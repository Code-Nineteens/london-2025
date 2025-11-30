//
//  ContextRetriever.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Combine

/// Intelligently retrieves relevant context for a given intent
@MainActor
final class ContextRetriever: ObservableObject {
    
    static let shared = ContextRetriever()
    
    // MARK: - Dependencies
    
    private let store = ContextStore.shared
    private let embeddingService = OpenAIEmbeddingService.shared
    private let collector = ContextCollector.shared
    
    // MARK: - Configuration
    
    private let maxResults = 10
    private let recencyWeight: Float = 0.3
    private let relevanceWeight: Float = 0.5
    private let entityWeight: Float = 0.2
    
    private init() {}
    
    // MARK: - Public API
    
    /// Retrieve relevant context for an intent (e.g., "wyślij maila do klienta ABC")
    func retrieve(intent: String) async -> [ContextChunk] {
        print("🎯 ContextRetriever: Searching for '\(intent)'")
        
        var candidates: [ContextChunk] = []
        
        // 1. Extract entities from intent
        let intentEntities = extractEntitiesFromIntent(intent)
        print("🎯 Extracted entities: \(intentEntities)")
        
        // 2. Semantic search if embeddings are available
        if await embeddingService.isConfigured {
            do {
                let queryEmbedding = try await embeddingService.embed(text: intent)
                let semanticResults = await store.searchSimilar(embedding: queryEmbedding, topK: 20)
                candidates.append(contentsOf: semanticResults)
                print("🎯 Semantic search found \(semanticResults.count) results")
            } catch {
                print("⚠️ Semantic search failed: \(error)")
            }
        }
        
        // 3. Text search as fallback/supplement
        do {
            // Search for key terms from intent
            let keyTerms = extractKeyTerms(from: intent)
            for term in keyTerms.prefix(3) {
                let textResults = try await store.searchText(query: term, limit: 10)
                candidates.append(contentsOf: textResults)
            }
        } catch {
            print("⚠️ Text search failed: \(error)")
        }
        
        // 4. Entity-based search
        for entity in intentEntities {
            do {
                let entityResults = try await store.getByEntity(type: entity.type, value: entity.value)
                candidates.append(contentsOf: entityResults)
                print("🎯 Entity search '\(entity.value)' found \(entityResults.count) results")
            } catch {
                print("⚠️ Entity search failed: \(error)")
            }
        }
        
        // 5. Recent context from relevant sources
        if intent.lowercased().contains("mail") || intent.lowercased().contains("email") {
            let recentMail = try? await store.getRecent(source: .mail, limit: 5)
            candidates.append(contentsOf: recentMail ?? [])
        }
        
        if intent.lowercased().contains("slack") || intent.lowercased().contains("message") {
            let recentSlack = try? await store.getRecent(source: .slack, limit: 5)
            candidates.append(contentsOf: recentSlack ?? [])
        }
        
        // Add some recent context regardless
        let recent = try? await store.getRecent(source: nil, limit: 10)
        candidates.append(contentsOf: recent ?? [])
        
        // 6. Deduplicate
        var seen = Set<UUID>()
        let unique = candidates.filter { chunk in
            if seen.contains(chunk.id) { return false }
            seen.insert(chunk.id)
            return true
        }
        
        // 7. Score and rank
        let scored = unique.map { chunk -> (chunk: ContextChunk, score: Float) in
            let recency = recencyScore(chunk.timestamp)
            let entityMatch = entityOverlapScore(intentEntities, chunk.entities)
            let topicMatch = topicMatchScore(intent, chunk)
            
            // Combine scores
            let score = recencyWeight * recency +
                        relevanceWeight * topicMatch +
                        entityWeight * entityMatch
            
            return (chunk, score)
        }
        
        // 8. Return top results
        let results = scored
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map(\.chunk)
        
        print("🎯 Returning \(results.count) relevant chunks")
        return Array(results)
    }
    
    /// Build context string for LLM from retrieved chunks
    func buildContextString(chunks: [ContextChunk]) -> String {
        guard !chunks.isEmpty else {
            return "No relevant context available."
        }
        
        var context = "RELEVANT CONTEXT:\n\n"
        
        for (index, chunk) in chunks.enumerated() {
            let timeAgo = formatTimeAgo(chunk.timestamp)
            let source = chunk.source.rawValue.capitalized
            
            context += "[\(index + 1)] [\(source)] (\(timeAgo))\n"
            context += chunk.content.prefix(500)
            
            if !chunk.entities.isEmpty {
                let entityStr = chunk.entities.map { "\($0.type.rawValue): \($0.value)" }.joined(separator: ", ")
                context += "\nEntities: \(entityStr)"
            }
            
            context += "\n\n"
        }
        
        return context
    }
    
    // MARK: - Private Helpers
    
    private func extractEntitiesFromIntent(_ intent: String) -> [Entity] {
        var entities: [Entity] = []
        
        // Simple pattern matching for common patterns
        let patterns: [(String, EntityType)] = [
            // "do klienta X", "do X"
            (#"do\s+(\w+)"#, .person),
            // "klient X", "klienta X"
            (#"klient[a]?\s+(\w+)"#, .person),
            // "projekt X"
            (#"projekt[u]?\s+(\w+)"#, .project),
            // "firma X"
            (#"firm[ay]?\s+(\w+)"#, .company),
        ]
        
        for (pattern, entityType) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(intent.startIndex..., in: intent)
                if let match = regex.firstMatch(in: intent, range: range) {
                    if match.numberOfRanges > 1,
                       let captureRange = Range(match.range(at: 1), in: intent) {
                        let value = String(intent[captureRange])
                        if value.count > 1 {
                            entities.append(Entity(type: entityType, value: value))
                        }
                    }
                }
            }
        }
        
        return entities
    }
    
    private func extractKeyTerms(from intent: String) -> [String] {
        let stopWords = Set(["do", "w", "z", "na", "i", "a", "the", "to", "of", "for", "in", "mail", "email", "wyślij", "napisz", "send", "write"])
        
        return intent
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
    
    private func recencyScore(_ timestamp: Date) -> Float {
        let age = Date().timeIntervalSince(timestamp)
        
        // Score decreases with age
        // 0-1 hour: 1.0
        // 1-24 hours: 0.8-0.5
        // 1-7 days: 0.5-0.2
        // older: 0.1
        
        let hours = age / 3600
        
        if hours < 1 { return 1.0 }
        if hours < 24 { return Float(0.8 - (hours / 24) * 0.3) }
        if hours < 168 { return Float(0.5 - (hours / 168) * 0.3) }
        return 0.1
    }
    
    private func entityOverlapScore(_ intentEntities: [Entity], _ chunkEntities: [Entity]) -> Float {
        guard !intentEntities.isEmpty else { return 0 }
        
        var matches = 0
        for intentEntity in intentEntities {
            for chunkEntity in chunkEntities {
                if intentEntity.type == chunkEntity.type &&
                   chunkEntity.value.localizedCaseInsensitiveContains(intentEntity.value) {
                    matches += 1
                    break
                }
            }
        }
        
        return Float(matches) / Float(intentEntities.count)
    }
    
    private func topicMatchScore(_ intent: String, _ chunk: ContextChunk) -> Float {
        let intentLower = intent.lowercased()
        var score: Float = 0.3 // Base score
        
        // Topic match
        if let topic = chunk.topic {
            if intentLower.contains(topic) || topic.contains(intentLower.prefix(5)) {
                score += 0.3
            }
        }
        
        // Content keyword overlap
        let intentWords = Set(intentLower.components(separatedBy: .whitespaces).filter { $0.count > 3 })
        let contentWords = Set(chunk.content.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 3 })
        let overlap = intentWords.intersection(contentWords)
        
        if !overlap.isEmpty {
            score += min(0.4, Float(overlap.count) * 0.1)
        }
        
        return min(1.0, score)
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

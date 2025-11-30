//
//  ContextCollector.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Combine
import Cocoa
import NaturalLanguage

/// Collects and enriches context from various sources
@MainActor
final class ContextCollector: ObservableObject {
    
    static let shared = ContextCollector()
    
    // MARK: - Dependencies
    
    private let store = ContextStore.shared
    private let embeddingService = OpenAIEmbeddingService.shared
    
    // MARK: - State
    
    @Published var isCollecting = false
    @Published var chunksCollected = 0
    @Published var lastError: String?
    
    /// Buffer for batching embedding requests
    private var pendingChunks: [ContextChunk] = []
    private var batchTimer: Timer?
    private let batchSize = 10
    private let batchDelay: TimeInterval = 2.0
    
    /// Deduplication cache (recent content hashes)
    private var recentHashes: Set<Int> = []
    private let maxHashCache = 1000
    
    /// Content similarity cache for near-duplicate detection
    private var recentContents: [String] = []
    private let maxRecentContents = 100
    private let similarityThreshold = 0.8
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start collecting context
    func startCollecting() async {
        guard !isCollecting else { return }
        isCollecting = true
        
        do {
            try await store.initialize()
            print("🔍 ContextCollector: Started")
        } catch {
            lastError = error.localizedDescription
            print("❌ ContextCollector: Failed to initialize - \(error)")
        }
    }
    
    /// Stop collecting
    func stopCollecting() {
        isCollecting = false
        batchTimer?.invalidate()
        batchTimer = nil
        
        // Process remaining pending chunks
        Task {
            await processPendingChunks()
        }
        
        print("🔍 ContextCollector: Stopped")
    }
    
    /// Collect context from an accessibility event
    func collectFromEvent(_ event: AXEvent) async {
        guard isCollecting else { return }
        guard let content = event.textContent, content.count >= 15 else { return }
        
        // Skip noise
        if isNoise(content) { return }
        
        // Deduplicate - exact match
        let hash = content.hashValue
        if recentHashes.contains(hash) { return }
        
        // Deduplicate - similarity check
        if isSimilarToRecent(content) { return }
        
        // Add to dedup caches
        recentHashes.insert(hash)
        if recentHashes.count > maxHashCache {
            recentHashes.removeFirst()
        }
        
        recentContents.append(content)
        if recentContents.count > maxRecentContents {
            recentContents.removeFirst()
        }
        
        // Extract entities
        let entities = extractEntities(from: content)
        
        // Classify topic
        let topic = classifyTopic(content: content, appName: event.appName)
        
        // Create chunk (without embedding yet)
        let chunk = ContextChunk(
            source: ContextSource.from(appName: event.appName),
            content: content,
            entities: entities,
            topic: topic,
            embedding: nil,
            metadata: [
                "app": event.appName,
                "role": event.elementRole ?? "",
                "action": event.actionType
            ]
        )
        
        // Add to pending batch
        pendingChunks.append(chunk)
        chunksCollected += 1
        
        // Schedule batch processing
        scheduleBatchProcessing()
    }
    
    /// Collect from clipboard
    func collectFromClipboard() async {
        guard isCollecting else { return }
        
        guard let content = NSPasteboard.general.string(forType: .string),
              content.count >= 10 else { return }
        
        // Skip noise
        if isNoise(content) { return }
        
        let entities = extractEntities(from: content)
        
        let chunk = ContextChunk(
            source: .clipboard,
            content: content,
            entities: entities,
            topic: nil,
            embedding: nil,
            metadata: [:]
        )
        
        pendingChunks.append(chunk)
        chunksCollected += 1
        scheduleBatchProcessing()
    }
    
    /// Collect from notification
    func collectFromNotification(title: String?, body: String?, app: String) async {
        guard isCollecting else { return }
        
        let content = [title, body].compactMap { $0 }.joined(separator: ": ")
        guard content.count >= 10 else { return }
        
        let entities = extractEntities(from: content)
        
        let chunk = ContextChunk(
            source: .notification,
            content: content,
            entities: entities,
            topic: nil,
            embedding: nil,
            metadata: ["app": app]
        )
        
        pendingChunks.append(chunk)
        chunksCollected += 1
        scheduleBatchProcessing()
    }
    
    // MARK: - Batch Processing
    
    private func scheduleBatchProcessing() {
        batchTimer?.invalidate()
        
        if pendingChunks.count >= batchSize {
            // Process immediately if batch is full
            Task {
                await processPendingChunks()
            }
        } else {
            // Schedule delayed processing
            batchTimer = Timer.scheduledTimer(withTimeInterval: batchDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    await self?.processPendingChunks()
                }
            }
        }
    }
    
    private func processPendingChunks() async {
        guard !pendingChunks.isEmpty else { return }
        
        let chunks = pendingChunks
        pendingChunks.removeAll()
        
        print("🔍 Processing batch of \(chunks.count) chunks...")
        
        // Generate embeddings in batch
        let texts = chunks.map(\.content)
        
        do {
            if await embeddingService.isConfigured {
                let embeddings = try await embeddingService.embedBatch(texts: texts)
                
                // Store chunks with embeddings
                for (index, chunk) in chunks.enumerated() {
                    let embedding = index < embeddings.count ? embeddings[index] : nil
                    let enrichedChunk = ContextChunk(
                        id: chunk.id,
                        timestamp: chunk.timestamp,
                        source: chunk.source,
                        content: chunk.content,
                        entities: chunk.entities,
                        topic: chunk.topic,
                        embedding: embedding,
                        metadata: chunk.metadata
                    )
                    try await store.insert(enrichedChunk)
                }
                
                print("🔍 Stored \(chunks.count) chunks with embeddings")
            } else {
                // Store without embeddings
                for chunk in chunks {
                    try await store.insert(chunk)
                }
                print("🔍 Stored \(chunks.count) chunks (no embeddings - API not configured)")
            }
        } catch {
            lastError = error.localizedDescription
            print("❌ Failed to process chunks: \(error)")
            
            // Still try to store without embeddings
            for chunk in chunks {
                try? await store.insert(chunk)
            }
        }
    }
    
    // MARK: - Entity Extraction
    
    private func extractEntities(from text: String) -> [Entity] {
        var entities: [Entity] = []
        
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag {
                let value = String(text[range])
                
                let entityType: EntityType
                switch tag {
                case .personalName:
                    entityType = .person
                case .organizationName:
                    entityType = .company
                case .placeName:
                    entityType = .location
                default:
                    return true
                }
                
                // Avoid duplicates
                if !entities.contains(where: { $0.value == value }) {
                    entities.append(Entity(type: entityType, value: value))
                }
            }
            return true
        }
        
        // Extract emails with regex
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                entities.append(Entity(type: .email, value: String(text[range])))
            }
        }
        
        // Extract money amounts (PLN, USD, EUR)
        let moneyPattern = #"[\d\s,.]+\s*(PLN|USD|EUR|zł|€|\$)"#
        if let regex = try? NSRegularExpression(pattern: moneyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                entities.append(Entity(type: .money, value: String(text[range])))
            }
        }
        
        return entities
    }
    
    // MARK: - Topic Classification
    
    private func classifyTopic(content: String, appName: String) -> String? {
        let contentLower = content.lowercased()
        
        // Finance keywords
        if contentLower.contains("faktura") || contentLower.contains("invoice") ||
           contentLower.contains("płatność") || contentLower.contains("payment") ||
           contentLower.contains("przelew") {
            return "finance"
        }
        
        // Meeting keywords
        if contentLower.contains("spotkanie") || contentLower.contains("meeting") ||
           contentLower.contains("call") || contentLower.contains("zoom") {
            return "meeting"
        }
        
        // Project keywords
        if contentLower.contains("projekt") || contentLower.contains("project") ||
           contentLower.contains("deadline") || contentLower.contains("termin") {
            return "project"
        }
        
        // Email keywords
        if contentLower.contains("mail") || contentLower.contains("email") ||
           appName == "Mail" {
            return "email"
        }
        
        return nil
    }
    
    /// Collect from UserActionMonitor event
    func collectFromUserAction(action: UserActionMonitor.UserAction) async {
        guard isCollecting else { return }
        
        let content = action.details
        guard content.count >= 15 else { return }
        
        // Skip noise
        if isNoise(content) { return }
        
        // Deduplicate
        let hash = content.hashValue
        if recentHashes.contains(hash) { return }
        if isSimilarToRecent(content) { return }
        
        recentHashes.insert(hash)
        recentContents.append(content)
        if recentContents.count > maxRecentContents {
            recentContents.removeFirst()
        }
        
        let entities = extractEntities(from: content)
        let topic = classifyTopic(content: content, appName: action.appName)
        
        let chunk = ContextChunk(
            source: ContextSource.from(appName: action.appName),
            content: content,
            entities: entities,
            topic: topic,
            embedding: nil,
            metadata: [
                "app": action.appName,
                "action_type": action.actionType.rawValue
            ]
        )
        
        pendingChunks.append(chunk)
        chunksCollected += 1
        scheduleBatchProcessing()
        
        print("🔍 Collected from \(action.appName): \(content.prefix(40))...")
    }
    
    // MARK: - Similarity Detection
    
    /// Check if content is similar to recently seen content
    private func isSimilarToRecent(_ content: String) -> Bool {
        let contentWords = Set(content.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 2 })
        
        for recent in recentContents.suffix(20) {
            let recentWords = Set(recent.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 2 })
            
            guard !contentWords.isEmpty && !recentWords.isEmpty else { continue }
            
            let intersection = contentWords.intersection(recentWords)
            let union = contentWords.union(recentWords)
            
            let similarity = Double(intersection.count) / Double(union.count)
            
            if similarity >= similarityThreshold {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Noise Filtering
    
    private func isNoise(_ content: String) -> Bool {
        let contentLower = content.lowercased()
        
        let noisePatterns = [
            "cursor", "focus", "scroll", "resize",
            "axfocused", "axvalue", "settings",
            "preference", "debug", "log(",
            "error:", "warning:", "info:",
            "<!doctype", "<html", "<script",
            "function()", "const ", "let ", "var ",
            "import ", "export ", "class "
        ]
        
        for pattern in noisePatterns {
            if contentLower.contains(pattern) {
                return true
            }
        }
        
        // Too short or too long (likely code/logs)
        if content.count < 20 || content.count > 5000 {
            return true
        }
        
        // Too many special characters (likely code)
        let specialChars = content.filter { "{}[]();=><".contains($0) }
        if Double(specialChars.count) / Double(content.count) > 0.1 {
            return true
        }
        
        return false
    }
}

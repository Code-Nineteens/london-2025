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
    private let userProfileManager = UserProfileManager.shared
    
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
    
    /// Collect from OCR screen capture (aggregated text from one scan)
    func collectFromOCR(text: String, appName: String) async {
        guard isCollecting else { 
            print("🔍 OCR SKIP: not collecting (isCollecting=false)")
            return 
        }
        guard text.count >= 50 else { 
            print("🔍 OCR SKIP: too short (\(text.count) chars)")
            return 
        }
        
        // Filter out garbage content
        if isOCRGarbage(text) {
            print("🔍 OCR SKIP: garbage content")
            return
        }
        
        // Simple deduplication
        let hash = text.hashValue
        if recentHashes.contains(hash) { 
            print("🔍 OCR SKIP: duplicate hash")
            return 
        }
        
        recentHashes.insert(hash)
        if recentHashes.count > maxHashCache {
            recentHashes.removeFirst()
        }
        
        var entities = extractEntities(from: text)
        let topic = classifyTopic(content: text, appName: appName)
        
        // Filter out user's own name from entities (don't treat self as contact)
        let userProfile = userProfileManager.profile
        entities = entities.filter { entity in
            if entity.type == .person && userProfile.isMe(entity.value) {
                return false
            }
            return true
        }
        
        // Log extracted entities
        if !entities.isEmpty {
            print("🔍 OCR: Extracted entities: \(entities.map { "\($0.type.rawValue): \($0.value)" }.joined(separator: ", "))")
            // Learn contacts from entities
            userProfileManager.learnFromEntities(entities)
        }
        if let topic = topic {
            print("🔍 OCR: Topic: \(topic)")
        }
        
        let chunk = ContextChunk(
            source: .ocr,
            content: text,
            entities: entities,
            topic: topic,
            embedding: nil,
            metadata: [
                "app": appName,
                "capture_type": "ocr_aggregate"
            ]
        )
        
        // Generate embedding and store
        print("🔍 OCR: Generating embedding...")
        do {
            var enrichedChunk = chunk
            
            // Try to generate embedding
            if await embeddingService.isConfigured {
                let embedding = try await embeddingService.embed(text: text)
                enrichedChunk = ContextChunk(
                    id: chunk.id,
                    timestamp: chunk.timestamp,
                    source: chunk.source,
                    content: chunk.content,
                    entities: chunk.entities,
                    topic: chunk.topic,
                    embedding: embedding,
                    metadata: chunk.metadata
                )
                print("🔍 OCR: ✅ Embedding generated")
            } else {
                print("🔍 OCR: ⚠️ No embedding API - saving without")
            }
            
            try await store.insert(enrichedChunk)
            chunksCollected += 1
            print("🔍 ✅ OCR saved from \(appName): \(text.prefix(50))...")
        } catch {
            print("🔍 ❌ OCR failed: \(error)")
            // Still try to save without embedding
            try? await store.insert(chunk)
        }
    }
    
    /// Check if OCR content is garbage (dev tools, SQL, system values)
    private func isOCRGarbage(_ text: String) -> Bool {
        let lower = text.lowercased()
        
        // ⚠️ SECURITY: Never capture API keys or secrets!
        if lower.contains("api_key") || lower.contains("api-key") { return true }
        if lower.contains("sk-ant-") || lower.contains("sk-proj-") { return true }
        if lower.contains("secret") || lower.contains("password=") { return true }
        if lower.contains("bearer ") || lower.contains("authorization:") { return true }
        
        // SQL queries
        if lower.contains("select ") && lower.contains(" from ") { return true }
        if lower.contains("insert into") { return true }
        
        // Dev tool / IDE markers (Windsurf, Cursor, VSCode)
        let devMarkers = [
            "claude opus", "thinking)", "accept file",
            "chiron", "axplayground", "localhost:", "sqlite3",
            "xcodebuild", "build succeeded", "build failed",
            "< > code", "code claude", ".swift",
            "emaildraftcomposer", "contextcollector",
            "ocr monitor", "screencapture",
            "-scheme", "xcode", ".env",
            "generate +", "message (%enter"
        ]
        for marker in devMarkers {
            if lower.contains(marker) { return true }
        }
        
        // System values patterns (lots of KB/s, MB, percentages)
        let systemPatterns = text.components(separatedBy: .whitespaces)
            .filter { $0.hasSuffix("KB/s") || $0.hasSuffix("MB/s") || $0.hasSuffix("MB") || $0.hasSuffix("%") }
        if systemPatterns.count > 3 { return true }
        
        // Touch ID / password dialogs
        if lower.contains("touch id") || lower.contains("podaj haslo") { return true }
        
        return false
    }
    
    /// Collect from notification
    func collectFromNotification(title: String?, body: String?, app: String) async {
        guard isCollecting else { return }

        let content = [title, body].compactMap { $0 }.joined(separator: ": ")
        guard content.count >= 10 else { return }

        let entities = extractEntities(from: content)

        // Determine the appropriate source based on app name
        // Discord notifications should use .discord for better filtering
        let source: ContextSource
        if app.lowercased() == "discord" {
            source = .discord
        } else if app.lowercased() == "slack" {
            source = .slack
        } else {
            source = .notification
        }

        let chunk = ContextChunk(
            source: source,
            content: content,
            entities: entities,
            topic: nil,
            embedding: nil,
            metadata: ["app": app]
        )

        print("📨 Storing notification from \(app) as source: \(source.rawValue)")
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
        
        // 1. Extract Slack-style names (e.g., "Kamil Moskała 7:10 PM", "Filip Wnęk")
        extractSlackNames(from: text, into: &entities)
        
        // 2. Extract DM/Channel names from Slack OCR
        extractSlackContext(from: text, into: &entities)
        
        // 3. Apple NLTagger for general names
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
                
                // Avoid duplicates (case insensitive)
                if !entities.contains(where: { $0.value.lowercased() == value.lowercased() }) {
                    entities.append(Entity(type: entityType, value: value))
                }
            }
            return true
        }
        
        // 4. Extract emails with regex
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                entities.append(Entity(type: .email, value: String(text[range])))
            }
        }
        
        // 5. Extract money amounts (PLN, USD, EUR)
        let moneyPattern = #"[\d\s,.]+\s*(PLN|USD|EUR|zł|€|\$)"#
        if let regex = try? NSRegularExpression(pattern: moneyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                entities.append(Entity(type: .money, value: String(text[range])))
            }
        }
        
        // 6. Extract Polish-style names (Imię Nazwisko pattern)
        extractPolishNames(from: text, into: &entities)
        
        return entities
    }
    
    /// Extract names from Slack message format (e.g., "Kamil Moskała 7:10 PM")
    private func extractSlackNames(from text: String, into entities: inout [Entity]) {
        // Pattern: Name Surname followed by time (e.g., "Kamil Moskała 7:10 PM")
        let slackNamePattern = #"([A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+\s+[A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+)\s+\d{1,2}:\d{2}\s*(AM|PM)?"#
        
        if let regex = try? NSRegularExpression(pattern: slackNamePattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: text) {
                    let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                    if !entities.contains(where: { $0.value.lowercased() == name.lowercased() }) {
                        entities.append(Entity(type: .person, value: name, confidence: 0.9))
                    }
                }
            }
        }
    }
    
    /// Extract Slack DM/Channel context
    private func extractSlackContext(from text: String, into entities: inout [Entity]) {
        // Look for DM indicator: ". Name Surname" at start or "Message to Name"
        let dmPatterns = [
            #"\.\s*([A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+\s+[A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+)"#, // ". Kamil Moskała"
            #"Message to\s+([A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+(?:\s+[A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+)?)"#, // "Message to Kamil"
        ]
        
        for pattern in dmPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if match.numberOfRanges > 1,
                       let nameRange = Range(match.range(at: 1), in: text) {
                        let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                        if !entities.contains(where: { $0.value.lowercased() == name.lowercased() }) {
                            entities.append(Entity(type: .person, value: name, confidence: 0.95))
                        }
                    }
                }
            }
        }
        
        // Extract channel names: "# channelname"
        let channelPattern = #"#\s*([a-z0-9_-]+)"#
        if let regex = try? NSRegularExpression(pattern: channelPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if match.numberOfRanges > 1,
                   let channelRange = Range(match.range(at: 1), in: text) {
                    let channel = String(text[channelRange])
                    if channel != "general" && !entities.contains(where: { $0.value == channel }) {
                        entities.append(Entity(type: .project, value: channel, confidence: 0.8))
                    }
                }
            }
        }
    }
    
    /// Extract Polish-style names (capitalized word pairs)
    private func extractPolishNames(from text: String, into entities: inout [Entity]) {
        // Common Polish first names to help identify name patterns
        let commonFirstNames = Set(["Adam", "Kamil", "Filip", "Piotr", "Marcin", "Tomasz", "Michał", 
                                     "Krzysztof", "Paweł", "Anna", "Maria", "Katarzyna", "Monika",
                                     "Agnieszka", "Ewa", "Bart", "Bartek"])
        
        // Pattern: Two capitalized words that might be a name
        let namePattern = #"\b([A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+)\s+([A-ZŻŹĆĄŚĘŁÓŃ][a-zżźćąśęłóń]+)\b"#
        
        if let regex = try? NSRegularExpression(pattern: namePattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if match.numberOfRanges > 2,
                   let firstRange = Range(match.range(at: 1), in: text),
                   let lastRange = Range(match.range(at: 2), in: text) {
                    let firstName = String(text[firstRange])
                    let lastName = String(text[lastRange])
                    let fullName = "\(firstName) \(lastName)"
                    
                    // Check if first name looks like a common name
                    if commonFirstNames.contains(firstName) || commonFirstNames.contains(String(firstName.prefix(4))) {
                        if !entities.contains(where: { $0.value.lowercased() == fullName.lowercased() }) {
                            entities.append(Entity(type: .person, value: fullName, confidence: 0.85))
                        }
                    }
                }
            }
        }
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
        guard isCollecting else { 
            print("🔍 SKIP: not collecting")
            return 
        }
        
        let content = action.details
        guard content.count >= 15 else { 
            print("🔍 SKIP: too short (\(content.count) chars): \(content.prefix(30))")
            return 
        }
        
        // Skip noise
        if isNoise(content) { 
            print("🔍 SKIP: noise detected: \(content.prefix(50))")
            return 
        }
        
        // Deduplicate
        let hash = content.hashValue
        if recentHashes.contains(hash) { 
            print("🔍 SKIP: duplicate hash")
            return 
        }
        if isSimilarToRecent(content) { 
            print("🔍 SKIP: similar to recent")
            return 
        }
        
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
        
        // Very specific noise patterns (less aggressive)
        let noisePatterns = [
            "axfocused", "axvalue",
            "<!doctype", "<html", "<script",
            "function()", "console.log"
        ]
        
        for pattern in noisePatterns {
            if contentLower.contains(pattern) {
                return true
            }
        }
        
        // Too long (likely code dump)
        if content.count > 5000 {
            return true
        }
        
        // Too many special characters (likely code) - 15% threshold instead of 10%
        let specialChars = content.filter { "{}[]();=><".contains($0) }
        if Double(specialChars.count) / Double(content.count) > 0.15 {
            return true
        }
        
        return false
    }
}

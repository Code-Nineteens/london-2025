//
//  ContextStore.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import SQLite3

/// SQLite-based storage for context chunks with vector similarity search
actor ContextStore {
    
    static let shared = ContextStore()
    
    // MARK: - Configuration
    
    private let maxCacheSize = 5000
    private let dbFileName = "context_store.sqlite"
    
    // MARK: - State
    
    private var db: OpaquePointer?
    private var embeddingCache: [(id: UUID, embedding: [Float], chunk: ContextChunk)] = []
    private var isInitialized = false
    
    private init() {}
    
    // MARK: - Initialization
    
    func initialize() async throws {
        guard !isInitialized else { return }
        
        let dbPath = getDBPath()
        print("📦 ContextStore: Opening database at \(dbPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw StoreError.failedToOpen
        }
        
        try createTables()
        try rebuildFTSIndex()
        try await loadEmbeddingCache()
        
        isInitialized = true
        print("📦 ContextStore: Initialized with \(embeddingCache.count) cached embeddings")
    }
    
    private func getDBPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AxPlayground", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        return appDir.appendingPathComponent(dbFileName).path
    }
    
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS context_chunks (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            source TEXT NOT NULL,
            content TEXT NOT NULL,
            entities TEXT,
            topic TEXT,
            embedding BLOB,
            metadata TEXT,
            created_at REAL DEFAULT (julianday('now'))
        );
        
        CREATE INDEX IF NOT EXISTS idx_timestamp ON context_chunks(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_source ON context_chunks(source);
        CREATE INDEX IF NOT EXISTS idx_topic ON context_chunks(topic);
        
        CREATE VIRTUAL TABLE IF NOT EXISTS context_fts USING fts5(
            content,
            content='context_chunks',
            content_rowid='rowid'
        );
        
        -- Triggers to keep FTS in sync
        CREATE TRIGGER IF NOT EXISTS context_fts_insert AFTER INSERT ON context_chunks BEGIN
            INSERT INTO context_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
        END;
        
        CREATE TRIGGER IF NOT EXISTS context_fts_delete AFTER DELETE ON context_chunks BEGIN
            INSERT INTO context_fts(context_fts, rowid, content) VALUES('delete', OLD.rowid, OLD.content);
        END;
        
        CREATE TRIGGER IF NOT EXISTS context_fts_update AFTER UPDATE ON context_chunks BEGIN
            INSERT INTO context_fts(context_fts, rowid, content) VALUES('delete', OLD.rowid, OLD.content);
            INSERT INTO context_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
        END;
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw StoreError.sqlError(error)
        }
    }
    
    /// Rebuild FTS index from existing data
    private func rebuildFTSIndex() throws {
        // First clear FTS
        let clearSQL = "DELETE FROM context_fts;"
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, clearSQL, nil, nil, &errMsg)
        
        // Then repopulate from context_chunks
        let rebuildSQL = """
        INSERT INTO context_fts(rowid, content) 
        SELECT rowid, content FROM context_chunks;
        """
        
        if sqlite3_exec(db, rebuildSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            print("⚠️ FTS rebuild warning: \(error)")
            // Don't throw - FTS is supplementary
        } else {
            print("📦 FTS index rebuilt")
        }
    }
    
    // MARK: - Insert
    
    func insert(_ chunk: ContextChunk) async throws {
        try await ensureInitialized()
        
        let sql = """
        INSERT OR REPLACE INTO context_chunks 
        (id, timestamp, source, content, entities, topic, embedding, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError("Failed to prepare insert")
        }
        defer { sqlite3_finalize(stmt) }
        
        let idStr = chunk.id.uuidString
        let timestamp = chunk.timestamp.timeIntervalSince1970
        let sourceStr = chunk.source.rawValue
        let entitiesJson = try JSONEncoder().encode(chunk.entities)
        let metadataJson = try JSONEncoder().encode(chunk.metadata)
        let embeddingData = chunk.embedding.map { embedding -> Data in
            var floats = embedding
            return Data(bytes: &floats, count: floats.count * MemoryLayout<Float>.size)
        }
        
        sqlite3_bind_text(stmt, 1, idStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, timestamp)
        sqlite3_bind_text(stmt, 3, sourceStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, chunk.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, String(data: entitiesJson, encoding: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, chunk.topic, -1, SQLITE_TRANSIENT)
        
        if let data = embeddingData {
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 7, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_text(stmt, 8, String(data: metadataJson, encoding: .utf8), -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError("Failed to insert")
        }
        
        // Update cache
        if let embedding = chunk.embedding {
            embeddingCache.append((chunk.id, embedding, chunk))
            
            // Trim cache if needed
            if embeddingCache.count > maxCacheSize {
                embeddingCache.removeFirst(embeddingCache.count - maxCacheSize)
            }
        }
        
        print("📦 Inserted chunk: \(chunk.source.rawValue) - \(chunk.content.prefix(50))...")
    }
    
    // MARK: - Search
    
    /// Semantic similarity search using embeddings
    func searchSimilar(embedding: [Float], topK: Int = 10) async -> [ContextChunk] {
        return embeddingCache
            .map { item in
                let similarity = cosineSimilarity(embedding, item.embedding)
                return (chunk: item.chunk, score: similarity)
            }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map(\.chunk)
    }
    
    /// Full-text search
    func searchText(query: String, limit: Int = 20) async throws -> [ContextChunk] {
        try await ensureInitialized()
        
        // Simple LIKE search (FTS would be better but more complex setup)
        let sql = """
        SELECT id, timestamp, source, content, entities, topic, embedding, metadata
        FROM context_chunks
        WHERE content LIKE ?
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError("Failed to prepare search")
        }
        defer { sqlite3_finalize(stmt) }
        
        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        
        var results: [ContextChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                results.append(chunk)
            }
        }
        
        return results
    }
    
    /// Get recent chunks from specific source
    func getRecent(source: ContextSource? = nil, limit: Int = 50) async throws -> [ContextChunk] {
        try await ensureInitialized()
        
        let sql: String
        if let source = source {
            sql = """
            SELECT id, timestamp, source, content, entities, topic, embedding, metadata
            FROM context_chunks
            WHERE source = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """
        } else {
            sql = """
            SELECT id, timestamp, source, content, entities, topic, embedding, metadata
            FROM context_chunks
            ORDER BY timestamp DESC
            LIMIT ?
            """
        }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError("Failed to prepare query")
        }
        defer { sqlite3_finalize(stmt) }
        
        if let source = source {
            sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
        
        var results: [ContextChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                results.append(chunk)
            }
        }
        
        return results
    }
    
    /// Get chunks containing specific entity
    func getByEntity(type: EntityType, value: String) async throws -> [ContextChunk] {
        try await ensureInitialized()
        
        // Search in entities JSON
        let sql = """
        SELECT id, timestamp, source, content, entities, topic, embedding, metadata
        FROM context_chunks
        WHERE entities LIKE ?
        ORDER BY timestamp DESC
        LIMIT 50
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError("Failed to prepare entity search")
        }
        defer { sqlite3_finalize(stmt) }
        
        let pattern = "%\(value)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        
        var results: [ContextChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                // Double-check entity match
                if chunk.entities.contains(where: { $0.type == type && $0.value.localizedCaseInsensitiveContains(value) }) {
                    results.append(chunk)
                }
            }
        }
        
        return results
    }
    
    // MARK: - Maintenance
    
    /// Delete chunks older than specified days
    func pruneOlderThan(days: Int) async throws {
        try await ensureInitialized()
        
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let sql = "DELETE FROM context_chunks WHERE timestamp < ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError("Failed to prepare prune")
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError("Failed to prune")
        }
        
        let deleted = sqlite3_changes(db)
        print("📦 Pruned \(deleted) old chunks")
        
        // Reload cache
        try await loadEmbeddingCache()
    }
    
    /// Get total chunk count
    func count() async throws -> Int {
        try await ensureInitialized()
        
        let sql = "SELECT COUNT(*) FROM context_chunks"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    // MARK: - Private Helpers
    
    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }
    
    private func loadEmbeddingCache() async throws {
        embeddingCache.removeAll()
        
        let sql = """
        SELECT id, timestamp, source, content, entities, topic, embedding, metadata
        FROM context_chunks
        WHERE embedding IS NOT NULL
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(maxCacheSize))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt), let embedding = chunk.embedding {
                embeddingCache.append((chunk.id, embedding, chunk))
            }
        }
    }
    
    private func parseChunkRow(_ stmt: OpaquePointer?) -> ContextChunk? {
        guard let stmt = stmt else { return nil }
        
        guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr) else { return nil }
        
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let sourceStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let source = ContextSource(rawValue: sourceStr) ?? .unknown
        let content = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
        
        var entities: [Entity] = []
        if let entitiesStr = sqlite3_column_text(stmt, 4).map({ String(cString: $0) }),
           let data = entitiesStr.data(using: .utf8) {
            entities = (try? JSONDecoder().decode([Entity].self, from: data)) ?? []
        }
        
        let topic = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        
        var embedding: [Float]?
        let blobSize = sqlite3_column_bytes(stmt, 6)
        if blobSize > 0, let blobPtr = sqlite3_column_blob(stmt, 6) {
            let floatCount = Int(blobSize) / MemoryLayout<Float>.size
            embedding = Array(UnsafeBufferPointer(start: blobPtr.assumingMemoryBound(to: Float.self), count: floatCount))
        }
        
        var metadata: [String: String] = [:]
        if let metaStr = sqlite3_column_text(stmt, 7).map({ String(cString: $0) }),
           let data = metaStr.data(using: .utf8) {
            metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        
        return ContextChunk(
            id: id,
            timestamp: timestamp,
            source: source,
            content: content,
            entities: entities,
            topic: topic,
            embedding: embedding,
            metadata: metadata
        )
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magA) * sqrt(magB)
        return magnitude > 0 ? dot / magnitude : 0
    }
    
    // MARK: - Errors
    
    enum StoreError: Error {
        case failedToOpen
        case sqlError(String)
        case notInitialized
    }
}

// SQLite constants
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

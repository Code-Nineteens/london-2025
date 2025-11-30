//
//  ContextChunk.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation

/// A chunk of context data with embedding for semantic search
struct ContextChunk: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let source: ContextSource
    let content: String
    let entities: [Entity]
    let topic: String?
    let embedding: [Float]?
    let metadata: [String: String]
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: ContextSource,
        content: String,
        entities: [Entity] = [],
        topic: String? = nil,
        embedding: [Float]? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.entities = entities
        self.topic = topic
        self.embedding = embedding
        self.metadata = metadata
    }
}

/// Source of context data
enum ContextSource: String, Codable, Sendable {
    case slack
    case mail
    case calendar
    case notes
    case clipboard
    case browser
    case terminal
    case document
    case accessibility
    case notification
    case unknown
    
    /// Map app name to context source
    static func from(appName: String) -> ContextSource {
        switch appName.lowercased() {
        case "slack": return .slack
        case "mail": return .mail
        case "calendar": return .calendar
        case "notes": return .notes
        case "safari", "chrome", "firefox", "arc": return .browser
        case "terminal", "iterm", "warp": return .terminal
        case "pages", "word", "google docs": return .document
        default: return .accessibility
        }
    }
}

/// Named entity extracted from text
struct Entity: Codable, Sendable, Hashable {
    let type: EntityType
    let value: String
    let confidence: Float
    
    init(type: EntityType, value: String, confidence: Float = 1.0) {
        self.type = type
        self.value = value
        self.confidence = confidence
    }
}

enum EntityType: String, Codable, Sendable {
    case person
    case company
    case project
    case date
    case money
    case email
    case phone
    case location
    case other
}

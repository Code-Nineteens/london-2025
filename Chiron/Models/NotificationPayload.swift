//
//  NotificationPayload.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Foundation

/// Payload for AI-triggered automation suggestions
struct NotificationPayload: Codable, Sendable {
    /// Short description of inferred user intent
    let task: String
    
    /// Confidence score 0.0-1.0
    let confidence: Double
    
    /// What could be automated
    let suggestedAction: String
    
    /// 1-2 sentences explaining why this is actionable
    let reason: String
    
    /// Context about the active app and UI element
    let appContext: AppContext
    
    /// Timestamp when this was generated
    let timestamp: Date
    
    struct AppContext: Codable, Sendable {
        let appName: String
        let elementRole: String?
        let elementTitle: String?
    }
    
    /// Check if confidence is high enough to show
    var isActionable: Bool {
        confidence >= 0.6
    }
}

/// System state snapshot for LLM context
struct SystemState: Sendable {
    let activeApp: String
    let activeElement: String?
    let recentTexts: [String]
    let lastActions: [String]
    let timestamp: Date
    
    init(
        activeApp: String = "",
        activeElement: String? = nil,
        recentTexts: [String] = [],
        lastActions: [String] = []
    ) {
        self.activeApp = activeApp
        self.activeElement = activeElement
        self.recentTexts = recentTexts
        self.lastActions = lastActions
        self.timestamp = Date()
    }
}

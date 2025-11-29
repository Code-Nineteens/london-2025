//
//  AutomationSuggestionService.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Foundation
import Combine

/// Main service for automation suggestions - integrates intent analysis with notifications
@MainActor
final class AutomationSuggestionService: ObservableObject {
    
    static let shared = AutomationSuggestionService()
    
    // MARK: - Dependencies
    
    private let intentAnalyzer = IntentAnalyzer.shared
    private let notificationManager = NotificationManager.shared
    
    // MARK: - State
    
    @Published var isEnabled = false
    @Published var isProcessing = false
    @Published var lastSuggestion: NotificationPayload?
    @Published var suggestionHistory: [NotificationPayload] = []
    
    /// Statistics
    @Published var eventsProcessed = 0
    @Published var suggestionsGenerated = 0
    
    private init() {}
    
    // MARK: - Public API
    
    /// Enable/disable automation suggestions
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            print("🤖 Automation suggestions enabled")
        } else {
            print("🤖 Automation suggestions disabled")
        }
    }
    
    /// Configure API key
    func configureAPIKey(_ key: String) async {
        await AnthropicClient.shared.setAPIKey(key)
        print("🔑 API key configured")
    }
    
    /// Check if service is ready
    var isReady: Bool {
        get async {
            await AnthropicClient.shared.isConfigured
        }
    }
    
    /// Process an action and potentially show suggestion
    func processAction(actionType: String, appName: String, details: String) async {
        guard isEnabled else { return }
        
        eventsProcessed += 1
        isProcessing = true
        defer { isProcessing = false }
        
        guard let payload = await intentAnalyzer.processAction(
            actionType: actionType,
            appName: appName,
            details: details
        ) else {
            return
        }
        
        // Show notification
        showSuggestionNotification(payload)
        
        // Update state
        lastSuggestion = payload
        suggestionHistory.insert(payload, at: 0)
        suggestionsGenerated += 1
        
        // Keep history limited
        if suggestionHistory.count > 50 {
            suggestionHistory = Array(suggestionHistory.prefix(50))
        }
    }
    
    /// Process text change event
    func processTextChange(text: String, app: String) async {
        guard isEnabled else { return }
        
        let event = AXEvent(
            actionType: "text_added",
            appName: app,
            elementRole: "AXTextArea",
            textContent: text
        )
        
        eventsProcessed += 1
        isProcessing = true
        defer { isProcessing = false }
        
        guard let payload = await intentAnalyzer.processEvent(event) else {
            return
        }
        
        showSuggestionNotification(payload)
        lastSuggestion = payload
        suggestionHistory.insert(payload, at: 0)
        suggestionsGenerated += 1
    }
    
    // MARK: - Notification Display
    
    private func showSuggestionNotification(_ payload: NotificationPayload) {
        let confidenceEmoji = payload.confidence >= 0.8 ? "🎯" : "💡"
        
        notificationManager.show(
            title: "\(confidenceEmoji) \(payload.task)",
            message: "\(payload.suggestedAction)\n\n\(payload.reason)",
            icon: "wand.and.stars"
        )
        
        print("🤖 Suggestion: \(payload.task) (confidence: \(String(format: "%.0f", payload.confidence * 100))%)")
    }
    
    // MARK: - Utility
    
    /// Clear history
    func clearHistory() {
        suggestionHistory.removeAll()
        eventsProcessed = 0
        suggestionsGenerated = 0
    }
    
    /// Get statistics
    var statistics: String {
        let rate = eventsProcessed > 0 ? Double(suggestionsGenerated) / Double(eventsProcessed) * 100 : 0
        return "Events: \(eventsProcessed) | Suggestions: \(suggestionsGenerated) | Rate: \(String(format: "%.1f", rate))%"
    }
}

// MARK: - Integration Helper

extension AutomationSuggestionService {
    
    /// Main entry point function as specified
    func shouldTriggerNotification(
        events: [AXEvent],
        systemState: SystemState
    ) async -> NotificationPayload? {
        guard isEnabled else { return nil }
        
        // Process each event through the analyzer
        for event in events.suffix(5) {
            if let payload = await intentAnalyzer.processEvent(event) {
                return payload
            }
        }
        
        return nil
    }
}

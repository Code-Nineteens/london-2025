//
//  IntentAnalyzer.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Foundation
import Combine

/// Analyzes accessibility events to detect user intent and trigger automation suggestions
@MainActor
final class IntentAnalyzer: ObservableObject {
    
    static let shared = IntentAnalyzer()
    
    // MARK: - Configuration
    
    /// Minimum score from heuristics to trigger LLM call (raised for less noise)
    private let heuristicThreshold: Double = 0.6
    
    /// Minimum confidence from LLM to show notification
    private let notificationThreshold: Double = 0.7
    
    /// Buffer size for recent events
    private let maxBufferSize = 100
    
    /// Cooldown between notifications (seconds) - increased to avoid spam
    private let notificationCooldown: TimeInterval = 30.0
    
    /// Minimum text length to consider meaningful
    private let minActionableTextLength = 30
    
    // MARK: - State
    
    private var eventBuffer: [BufferedEvent] = []
    private var lastNotificationTime: Date?
    private var systemState = SystemState()
    
    @Published var isAnalyzing = false
    @Published var lastPayload: NotificationPayload?
    
    // MARK: - LLM Client
    
    private let llmClient = AnthropicClient.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Main entry point - process an event and potentially trigger notification
    func processEvent(_ event: AXEvent) async -> NotificationPayload? {
        print("")
        print("═══════════════════════════════════════════════════")
        print("📥 NEW EVENT RECEIVED")
        print("   App: \(event.appName)")
        print("   ActionType: \(event.actionType)")
        print("   TextContent: \(event.textContent?.prefix(100) ?? "nil")")
        print("═══════════════════════════════════════════════════")
        
        // Add to buffer
        addToBuffer(event)
        print("📦 Buffer size: \(eventBuffer.count)")
        
        // Update system state
        updateSystemState(with: event)
        
        // Cooldown disabled - analyze every event
        print("⏱️ No cooldown (disabled)")
        
        // Pre-filter with heuristics
        let heuristicScore = computeHeuristicScore()
        print("📊 Heuristic score: \(String(format: "%.2f", heuristicScore)) (threshold: \(heuristicThreshold))")
        
        guard heuristicScore >= heuristicThreshold else {
            print("❌ BLOCKED: Score too low")
            return nil
        }
        
        print("✅ Passed heuristics - calling API...")

        // Call API for intent analysis
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let content = event.textContent, !content.isEmpty else {
            print("❌ No text content to analyze")
            return nil
        }

        guard let payload = await analyzeIntent(content: content) else {
            print("❌ LLM returned nil (should_trigger was false or error)")
            return nil
        }
        
        print("📋 LLM RETURNED PAYLOAD:")
        print("   task: \(payload.task)")
        print("   confidence: \(payload.confidence)")
        print("   suggestedAction: \(payload.suggestedAction)")
        print("   isActionable: \(payload.isActionable) (needs >= 0.6)")
        
        // Check if actionable
        guard payload.isActionable else {
            print("❌ BLOCKED: Confidence \(payload.confidence) < 0.6")
            return nil
        }
        
        // Update state and return
        lastNotificationTime = Date()
        lastPayload = payload
        
        print("🔔 NOTIFICATION WILL BE SHOWN!")
        print("═══════════════════════════════════════════════════")
        print("")
        
        return payload
    }
    
    /// Process a simple action dictionary
    func processAction(
        actionType: String,
        appName: String,
        details: String
    ) async -> NotificationPayload? {
        let event = AXEvent(
            actionType: actionType,
            appName: appName,
            elementRole: nil,
            textContent: details
        )
        return await processEvent(event)
    }
    
    /// Get recent events from buffer (for email composition)
    func getRecentEvents() -> [AXEvent] {
        return eventBuffer.suffix(50).map { $0.event }
    }
    
    /// Get current system state (for email composition)
    func getCurrentSystemState() -> SystemState {
        return systemState
    }
    
    // MARK: - Event Buffer
    
    private func addToBuffer(_ event: AXEvent) {
        let buffered = BufferedEvent(event: event, timestamp: Date())
        eventBuffer.append(buffered)
        
        // Trim buffer
        if eventBuffer.count > maxBufferSize {
            eventBuffer.removeFirst(eventBuffer.count - maxBufferSize)
        }
    }
    
    private func updateSystemState(with event: AXEvent) {
        systemState = SystemState(
            activeApp: event.appName,
            activeElement: event.elementRole,
            recentTexts: getRecentTexts(),
            lastActions: getRecentActions()
        )
    }
    
    private func getRecentTexts() -> [String] {
        eventBuffer
            .suffix(20)
            .compactMap { $0.event.textContent }
            .filter { !$0.isEmpty && $0.count > 5 }
    }
    
    private func getRecentActions() -> [String] {
        eventBuffer
            .suffix(10)
            .map { $0.event.actionType }
    }
    
    // MARK: - Heuristic Scoring
    
    /// Pre-filter with MINIMAL heuristics - let LLM decide if actionable
    /// Only filter out obvious non-actionable cases
    private func computeHeuristicScore() -> Double {
        var score = 0.0
        
        let recentEvents = eventBuffer.suffix(15)
        guard !recentEvents.isEmpty else { return 0.0 }
        
        let allTexts = recentEvents.compactMap { $0.event.textContent }
        
        // === MINIMAL FILTERS (let LLM decide the rest) ===
        
        // 1. Must have SOME text content to analyze
        guard !allTexts.isEmpty else { return 0.0 }
        
        // 2. System apps - never actionable
        let systemApps = ["Finder", "System Preferences", "System Settings", "Activity Monitor", "Spotlight"]
        if systemApps.contains(systemState.activeApp) { return 0.0 }
        
        // 3. Must have meaningful text (at least 10 chars total)
        let totalTextLength = allTexts.map { $0.count }.reduce(0, +)
        if totalTextLength < 10 { return 0.0 }
        
        // === SCORING (determines if we call LLM) ===
        
        // 4. Has text content = worth checking with LLM
        score += 0.5
        
        // 5. User is actively typing
        let typingEvents = recentEvents.filter { 
            $0.event.actionType.contains("ValueChanged") ||
            $0.event.actionType.contains("text_")
        }
        if typingEvents.count >= 2 { score += 0.2 }
        
        // 6. High-value communication apps
        let communicationApps = ["Mail", "Slack", "Messages", "Notes", "Teams", "Discord"]
        if communicationApps.contains(systemState.activeApp) {
            score += 0.2
        }
        
        // 7. In text input field
        let inputRoles = ["AXTextArea", "AXTextField"]
        if let role = systemState.activeElement, inputRoles.contains(role) {
            score += 0.1
        }
        
        return max(0.0, min(1.0, score))
    }
    
    // MARK: - API Analysis

    private func analyzeIntent(content: String) async -> NotificationPayload? {
        guard let url = URL(string: "https://iteratehack-code-19.hf.space/action") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["message": content]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String,
                  let score = json["score"] as? Double else {
                print("❌ Failed to parse API response")
                return nil
            }

            print("✅ API Response: action=\(action), score=\(score)")

            return NotificationPayload(
                task: action,
                confidence: score,
                suggestedAction: "Perform \(action) action",
                reason: "Detected intent from your recent activity",
                appContext: NotificationPayload.AppContext(
                    appName: systemState.activeApp,
                    elementRole: systemState.activeElement,
                    elementTitle: nil
                ),
                timestamp: Date()
            )
        } catch {
            print("❌ API request failed: \(error)")
            return nil
        }
    }
    
    private func buildLLMContext() -> String {
        let recentEvents = eventBuffer.suffix(20)
        
        var context = """
        SYSTEM STATE:
        Active App: \(systemState.activeApp)
        Active Element: \(systemState.activeElement ?? "unknown")
        
        RECENT EVENTS (last 20):
        """
        
        for buffered in recentEvents {
            let event = buffered.event
            var line = "[\(event.actionType)] App: \(event.appName)"
            if let role = event.elementRole {
                line += " | Role: \(role)"
            }
            if let text = event.textContent, !text.isEmpty {
                let truncated = String(text.prefix(100))
                line += " | Text: \"\(truncated)\""
            }
            context += "\n- \(line)"
        }
        
        if !systemState.recentTexts.isEmpty {
            context += "\n\nRECENT TEXT CONTENT:\n"
            for text in systemState.recentTexts.prefix(5) {
                let truncated = String(text.prefix(200))
                context += "- \"\(truncated)\"\n"
            }
        }
        
        return context
    }
}

// MARK: - Supporting Types

/// Wrapper for buffered events with timestamp
private struct BufferedEvent {
    let event: AXEvent
    let timestamp: Date
}

/// Unified event type for analysis
struct AXEvent: Sendable {
    let actionType: String
    let appName: String
    let elementRole: String?
    let elementTitle: String?
    let textContent: String?
    let timestamp: Date
    
    /// Initialize from details string (parses "Role: X | Element: Y | Value: Z" format)
    init(fromDetails details: String, actionType: String, appName: String, timestamp: Date = Date()) {
        self.actionType = actionType
        self.appName = appName
        self.timestamp = timestamp
        
        if details.contains("Role:") {
            let components = details.components(separatedBy: "|")
            self.elementRole = components.first { $0.contains("Role:") }?
                .replacingOccurrences(of: "Role:", with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces)
            self.elementTitle = components.first { $0.contains("Element:") }?
                .replacingOccurrences(of: "Element:", with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces)
            self.textContent = components.first { $0.contains("Value:") }?
                .replacingOccurrences(of: "Value:", with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces)
        } else {
            self.elementRole = nil
            self.elementTitle = nil
            self.textContent = details.isEmpty ? nil : details
        }
    }
    
    /// Direct initialization
    init(
        actionType: String,
        appName: String,
        elementRole: String? = nil,
        elementTitle: String? = nil,
        textContent: String? = nil,
        timestamp: Date = Date()
    ) {
        self.actionType = actionType
        self.appName = appName
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.textContent = textContent
        self.timestamp = timestamp
    }
}

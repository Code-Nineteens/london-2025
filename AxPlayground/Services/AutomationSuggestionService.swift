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
    private let emailDraftComposer = EmailDraftComposer.shared
    
    // MARK: - State
    
    @Published var isEnabled = false
    @Published var isProcessing = false
    @Published var lastSuggestion: NotificationPayload?
    @Published var suggestionHistory: [NotificationPayload] = []
    @Published var lastEmailDraft: EmailDraftPayload?
    
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

        // Skip NONE actions - don't show notification
        if payload.task.uppercased() == "NONE" || payload.suggestedAction.uppercased() == "NONE" {
            print("🔷 Skipping NONE action - no notification")
            return
        }

        print("")
        print("🔷🔷🔷 AutomationSuggestionService.processAction 🔷🔷🔷")
        print("   📋 Notification Content:")
        print("      task: \(payload.task)")
        print("      confidence: \(String(format: "%.0f", payload.confidence * 100))%")
        print("      suggestedAction: \(payload.suggestedAction)")
        print("      reason: \(payload.reason)")
        print("      appContext: \(payload.appContext.appName)")

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
        DispatchQueue.main.async { [self] in
            lastSuggestion = payload
            suggestionHistory.insert(payload, at: 0)
            suggestionsGenerated += 1
        }
    }
    
    // MARK: - Notification Display
    
    private func showSuggestionNotification(_ payload: NotificationPayload) {
        DispatchQueue.main.async { [self] in
            let confidenceEmoji = payload.confidence >= 0.8 ? "🎯" : "💡"
            
            // Determine action based on task type
            let action = determineAction(for: payload)
            
            notificationManager.show(
                title: "\(confidenceEmoji) \(payload.task)",
                message: "\(payload.suggestedAction)\n\n\(payload.reason)",
                icon: action.icon,
                onInsertNow: action.handler
            )
            
            print("🤖 Suggestion: \(payload.task) (confidence: \(String(format: "%.0f", payload.confidence * 100))%)")
        }
    }
    
    /// Determine what action to take based on the payload
    private func determineAction(for payload: NotificationPayload) -> (icon: String, handler: (() -> Void)?) {
        let taskLower = payload.task.lowercased()
        let suggestedLower = payload.suggestedAction.lowercased()
        let combined = taskLower + " " + suggestedLower
        
        // Check for email-related keywords
        if combined.contains("mail") || combined.contains("email") || 
           combined.contains("wyślij") || combined.contains("send") ||
           combined.contains("maila") {
            
            return (icon: "envelope.fill", handler: { [weak self] in
                Task { @MainActor in
                    await self?.composeAndOpenEmailDraft(for: payload)
                }
            })
        }
        
        // Check for message-related keywords
        if combined.contains("message") || combined.contains("wiadomość") ||
           combined.contains("slack") || combined.contains("discord") {
            return (icon: "message.fill", handler: nil)
        }
        
        // Check for document-related keywords
        if combined.contains("document") || combined.contains("dokument") ||
           combined.contains("create") || combined.contains("utwórz") {
            return (icon: "doc.fill", handler: nil)
        }

        // Check for GitHub-related keywords
        if combined.contains("github") || combined.contains("issue") ||
           combined.contains("pull request") || combined.contains("pr") ||
           combined.contains("devin") {
            return (icon: "chevron.left.forwardslash.chevron.right", handler: {
                Task {
                    await self.handleGitHubAction(for: payload)
                }
            })
        }

        // Default
        return (icon: "wand.and.stars", handler: nil)
    }

    // MARK: - GitHub Action

    /// Handle GitHub-related actions using Devin
    private func handleGitHubAction(for payload: NotificationPayload) async {
        print("🐙 Handling GitHub action: \(payload.task)")
        

        // Extract URL from payload (search in task, suggestedAction, reason)
        let allText = "\(payload.task) \(payload.suggestedAction) \(payload.reason)"
        let issueURL = extractURL(from: allText)

        if let url = issueURL {
            print("🐙 Found URL: \(url)")
            do {
                let session = try await DevinHelper.solveIssue(issueURL: url)
                print("🐙 ✅ Devin session created: \(session.sessionId)")
            } catch {
                print("🐙 ❌ Devin error: \(error.localizedDescription)")
                // Fallback: open the URL directly
            }
        } else {
            print("🐙 No URL found, opening GitHub")
        }
    }

    /// Extract https:// URL from text
    private func extractURL(from text: String) -> String? {
        let pattern = "https://[^\\s\"'<>]+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if let swiftRange = Range(match.range, in: text) {
                return String(text[swiftRange])
            }
        }
        return nil
    }
    
    // MARK: - Email Draft Composition
    
    /// Compose full email draft using AI and open in Mail
    private func composeAndOpenEmailDraft(for payload: NotificationPayload) async {
        print("📧 Composing email draft for: \(payload.task)")
        
        // Get recent events from intent analyzer buffer
        let recentEvents = intentAnalyzer.getRecentEvents()
        let systemState = intentAnalyzer.getCurrentSystemState()
        
        // Compose draft
        if let draft = await emailDraftComposer.composeEmailDraft(
            intent: payload.task,
            recentEvents: recentEvents,
            systemState: systemState
        ) {
            lastEmailDraft = draft
            
            if draft.isActionable {
                print("📧 Opening Mail with composed draft...")
                print("📧 Subject: \(draft.emailSubject)")
                print("📧 Body: \(draft.emailBody.prefix(100))...")
                print("📧 Context used: \(draft.valueAddedContextUsed)")
                
                MailHelper.compose(
                    to: draft.recipient,
                    subject: draft.emailSubject,
                    body: draft.emailBody
                )
            } else {
                // Show notification about why email cannot be composed
                let reason = draft.whyNotComposable ?? "Niewystarczające informacje"
                print("📧 Cannot compose email: \(reason)")
                
                NotificationManager.shared.show(
                    title: "❌ Nie mogę napisać maila",
                    message: reason,
                    icon: "envelope.badge.exclamationmark"
                )
            }
        } else {
            // Fallback if LLM fails
            print("📧 LLM failed, using simple fallback")
            openSimpleEmailDraft(for: payload)
        }
    }
    
    /// Simple fallback email draft without LLM
    private func openSimpleEmailDraft(for payload: NotificationPayload) {
        let subject = extractEmailSubject(from: payload)
        let body = extractEmailBody(from: payload)
        
        MailHelper.compose(
            subject: subject,
            body: body
        )
    }
    
    /// Extract email subject from payload (fallback)
    private func extractEmailSubject(from payload: NotificationPayload) -> String {
        let task = payload.task
        
        // Look for "do X" pattern (Polish)
        if let range = task.range(of: "do ", options: .caseInsensitive) {
            let afterDo = String(task[range.upperBound...])
            let words = afterDo.components(separatedBy: " ").prefix(3)
            if !words.isEmpty {
                return "Wiadomość do \(words.joined(separator: " "))"
            }
        }
        
        // Look for "to X" pattern (English)
        if let range = task.range(of: "to ", options: .caseInsensitive) {
            let afterTo = String(task[range.upperBound...])
            let words = afterTo.components(separatedBy: " ").prefix(3)
            if !words.isEmpty {
                return "Message to \(words.joined(separator: " "))"
            }
        }
        
        return payload.task
    }
    
    /// Extract email body from payload (fallback)
    private func extractEmailBody(from payload: NotificationPayload) -> String {
        let greeting = "Dzień dobry,\n\n"
        let signature = "\n\nPozdrawiam"
        
        let hint = payload.suggestedAction
            .replacingOccurrences(of: "Otwórz Mail", with: "")
            .replacingOccurrences(of: "Open Mail", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !hint.isEmpty {
            return "\(greeting)\(hint)\(signature)"
        }
        
        return "\(greeting)[Treść wiadomości]\(signature)"
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

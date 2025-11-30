//
//  EmailDraftComposer.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Combine

/// Composes email drafts based on detected intent and relevant context
@MainActor
final class EmailDraftComposer: ObservableObject {
    
    static let shared = EmailDraftComposer()
    
    // MARK: - Dependencies
    
    private let llmClient = AnthropicClient.shared
    private let contextRetriever = ContextRetriever.shared
    private let userProfileManager = UserProfileManager.shared
    
    // MARK: - Configuration
    
    private let maxContextChunks = 10
    
    // MARK: - State
    
    @Published var lastDraft: EmailDraftPayload?
    @Published var isComposing = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// Main entry point: compose email draft from detected intent
    func composeEmailDraft(
        intent: String,
        recentEvents: [AXEvent],
        systemState: SystemState
    ) async -> EmailDraftPayload? {
        isComposing = true
        defer { isComposing = false }
        
        print("")
        print("📧═══════════════════════════════════════════════════")
        print("📧 EMAIL DRAFT COMPOSER STARTED")
        print("📧 Intent: \(intent)")
        print("📧═══════════════════════════════════════════════════")
        
        // 1. Retrieve relevant context from ContextStore
        let contextChunks = await contextRetriever.retrieve(intent: intent)
        let contextString = contextRetriever.buildContextString(chunks: contextChunks)
        print("📧 Retrieved \(contextChunks.count) context chunks")
        
        // 2. Build LLM prompt with context
        let prompt = buildEmailCompositionPromptNew(
            intent: intent,
            contextString: contextString,
            systemState: systemState
        )
        
        // Log full prompt for debugging
        print("")
        print("📧 ═══════════════════════════════════════════════════")
        print("📧 FULL LLM PROMPT:")
        print("📧 ═══════════════════════════════════════════════════")
        print(prompt)
        print("📧 ═══════════════════════════════════════════════════")
        print("")
        
        // 3. Call LLM for email composition
        guard let draft = await composeWithLLM(prompt: prompt) else {
            print("📧 ❌ LLM composition failed")
            return nil
        }
        
        // 4. Validate and sanitize the draft
        var finalDraft = draft

        // Check if subject is invalid (e.g., just "MAIL")
        let hasInvalidSubject = isInvalidEmailSubject(draft.emailSubject)
        // Check if body is invalid (e.g., "Perform MAIL action")
        let hasInvalidBody = isInvalidEmailBody(draft.emailBody, intent: intent)

        if hasInvalidSubject || hasInvalidBody {
            print("📧 ⚠️ LLM returned invalid content, clearing fields")
            print("📧   Invalid subject: \(hasInvalidSubject) ('\(draft.emailSubject)')")
            print("📧   Invalid body: \(hasInvalidBody)")
            finalDraft = EmailDraftPayload(
                shouldComposeEmail: true,
                inferredTask: draft.inferredTask,
                confidence: draft.confidence,
                valueAddedContextUsed: draft.valueAddedContextUsed,
                emailSubject: hasInvalidSubject ? "" : draft.emailSubject,
                emailBody: hasInvalidBody ? "" : draft.emailBody,
                recipient: draft.recipient,
                missingInfo: nil,
                timestamp: Date()
            )
        } else if !draft.shouldComposeEmail {
            print("📧 ⚠️ LLM said no compose, but we force open Mail anyway")
            finalDraft = EmailDraftPayload(
                shouldComposeEmail: true,
                inferredTask: draft.inferredTask,
                confidence: draft.confidence,
                valueAddedContextUsed: draft.valueAddedContextUsed,
                emailSubject: draft.emailSubject.isEmpty ? "" : draft.emailSubject,
                emailBody: "", // Empty body, user fills in
                recipient: draft.recipient,
                missingInfo: nil,
                timestamp: Date()
            )
        }
        let validatedDraft = finalDraft
        
        print("📧 ✅ Draft composed!")
        print("📧 Subject: \(validatedDraft.emailSubject)")
        print("📧 Recipient: \(validatedDraft.recipient ?? "none")")
        print("📧 Body preview: \(validatedDraft.emailBody.prefix(100))...")
        print("📧═══════════════════════════════════════════════════")
        
        lastDraft = validatedDraft
        return validatedDraft
    }
    
    /// Check if email body is invalid (just repeated intent or too generic)
    private func isInvalidEmailBody(_ body: String, intent: String) -> Bool {
        // Remove greetings and closings to get core content
        let coreContent = body
            .replacingOccurrences(of: "Dzień dobry,", with: "")
            .replacingOccurrences(of: "Cześć,", with: "")
            .replacingOccurrences(of: "Witam,", with: "")
            .replacingOccurrences(of: "Pozdrawiam", with: "")
            .replacingOccurrences(of: "Z poważaniem", with: "")
            .replacingOccurrences(of: "Do usłyszenia", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("📧 VALIDATION - Core content: '\(coreContent)'")

        let coreLower = coreContent.lowercased()
        let intentLower = intent.lowercased()

        // Check if core content is too similar to intent
        if coreLower == intentLower {
            print("📧 INVALID: exact match with intent")
            return true
        }
        if coreLower.contains(intentLower) && coreContent.count < intent.count * 2 {
            print("📧 INVALID: contains intent")
            return true
        }

        // Check for generic patterns that indicate LLM didn't write real content
        let invalidPatterns = [
            "send email", "send mail", "wyślij mail", "wyślij email",
            "compose email", "open email", "write email", "draft email",
            "automate", "process of sending",
            "email to", "mail to", "napisz do", "mail do",
            "[", "]", // placeholders
            "dear client", "dear customer",
            "@", // raw email addresses in body = not real content
            "perform mail action", "mail action", "perform email action",
            "email action", "action mail", "action email",
        ]

        for pattern in invalidPatterns {
            if coreLower.contains(pattern) {
                print("📧 INVALID: contains pattern '\(pattern)'")
                return true
            }
        }

        // Check if content is too short (just greeting + closing without real content)
        if coreContent.count < 20 {
            print("📧 INVALID: too short (\(coreContent.count) chars)")
            return true
        }

        print("📧 VALID: passed all checks")
        return false
    }

    /// Check if email subject is invalid (just "MAIL" or action type)
    private func isInvalidEmailSubject(_ subject: String) -> Bool {
        let subjectLower = subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Invalid subject patterns - just the action type or generic
        let invalidSubjects = [
            "mail", "email", "send", "send mail", "send email",
            "compose", "draft", "message", "wiadomość",
            "perform mail action", "mail action", "email action"
        ]

        if invalidSubjects.contains(subjectLower) {
            print("📧 INVALID SUBJECT: '\(subject)' is too generic")
            return true
        }

        // Subject is too short
        if subjectLower.count < 3 {
            print("📧 INVALID SUBJECT: too short")
            return true
        }

        return false
    }
    
    /// Quick check if text indicates email intent
    func detectsEmailIntent(in text: String) -> Bool {
        let emailKeywords = [
            // Polish
            "wyślij mail", "napisz mail", "wyślij email", "napisz email",
            "wyślij maila", "napisz maila", "odpowiedz na mail",
            "mail do", "email do", "wiadomość do", "napisz do",
            // English
            "send email", "write email", "compose email", "email to",
            "send mail", "write mail", "reply to email", "draft email"
        ]
        
        let textLower = text.lowercased()
        return emailKeywords.contains { textLower.contains($0) }
    }
    
    // MARK: - LLM Prompt Building
    
    private func buildEmailCompositionPromptNew(
        intent: String,
        contextString: String,
        systemState: SystemState
    ) -> String {
        let userProfile = userProfileManager.profile
        
        return """
        TASK: Compose an email based on the user's intent and context.

        USER INTENT: "\(intent)"

        USER: \(userProfile.name)
        LANGUAGE: English (ALWAYS write in English!)
        STYLE: \(userProfile.writingStyle.formality)

        CURRENT APP: \(systemState.activeApp)

        \(contextString)

        ⚠️ CONTEXT PRIORITY (MOST IMPORTANT):
        1. [Notification] = TOP PRIORITY - These are real-time messages from colleagues/apps. ALWAYS use notification content first!
        2. [Ocr] = Second priority - Current screen content
        3. Other context = Lower priority

        CONTEXT USAGE:
        - NOTIFICATIONS ARE THE PRIMARY SOURCE OF TRUTH for email content!
        - If a [Notification] contains instructions like "email X about Y" - this is your main directive.
        - Extract recipient names, email addresses, and topics primarily from [Notification].
        - Use [Ocr] to supplement with additional details visible on screen.
        - If intent is vague (e.g. "reply to this"), rely HEAVILY on [Notification] content.
        - DISCARD context that is clearly unrelated to the intent (e.g. old screen content).

        SCENARIO - COLLEAGUE REQUEST (Triangular):
        - If a [Notification] from Colleague A says "Email Person B about Topic C":
          -> You are writing TO Person B.
          -> The topic is Topic C.
          -> Do NOT say "As requested" (Person B didn't request it, Colleague A did).
          -> Instead, start directly: "I'm writing to you regarding Topic C..." or "Colleague A mentioned..."

        CRITICAL - DETERMINE THE GOAL:
        - Is it a job offer? An inquiry? A status update? A meeting request?
        - Look at [Notification] FIRST to understand the TRUE PURPOSE.
        - Then check [Ocr] for supporting details.

        RULES:
        1. ALWAYS set should_compose_email=true
        2. Write in ENGLISH only
        3. PRIORITIZE [Notification] content above all other context!
        4. ADAPT THE CONTENT TO THE GOAL:
           - If notification: "hire Piotrek" → write JOB OFFER / INQUIRY
           - If notification: "ask about project X" → write QUESTION
           - If notification: "send update to client" → write STATUS UPDATE
           - If notification: "schedule meeting" → write MEETING REQUEST
        5. If no clear topic/recipient in notifications or context:
           - Set email_body="" (empty) - user fills in
        6. Sign as \(userProfile.name)
        7. NEVER use [placeholder] text - use real names or leave empty

        ═══════════════════════════════════════════════════════
        CUSTOM RULES (USER-DEFINED CONTACTS & PREFERENCES):
        ═══════════════════════════════════════════════════════

        [Person - Piotr]
        • Email: piotrekpasztor@gmail.com
        • Style: Informal - you work together as colleagues
        • When writing to Piotr, use casual/friendly tone, and always use lowercase pls!

        ═══════════════════════════════════════════════════════

        RESPOND WITH VALID JSON:
        {
            "should_compose_email": true,
            "inferred_task": "description of what email is about",
            "confidence": 0.0-1.0,
            "value_added_context_used": ["list of context items used - especially notifications!"],
            "email_subject": "subject line",
            "email_body": "full email text OR empty string if no clear context",
            "recipient": "email address from notification/context or null",
            "missing_info": null
        }
        """
    }
    
    // MARK: - LLM Composition
    
    private func composeWithLLM(prompt: String) async -> EmailDraftPayload? {
        guard await llmClient.isConfigured else {
            print("📧 ❌ LLM not configured")
            return nil
        }
        
        let systemPrompt = """
        You are an email composition assistant. Write in ENGLISH only.

        ⚠️ CRITICAL - NOTIFICATION PRIORITY:
        [Notification] context is your #1 source of truth! These are real-time messages from colleagues telling you what to do.
        ALWAYS extract email content, recipients, and topics from [Notification] FIRST before looking at other context.

        RULES:
        1. ALWAYS set should_compose_email=true
        2. Write professional, natural emails in English
        3. [Notification] = PRIMARY SOURCE - Extract recipient, topic, and purpose from notifications first!
        4. [Ocr] = SECONDARY SOURCE - Use for additional details
        5. DEDUCE THE GOAL from notifications, filtered by user intent.
        6. If context is unrelated to intent, IGNORE it.
        7. If no notifications or context is unclear → set email_body="" (empty string) so user can fill it
        8. Extract recipient email from [Notification] context - this is usually where it comes from!
        9. NEVER put placeholder text like [company] or [name]
        10. AVOID generic "As requested" openers unless the recipient actually requested it.

        EXAMPLE 1 (Colleague Request via Notification):
        Context: [Notification] from Ari: "Send email to Piotrek about hiring him"
        Response:
        {
            "should_compose_email": true,
            "email_subject": "Job Opportunity",
            "email_body": "Hi Piotrek,\\n\\nAri mentioned that we are interested in discussing a potential opportunity with you...\\n\\nBest,\\nFilip",
            "recipient": "piotrek@example.com",
            "value_added_context_used": ["Notification from Ari about hiring Piotrek"]
        }

        EXAMPLE 2 (Project Update from Notification):
        Context: [Notification] from Manager: "Update the client on project status"
        Response:
        {
            "should_compose_email": true,
            "email_subject": "Project Status Update",
            "email_body": "Hi,\\n\\nI wanted to provide you with an update on the current project status...\\n\\nBest,\\nFilip",
            "recipient": null,
            "value_added_context_used": ["Notification from Manager about project update"]
        }

        EXAMPLE 3 (No notifications, no clear context):
        {
            "should_compose_email": true,
            "email_subject": "",
            "email_body": "",
            "recipient": null,
            "value_added_context_used": []
        }

        Respond ONLY with valid JSON.
        """
        
        // Log exactly what is being sent to the AI model
        print("")
        print("📧 ═══════════════════════════════════════════════════")
        print("📧 SENDING TO AI MODEL - FULL REQUEST")
        print("📧 ═══════════════════════════════════════════════════")
        print("📧 SYSTEM PROMPT:")
        print("📧 ───────────────────────────────────────────────────")
        print(systemPrompt)
        print("📧 ───────────────────────────────────────────────────")
        print("📧 USER MESSAGE (includes context):")
        print("📧 ───────────────────────────────────────────────────")
        print(prompt)
        print("📧 ───────────────────────────────────────────────────")
        print("📧 ═══════════════════════════════════════════════════")
        print("")

        do {
            let response = try await llmClient.callAPI(
                systemPrompt: systemPrompt,
                userMessage: prompt
            )

            // Log the AI response
            print("")
            print("📧 ═══════════════════════════════════════════════════")
            print("📧 AI MODEL RESPONSE:")
            print("📧 ═══════════════════════════════════════════════════")
            print(response)
            print("📧 ═══════════════════════════════════════════════════")
            print("")

            return parseEmailDraftResponse(response)
        } catch {
            print("📧 ❌ LLM error: \(error)")
            return nil
        }
    }
    
    private func parseEmailDraftResponse(_ response: String) -> EmailDraftPayload? {
        // Extract JSON from response
        var jsonString = response
        
        // Try to find JSON block safely
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            // Use closed range up to end of the "}" character
            let startIndex = startRange.lowerBound
            let endIndex = endRange.upperBound
            if startIndex < endIndex {
                jsonString = String(response[startIndex..<endIndex])
            }
        }
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            print("📧 ❌ Failed to encode response as data")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            var draft = try decoder.decode(EmailDraftPayload.self, from: data)
            
            // Add timestamp if not present
            if draft.timestamp == Date(timeIntervalSince1970: 0) {
                draft = EmailDraftPayload(
                    shouldComposeEmail: draft.shouldComposeEmail,
                    inferredTask: draft.inferredTask,
                    confidence: draft.confidence,
                    valueAddedContextUsed: draft.valueAddedContextUsed,
                    emailSubject: draft.emailSubject,
                    emailBody: draft.emailBody,
                    recipient: draft.recipient,
                    missingInfo: draft.missingInfo,
                    timestamp: Date()
                )
            }
            
            return draft
        } catch {
            print("📧 ❌ JSON parse error: \(error)")
            return nil
        }
    }
    
    // MARK: - Style Learning
    
    /// Update user writing style from samples (future: ML-based learning)
    func updateWritingStyle(from samples: [String]) {
        // Extract patterns from samples
        // For now, use default Polish style
        // TODO: Implement pattern extraction
    }
}

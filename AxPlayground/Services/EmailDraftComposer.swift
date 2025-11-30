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
        
        // 4. Force should_compose_email to true (we always want to open Mail)
        var finalDraft = draft
        if !draft.shouldComposeEmail {
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
        
        CONTEXT USAGE:
        - Check [Notification] and [Ocr] for details matching the intent.
        - If intent is specific (e.g. "email X about Y"), use context only for details about Y or contact info for X.
        - If intent is vague (e.g. "reply to this"), rely heavily on [Notification] and [Ocr].
        - DISCARD context that is clearly unrelated to the intent (e.g. old screen content).
        
        SCENARIO - COLLEAGUE REQUEST (Triangular):
        - If a [Notification] from Colleague A says "Email Person B about Topic C":
          -> You are writing TO Person B.
          -> The topic is Topic C.
          -> Do NOT say "As requested" (Person B didn't request it, Colleague A did).
          -> Instead, start directly: "I'm writing to you regarding Topic C..." or "Colleague A mentioned..."
        
        CRITICAL - DETERMINE THE GOAL:
        - Is it a job offer? An inquiry? A status update? A meeting request?
        - Look at the context to understand the TRUE PURPOSE, but ensure it aligns with USER INTENT.
        
        RULES:
        1. ALWAYS set should_compose_email=true
        2. Write in ENGLISH only
        3. ADAPT THE CONTENT TO THE GOAL:
           - If context: "hire Piotrek" → write JOB OFFER / INQUIRY
           - If context: "ask about project X" → write QUESTION
           - If context: "send update to client" → write STATUS UPDATE
           - If context: "schedule meeting" → write MEETING REQUEST
        4. If no clear topic/recipient in context:
           - Set email_body="" (empty) - user fills in
        5. Sign as \(userProfile.name)
        6. NEVER use [placeholder] text - use real names or leave empty
        
        RESPOND WITH VALID JSON:
        {
            "should_compose_email": true,
            "inferred_task": "description of what email is about",
            "confidence": 0.0-1.0,
            "value_added_context_used": ["list of context items used"],
            "email_subject": "subject line",
            "email_body": "full email text OR empty string if no clear context",
            "recipient": "email address from context or null",
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
        
        CRITICAL: Prioritize USER INTENT. Use context details ONLY if they support the intent.
        
        RULES:
        1. ALWAYS set should_compose_email=true
        2. Write professional, natural emails in English
        3. DEDUCE THE GOAL from context, but filtered by the intent.
        4. If context is unrelated to intent, IGNORE the context.
        5. If context is unclear → set email_body="" (empty string) so user can fill it
        6. Extract recipient email from [Notification] context if present AND relevant
        7. NEVER put placeholder text like [company] or [name]
        8. AVOID generic "As requested" openers unless the recipient actually requested it.
        
        EXAMPLE 1 (Colleague Request):
        Context: Notification from Ari: "Send email to Piotrek about hiring him"
        Response:
        {
            "should_compose_email": true,
            "email_subject": "Job Opportunity / Hiring",
            "email_body": "Hi Piotrek,\n\nAri mentioned that we are interested in hiring you... [details from context]",
            "recipient": "piotrek@example.com"
        }
        {
            "should_compose_email": true,
            "email_subject": "Regarding Developer Position - Relocation to Poland",
            "email_body": "Hi Piotrek,\\n\\nIt was great meeting you recently. We are very interested in your profile and would like to discuss a potential role with us.\\n\\nHowever, as mentioned, this position would require relocation to Poland. Is this something you would be open to?\\n\\nBest,\\nFilip",
            "recipient": "piotrek@example.com"
        }

        EXAMPLE 2 (Project Update):
        {
            "should_compose_email": true,
            "email_subject": "Update on Project X",
            "email_body": "Hi Team,\\n\\nJust wanted to let you know that we have finished the initial phase...\\n\\nBest,\\nFilip",
            "recipient": "team@example.com"
        }
        
        EXAMPLE 3 (No clear context):
        {
            "should_compose_email": true,
            "email_subject": "",
            "email_body": "",
            "recipient": null
        }
        
        Respond ONLY with valid JSON.
        """
        
        do {
            let response = try await llmClient.callAPI(
                systemPrompt: systemPrompt,
                userMessage: prompt
            )
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

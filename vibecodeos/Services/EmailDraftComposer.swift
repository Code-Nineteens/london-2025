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
    
    // MARK: - Configuration
    
    private let maxContextChunks = 10
    
    // MARK: - State
    
    @Published var lastDraft: EmailDraftPayload?
    @Published var isComposing = false
    
    /// User's writing style profile
    private var userStyle: UserWritingStyle = .defaultPolish
    
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
        
        // 3. Call LLM for email composition
        guard let draft = await composeWithLLM(prompt: prompt) else {
            print("📧 ❌ LLM composition failed")
            return nil
        }
        
        // 4. Validate draft - reject if body is just the intent repeated
        if isInvalidEmailBody(draft.emailBody, intent: intent) {
            print("📧 ❌ Invalid email body - just repeated intent")
            return EmailDraftPayload(
                shouldComposeEmail: false,
                inferredTask: draft.inferredTask,
                confidence: 0.0,
                valueAddedContextUsed: [],
                emailSubject: draft.emailSubject,
                emailBody: "",
                recipient: draft.recipient,
                missingInfo: "Brak wystarczającego kontekstu. Podaj: do kogo jest mail i o czym ma być.",
                timestamp: Date()
            )
        }
        
        print("📧 ✅ Draft composed!")
        print("📧 Subject: \(draft.emailSubject)")
        print("📧 Body preview: \(draft.emailBody.prefix(100))...")
        print("📧═══════════════════════════════════════════════════")
        
        lastDraft = draft
        return draft
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
        let hasContext = !contextString.isEmpty && contextString != "AVAILABLE CONTEXT:\n(No relevant context found)\n"
        
        return """
        TASK: Compose a real, sendable email based on the user's intent and context.
        
        USER INTENT: "\(intent)"
        
        USER WRITING STYLE:
        - Language: \(userStyle.preferredLanguage) (ALWAYS write in this language!)
        - Formality: \(userStyle.formalityLevel)
        - Greetings: \(userStyle.greetings.joined(separator: ", "))
        - Closings: \(userStyle.closings.joined(separator: ", "))
        
        CURRENT APP: \(systemState.activeApp)
        
        \(contextString)
        
        CRITICAL RULES:
        1. NEVER repeat the intent literally in the email body
        2. If the intent is vague (e.g., "send email to client"), you MUST:
           - Look for specific client names, projects, or topics in the CONTEXT
           - If found: write email about that specific topic
           - If NOT found: set should_compose_email=false and explain what info is missing
        3. Write a REAL email that someone could actually send - professional, specific content
        4. Use context details naturally (names, dates, projects, previous messages)
        5. NEVER write placeholder text like "[nazwa firmy]" or "[temat]"
        
        \(hasContext ? """
        CONTEXT ANALYSIS:
        - Review the context chunks above carefully
        - Find: recipient names, email addresses, project names, recent topics, deadlines
        - Use these details to write a specific, relevant email
        """ : """
        NO CONTEXT AVAILABLE:
        - Cannot compose a specific email without knowing WHO and WHAT
        - Set should_compose_email=false
        - Explain what information is needed (recipient, topic, purpose)
        """)
        
        RESPOND WITH VALID JSON:
        {
            "should_compose_email": boolean (false if intent is too vague and no context helps),
            "inferred_task": "what this email is about based on context",
            "confidence": 0.0-1.0,
            "value_added_context_used": ["specific context items used"],
            "email_subject": "specific subject (not generic)",
            "email_body": "full email with greeting/closing - REAL TEXT, NOT DESCRIPTION",
            "recipient": "actual name/email from context, or null",
            "missing_info": "what's needed if should_compose_email is false"
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
        You are an email composition assistant.
        
        ABSOLUTE RULES - NEVER BREAK THESE:
        1. NEVER copy/paste the user's command into email_body
        2. NEVER put email addresses in the email body text
        3. If you don't know WHAT to write about → should_compose_email=false
        4. email_body must be a REAL message someone would send
        
        EXAMPLES OF INVALID email_body (NEVER DO THIS):
        - "Open email app and compose email to X"
        - "send email to client"
        - "wyślij mail do X"
        - Any text containing @ symbol
        
        EXAMPLE OF VALID email_body:
        "Dzień dobry,\\n\\nChciałbym umówić się na spotkanie w sprawie projektu.\\n\\nPozdrawiam"
        
        If the user's intent is vague (no specific topic/content), return:
        {"should_compose_email": false, "missing_info": "Specify what the email should be about"}
        
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

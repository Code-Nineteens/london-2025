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
        
        print("📧 ✅ Draft composed!")
        print("📧 Subject: \(draft.emailSubject)")
        print("📧 Body preview: \(draft.emailBody.prefix(100))...")
        print("📧═══════════════════════════════════════════════════")
        
        lastDraft = draft
        return draft
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
        return """
        TASK: Compose an email draft based on the user's intent and available context.
        
        USER INTENT: \(intent)
        
        USER WRITING STYLE:
        - Language: \(userStyle.preferredLanguage) (WRITE IN THIS LANGUAGE)
        - Formality: \(userStyle.formalityLevel)
        - Typical greetings: \(userStyle.greetings.joined(separator: ", "))
        - Typical closings: \(userStyle.closings.joined(separator: ", "))
        - Common phrases: \(userStyle.commonPhrases.joined(separator: ", "))
        
        CURRENT APP: \(systemState.activeApp)
        
        \(contextString)
        
        INSTRUCTIONS:
        1. Analyze the intent to understand WHO the email is for and WHAT it should be about
        2. Use the CONTEXT above to find relevant details (names, topics, deadlines, previous conversations)
        3. Write a REAL email in \(userStyle.preferredLanguage == "pl" ? "Polish" : "English") - not a description of what to write
        4. Match the user's style: \(userStyle.formalityLevel), using their typical phrases
        5. If context mentions specific things (meetings, projects, deadlines), reference them naturally
        6. Keep it concise but complete - ready to send
        
        RESPOND WITH VALID JSON ONLY:
        {
            "should_compose_email": true,
            "inferred_task": "one-line description of what this email is about",
            "confidence": 0.8,
            "value_added_context_used": ["list what context you used"],
            "email_subject": "subject line in \(userStyle.preferredLanguage == "pl" ? "Polish" : "English")",
            "email_body": "full email text with greeting and closing - ACTUAL EMAIL TEXT, NOT A DESCRIPTION",
            "recipient": "recipient name if found, or null"
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
        You are an email composition assistant. You compose professional, concise emails 
        that match the user's writing style. You respond ONLY with valid JSON.
        
        Quality principles:
        - Intent-first: understand what the user wants to communicate
        - Style-accurate: match user's tone, phrases, and formality
        - Value-added context only: include external info only if it improves the email
        - Concise: no fluff, get to the point
        - Authentic: sound like the user, not a robot
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

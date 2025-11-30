//
//  EmailDraftPayload.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation

/// Structured output for email draft composition
struct EmailDraftPayload: Codable, Sendable {
    /// Whether an email should be composed
    let shouldComposeEmail: Bool
    
    /// Short one-line description of inferred task
    let inferredTask: String
    
    /// Confidence score 0.0-1.0
    let confidence: Double
    
    /// List of context sources used (if any)
    let valueAddedContextUsed: [String]
    
    /// Generated email subject
    let emailSubject: String
    
    /// Final email draft - ready to paste
    let emailBody: String
    
    /// Recipient if detected
    let recipient: String?
    
    /// Timestamp when generated
    let timestamp: Date
    
    // MARK: - Coding Keys for JSON parsing
    
    enum CodingKeys: String, CodingKey {
        case shouldComposeEmail = "should_compose_email"
        case inferredTask = "inferred_task"
        case confidence
        case valueAddedContextUsed = "value_added_context_used"
        case emailSubject = "email_subject"
        case emailBody = "email_body"
        case recipient
        case timestamp
    }
    
    /// Check if draft is actionable
    var isActionable: Bool {
        shouldComposeEmail && confidence >= 0.7
    }
    
    /// Empty/nil draft for when no email should be composed
    static var empty: EmailDraftPayload {
        EmailDraftPayload(
            shouldComposeEmail: false,
            inferredTask: "",
            confidence: 0.0,
            valueAddedContextUsed: [],
            emailSubject: "",
            emailBody: "",
            recipient: nil,
            timestamp: Date()
        )
    }
}

// MARK: - Context Event for Email Composition

/// Represents a relevant context event for email composition
struct EmailContext: Sendable {
    /// Source app (Slack, Calendar, Git, etc.)
    let source: String
    
    /// Brief description of context
    let summary: String
    
    /// Raw content (truncated)
    let content: String
    
    /// Relevance score 0.0-1.0
    let relevanceScore: Double
    
    /// Timestamp
    let timestamp: Date
    
    /// Context type
    let type: ContextType
    
    enum ContextType: String, Sendable {
        case slackMessage = "slack"
        case calendarEvent = "calendar"
        case gitCommit = "git"
        case document = "document"
        case email = "email"
        case meeting = "meeting"
        case deadline = "deadline"
        case other = "other"
    }
}

// MARK: - User Writing Style Profile

/// Profile of user's writing style extracted from samples
struct UserWritingStyle: Codable, Sendable {
    /// Common greeting patterns
    let greetings: [String]
    
    /// Common closing patterns
    let closings: [String]
    
    /// Preferred language (pl/en)
    let preferredLanguage: String
    
    /// Formality level: formal, semi-formal, casual
    let formalityLevel: String
    
    /// Common phrases the user uses
    let commonPhrases: [String]
    
    /// Average sentence length
    let avgSentenceLength: Int
    
    /// Default style profile (Polish, semi-formal)
    static var defaultPolish: UserWritingStyle {
        UserWritingStyle(
            greetings: ["Dzień dobry,", "Cześć,", "Witam,"],
            closings: ["Pozdrawiam", "Z poważaniem", "Do usłyszenia"],
            preferredLanguage: "pl",
            formalityLevel: "semi-formal",
            commonPhrases: [
                "zgodnie z naszą rozmową",
                "w nawiązaniu do",
                "proszę o",
                "dziękuję za"
            ],
            avgSentenceLength: 15
        )
    }
}

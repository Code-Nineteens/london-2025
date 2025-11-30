//
//  DevinHelper.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa

/// Helper for integrating with Devin AI (https://api.devin.ai/v1)
struct DevinHelper {
    
    // MARK: - Configuration
    
    private static let apiBaseURL = "https://api.devin.ai/v1"
    private static let webAppURL = "https://app.devin.ai"
    private static let currentIssueURL = "https://github.com/Code-Nineteens/london-2025/issues/7"
    
    /// API key from EnvManager.
    private static var apiKey: String? {
        EnvManager.shared[.devinAPIKey]
    }
    
    // MARK: - Types
    
    struct Session: Codable {
        let sessionId: String
        let url: String?
        
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case url
        }
    }
    
    // MARK: - Public Methods
    
    /// Solves the current issue (Code-Nineteens/london-2025#7).
    static func solveCurrentIssue() async throws -> Session {
        try await solveIssue(issueURL: currentIssueURL)
    }
    
    /// Opens a specific Devin session in browser.
    static func openSession(_ session: Session) {
        let sessionURL = session.url ?? "\(webAppURL)/sessions/\(session.sessionId)"
        if let url = URL(string: sessionURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Creates session to solve a GitHub/GitLab issue and opens it in browser.
    /// Uses API key from DEVIN_API_KEY environment variable.
    static func solveIssue(issueURL: String) async throws -> Session {
        guard let apiKey = apiKey else {
            throw DevinError.apiKeyMissing
        }
            
        let prompt = "fix this issue: \(issueURL). Be very precise"
        let session = try await createSession(prompt: prompt, apiKey: apiKey)
        openSession(session)
        return session
    }
    
    /// Creates a new Devin session.
    static func createSession(
        prompt: String,
        apiKey: String
    ) async throws -> Session {
        guard let url = URL(string: "\(apiBaseURL)/sessions") else {
            throw DevinError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "prompt": prompt,
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DevinError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DevinError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        return try JSONDecoder().decode(Session.self, from: data)
    }
}

// MARK: - Errors

enum DevinError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case apiKeyMissing
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Devin API URL"
        case .invalidResponse:
            return "Invalid response from Devin API"
        case .apiError(let statusCode, let message):
            return "Devin API error (\(statusCode)): \(message)"
        case .apiKeyMissing:
            return "DEVIN_API_KEY not set in .env file"
        }
    }
}

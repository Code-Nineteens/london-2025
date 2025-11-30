//
//  AnthropicClient.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Foundation

/// Client for Anthropic Claude API
actor AnthropicClient {
    
    static let shared = AnthropicClient()
    
    // MARK: - Configuration
    
    private let apiEndpoint = "https://api.anthropic.com/v1/messages"
    private let model = "claude-3-haiku-20240307"  // Fast & cheap for real-time
    private let maxTokens = 500
    
    // API Key - stored securely (in production use Keychain)
    private var apiKey: String {
        // Try environment variable first
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            return key
        }
        // Fallback to UserDefaults (for development)
        if let key = UserDefaults.standard.string(forKey: "anthropic_api_key") {
            return key
        }
        return ""
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Set API key (for UI configuration)
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "anthropic_api_key")
    }
    
    /// Check if API key is configured
    var isConfigured: Bool {
        let hasKey = !apiKey.isEmpty
        print("🔑 API Key configured: \(hasKey) (length: \(apiKey.count))")
        return hasKey
    }
    
    /// Analyze user intent from accessibility context
    func analyzeIntent(context: String) async -> NotificationPayload? {
        print("🌐 AnthropicClient.analyzeIntent called")
        print("   API key length: \(apiKey.count)")
        
        guard isConfigured else {
            print("⚠️ Anthropic API key not configured - check ANTHROPIC_API_KEY env var or UserDefaults")
            return nil
        }
        
        let systemPrompt = """
        You analyze macOS Accessibility events to detect ONLY explicit task commands that can be automated.
        
        BE EXTREMELY CONSERVATIVE. Default answer is should_trigger: false.
        
        ONLY trigger (should_trigger: true) when text contains an EXPLICIT COMMAND like:
        - "wyślij maila do X" / "send email to X"
        - "napisz wiadomość do Y" / "write message to Y"  
        - "odpowiedz na Z" / "reply to Z"
        - "utwórz dokument" / "create document"
        - "zaplanuj spotkanie" / "schedule meeting"
        
        NEVER trigger for:
        - Regular conversations or chat messages
        - Random text, insults, jokes, casual talk
        - Reading content (user is just viewing, not commanding)
        - Focus changes, clicking, scrolling
        - Short text without explicit command intent
        - Any text that is NOT a direct instruction/command
        
        The text must be a COMMAND/INSTRUCTION that tells someone to DO something.
        "chuj ci w pizde" = NOT a command, just an insult → should_trigger: false
        "wyślij maila do klienta" = IS a command → should_trigger: true
        
        Respond with JSON:
        {
            "should_trigger": false,
            "task": "description",
            "confidence": 0.0,
            "suggested_action": "none",
            "reason": "not a command"
        }
        
        Only set should_trigger: true if text is EXPLICITLY a command to perform a task.
        """
        
        let userMessage = """
        Analyze these accessibility events and determine if there's an automation opportunity:
        
        \(context)
        
        Return JSON with your analysis.
        """
        
        print("🌐 CALLING ANTHROPIC API...")
        print("   Model: \(model)")
        print("   Context length: \(context.count) chars")
        
        do {
            let response = try await callAPI(systemPrompt: systemPrompt, userMessage: userMessage)
            print("🌐 API RESPONSE RECEIVED")
            print("   Raw response: \(response)")
            return parseResponse(response, context: context)
        } catch {
            print("❌ ANTHROPIC API ERROR: \(error)")
            return nil
        }
    }
    
    // MARK: - API Call
    
    /// Call the Anthropic API with custom prompts (used by EmailDraftComposer)
    func callAPI(systemPrompt: String, userMessage: String) async throws -> String {
        guard let url = URL(string: apiEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10  // Fast timeout for real-time use
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ API Error (\(httpResponse.statusCode)): \(errorBody)")
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw APIError.parseError
        }
        
        return text
    }
    
    // MARK: - Response Parsing
    
    private func parseResponse(_ response: String, context: String) -> NotificationPayload? {
        print("")
        print("🔍 PARSING LLM RESPONSE...")
        
        // Extract JSON from response (Claude might include extra text)
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            print("⚠️ ERROR: No JSON found in response")
            return nil
        }
        
        // Safely extract JSON substring
        guard jsonStart <= jsonEnd else {
            print("⚠️ ERROR: Invalid JSON indices")
            return nil
        }
        
        let jsonString = String(response[jsonStart...jsonEnd])
        print("📝 Extracted JSON:")
        print(jsonString)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("⚠️ ERROR: Failed to parse JSON")
            return nil
        }
        
        // Check if should trigger
        let shouldTrigger = json["should_trigger"] as? Bool ?? false
        let confidence = json["confidence"] as? Double ?? 0.0
        let task = json["task"] as? String ?? "?"
        let reason = json["reason"] as? String ?? "?"
        
        print("")
        print("🤖 LLM DECISION:")
        print("   should_trigger: \(shouldTrigger)")
        print("   confidence: \(confidence)")
        print("   task: \(task)")
        print("   reason: \(reason)")
        
        guard shouldTrigger else {
            print("✋ LLM SAID NO → Returning nil, no notification")
            return nil
        }
        
        print("⚠️ LLM SAID YES → Will create payload")
        
        // Extract fields
        guard let task = json["task"] as? String,
              let confidence = json["confidence"] as? Double,
              let suggestedAction = json["suggested_action"] as? String,
              let reason = json["reason"] as? String else {
            print("⚠️ Missing required fields in response")
            return nil
        }
        
        // Extract app context from the context string
        let appName = extractAppName(from: context)
        let elementRole = extractElementRole(from: context)
        
        return NotificationPayload(
            task: task,
            confidence: confidence,
            suggestedAction: suggestedAction,
            reason: reason,
            appContext: NotificationPayload.AppContext(
                appName: appName,
                elementRole: elementRole,
                elementTitle: nil
            ),
            timestamp: Date()
        )
    }
    
    private func extractAppName(from context: String) -> String {
        if let range = context.range(of: "Active App: ") {
            let start = range.upperBound
            if let end = context[start...].firstIndex(of: "\n") {
                return String(context[start..<end])
            }
        }
        return "Unknown"
    }
    
    private func extractElementRole(from context: String) -> String? {
        if let range = context.range(of: "Active Element: ") {
            let start = range.upperBound
            if let end = context[start...].firstIndex(of: "\n") {
                let role = String(context[start..<end])
                return role == "unknown" ? nil : role
            }
        }
        return nil
    }
    
    // MARK: - Errors
    
    enum APIError: Error {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case parseError
    }
}

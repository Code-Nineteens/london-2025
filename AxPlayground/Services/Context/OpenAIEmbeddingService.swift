//
//  OpenAIEmbeddingService.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation

/// Service for generating text embeddings using OpenAI API
actor OpenAIEmbeddingService {
    
    static let shared = OpenAIEmbeddingService()
    
    private let endpoint = "https://api.openai.com/v1/embeddings"
    private let model = "text-embedding-3-small"
    
    /// API key from environment or UserDefaults
    private var apiKey: String {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return key
        }
        if let key = UserDefaults.standard.string(forKey: "openai_api_key") {
            return key
        }
        return ""
    }
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Set API key programmatically
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openai_api_key")
    }
    
    /// Generate embedding for a single text
    func embed(text: String) async throws -> [Float] {
        guard isConfigured else {
            throw EmbeddingError.notConfigured
        }
        
        guard !text.isEmpty else {
            throw EmbeddingError.emptyInput
        }
        
        // Truncate if too long (max ~8000 tokens for small model)
        let truncatedText = String(text.prefix(30000))
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "model": model,
            "input": truncatedText
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            print("❌ OpenAI Embedding error (\(httpResponse.statusCode)): \(errorBody)")
            throw EmbeddingError.apiError(httpResponse.statusCode, errorBody)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let firstData = dataArray.first,
              let embedding = firstData["embedding"] as? [Double] else {
            throw EmbeddingError.parseError
        }
        
        return embedding.map { Float($0) }
    }
    
    /// Generate embeddings for multiple texts (batch)
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard isConfigured else {
            throw EmbeddingError.notConfigured
        }
        
        guard !texts.isEmpty else {
            return []
        }
        
        // Filter and truncate
        let validTexts = texts
            .filter { !$0.isEmpty }
            .map { String($0.prefix(30000)) }
        
        guard !validTexts.isEmpty else {
            return []
        }
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": model,
            "input": validTexts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0, "Batch failed")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw EmbeddingError.parseError
        }
        
        return dataArray.compactMap { item -> [Float]? in
            guard let embedding = item["embedding"] as? [Double] else { return nil }
            return embedding.map { Float($0) }
        }
    }
    
    // MARK: - Errors
    
    enum EmbeddingError: Error {
        case notConfigured
        case emptyInput
        case invalidResponse
        case apiError(Int, String)
        case parseError
    }
}

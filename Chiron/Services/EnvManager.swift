//
//  EnvManager.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/05/2025.
//

import Foundation
import SwiftDotenv

// MARK: - EnvKey

/// Keys for environment variables used in the app.
enum EnvKey: String {
    case devinAPIKey = "DEVIN_API_KEY"
    case openAIKey = "OPENAI_API_KEY"
    case anthropicKey = "ANTHROPIC_API_KEY"
}

// MARK: - EnvManagerError

/// Errors that can occur when loading environment variables.
enum EnvManagerError: LocalizedError {
    case fileNotFound(path: String)
    case keyNotFound(key: String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Environment file not found at: \(path)"
        case .keyNotFound(let key):
            return "Environment variable '\(key)' not found"
        }
    }
}

// MARK: - EnvManager

/// Manages environment variables loaded from .env file.
///
/// Usage:
/// ```swift
/// // Load at app start
/// EnvManager.shared.load()
///
/// // Get values
/// if let apiKey = EnvManager.shared[.devinAPIKey] {
///     print("API Key: \(apiKey)")
/// }
/// ```
final class EnvManager {
    
    // MARK: - Singleton
    
    static let shared = EnvManager()
    
    // MARK: - Properties
    
    private var isLoaded = false
    
    /// Project root path determined at compile time.
    private var projectRoot: String {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // Chiron
            .deletingLastPathComponent()  // project root
            .path
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Loads environment variables from .env file at project root.
    ///
    /// - Throws: `EnvManagerError.fileNotFound` if .env doesn't exist.
    func load() throws {
        let envPath = projectRoot + "/.env"
        
        guard FileManager.default.fileExists(atPath: envPath) else {
            throw EnvManagerError.fileNotFound(path: envPath)
        }
        
        try Dotenv.configure(atPath: envPath)
        isLoaded = true
        
        print("✅ EnvManager: Loaded .env from \(envPath)")
    }
    
    /// Loads environment variables silently, logging errors instead of throwing.
    func loadSilently() {
        do {
            try load()
        } catch {
            print("⚠️ EnvManager: \(error.localizedDescription)")
        }
    }
    
    /// Gets value for an environment key.
    ///
    /// - Parameter key: The environment key to look up.
    /// - Returns: The value if found, nil otherwise.
    subscript(key: EnvKey) -> String? {
        getValue(for: key.rawValue)
    }
    
    /// Gets value for a raw string key.
    ///
    /// - Parameter key: The raw key string.
    /// - Returns: The value if found, nil otherwise.
    func getValue(for key: String) -> String? {
        guard let value = Dotenv[key] else { return nil }
        return extractString(from: value)
    }
    
    /// Gets value or throws if not found.
    ///
    /// - Parameter key: The environment key.
    /// - Throws: `EnvManagerError.keyNotFound` if key doesn't exist.
    /// - Returns: The value for the key.
    func require(_ key: EnvKey) throws -> String {
        guard let value = self[key] else {
            throw EnvManagerError.keyNotFound(key: key.rawValue)
        }
        return value
    }
    
    // MARK: - Private Methods
    
    private func extractString(from value: Dotenv.Value) -> String {
        switch value {
        case .string(let str):
            return str
        case .boolean(let bool):
            return String(bool)
        case .integer(let int):
            return String(int)
        case .double(let dbl):
            return String(dbl)
        }
    }
}


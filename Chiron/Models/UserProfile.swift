//
//  UserProfile.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Combine

/// User profile for personalization and context
struct UserProfile: Codable {
    var name: String
    var email: String?
    var company: String?
    var role: String?
    var preferredLanguage: String
    var writingStyle: WritingStyle
    var knownContacts: [Contact]
    
    // Auto-detected from system
    var systemFullName: String?
    var systemUserName: String?
    
    struct Contact: Codable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var email: String?
        var company: String?
        var relationship: String? // "client", "colleague", "friend", etc.
        var notes: String?
    }
    
    struct WritingStyle: Codable {
        var formality: String // "formal", "casual", "semi-formal"
        var greetings: [String]
        var closings: [String]
    }
    
    // MARK: - Default Profile
    
    static var `default`: UserProfile {
        // Get user's real name from macOS account
        let fullName = NSFullUserName() // e.g., "Filip Wnęk"
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        
        // Try to get email from system (if available)
        let userName = NSUserName() // e.g., "filipwnek"
        
        print("👤 Detected system user: \(fullName) (@\(userName))")
        
        return UserProfile(
            name: firstName, // Use first name for casual communication
            email: nil,
            company: nil,
            role: nil,
            preferredLanguage: "English",
            writingStyle: WritingStyle(
                formality: "semi-formal",
                greetings: ["Hi", "Hey", "Hello"],
                closings: ["Best", "Thanks", "Cheers"]
            ),
            knownContacts: [],
            systemFullName: fullName,
            systemUserName: userName
        )
    }
    
    // MARK: - Persistence
    
    private static let fileName = "user_profile.json"
    
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ChironaOS")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent(fileName)
    }
    
    /// Load profile from disk or return default
    static func load() -> UserProfile {
        do {
            let data = try Data(contentsOf: fileURL)
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            print("👤 Loaded user profile: \(profile.name)")
            return profile
        } catch {
            print("👤 No saved profile, using default for: Filip")
            return .default
        }
    }
    
    /// Save profile to disk
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.fileURL)
            print("👤 Saved user profile: \(name)")
        } catch {
            print("❌ Failed to save user profile: \(error)")
        }
    }
    
    // MARK: - Context for LLM
    
    /// Generate context string for LLM
    func contextForLLM() -> String {
        var context = "USER PROFILE:\n"
        context += "- Name: \(name)\n"
        if let email = email { context += "- Email: \(email)\n" }
        if let company = company { context += "- Company: \(company)\n" }
        if let role = role { context += "- Role: \(role)\n" }
        context += "- Preferred language: \(preferredLanguage)\n"
        context += "- Writing style: \(writingStyle.formality)\n"
        context += "- Greetings: \(writingStyle.greetings.joined(separator: ", "))\n"
        context += "- Closings: \(writingStyle.closings.joined(separator: ", "))\n"
        
        if !knownContacts.isEmpty {
            context += "\nKNOWN CONTACTS:\n"
            for contact in knownContacts.prefix(10) {
                context += "- \(contact.name)"
                if let rel = contact.relationship { context += " (\(rel))" }
                if let company = contact.company { context += " @ \(company)" }
                context += "\n"
            }
        }
        
        return context
    }
    
    /// Check if a name refers to the user
    func isMe(_ name: String) -> Bool {
        let nameLower = name.lowercased()
        let myNameLower = self.name.lowercased()
        
        // Exact match with display name
        if nameLower == myNameLower { return true }
        
        // Check against system full name
        if let fullName = systemFullName?.lowercased() {
            if nameLower == fullName { return true }
            // Check first name from full name
            if let firstName = fullName.components(separatedBy: " ").first,
               nameLower == firstName { return true }
            // Check last name from full name
            if let lastName = fullName.components(separatedBy: " ").last,
               nameLower == lastName { return true }
        }
        
        // First name match
        if let firstPart = myNameLower.components(separatedBy: " ").first,
           nameLower == firstPart { return true }
        
        // Common variations (prefix matching for nicknames like "Fil" for "Filip")
        if myNameLower.count >= 3 && nameLower.hasPrefix(String(myNameLower.prefix(3))) {
            return true
        }
        
        return false
    }
}

/// Singleton manager for user profile
@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    @Published var profile: UserProfile
    
    private init() {
        self.profile = UserProfile.load()
    }
    
    func save() {
        profile.save()
    }
    
    func addContact(_ contact: UserProfile.Contact) {
        // Don't add if it's the user themselves
        if profile.isMe(contact.name) { return }
        
        // Don't add duplicates
        if profile.knownContacts.contains(where: { $0.name.lowercased() == contact.name.lowercased() }) {
            return
        }
        
        profile.knownContacts.append(contact)
        save()
        print("👤 Added contact: \(contact.name)")
    }
    
    /// Learn contacts from extracted entities
    func learnFromEntities(_ entities: [Entity]) {
        for entity in entities where entity.type == .person {
            // Don't learn own name
            if profile.isMe(entity.value) { continue }
            
            let contact = UserProfile.Contact(
                name: entity.value,
                relationship: "contact"
            )
            addContact(contact)
        }
    }
}

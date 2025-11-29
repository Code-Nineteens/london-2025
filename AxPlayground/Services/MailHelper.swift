//
//  MailHelper.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa

/// Helper for opening mail client using AppleScript.
struct MailHelper {
    
    // MARK: - Public Methods
    
    /// Opens Mail.app.
    static func openMailApp() {
        runAppleScript("""
            tell application "Mail"
                activate
            end tell
        """)
    }
    
    /// Composes a new email in Mail.app.
    static func compose(
        to recipient: String? = nil,
        subject: String? = nil,
        body: String? = nil
    ) {
        var properties: [String] = []
        
        if let subject = subject {
            properties.append("subject:\"\(escapeForAppleScript(subject))\"")
        }
        
        if let body = body {
            properties.append("content:\"\(escapeForAppleScript(body))\"")
        }
        
        let propertiesString = properties.isEmpty ? "" : " with properties {\(properties.joined(separator: ", "))}"
        
        var recipientBlock = ""
        if let recipient = recipient {
            recipientBlock = """
                tell newMessage
                    make new to recipient with properties {address:"\(escapeForAppleScript(recipient))"}
                end tell
            """
        }
        
        let script = """
            tell application "Mail"
                activate
                set newMessage to make new outgoing message\(propertiesString)
                \(recipientBlock)
                tell newMessage
                    set visible to true
                end tell
            end tell
        """
        
        runAppleScript(script)
    }
    
    /// Composes an email with screen text content.
    static func sendScreenText(_ text: String) {
        compose(
            subject: "Screen Text Export",
            body: text
        )
    }
    
    // MARK: - Private Methods
    
    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else {
            print("❌ Failed to create AppleScript")
            return
        }
        
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript error: \(error)")
        }
    }
    
    private static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

//
//  MailHelper.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa

/// Helper for opening mail client using AppleScript.
struct MailHelper {
    
    /// Opens Mail.app using osascript (triggers permission dialog).
    static func openMailApp() {
        runOsascript("""
            tell application "Mail"
                activate
            end tell
        """)
    }
    
    /// Run AppleScript via osascript command - this properly triggers permission dialogs
    private static func runOsascript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📧 osascript output: \(output)")
            }
            
            if task.terminationStatus != 0 {
                print("❌ osascript failed with status: \(task.terminationStatus)")
            } else {
                print("✅ osascript succeeded")
            }
        } catch {
            print("❌ Failed to run osascript: \(error)")
        }
    }
    
    /// Composes a new email in Mail.app using osascript.
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
        
        runOsascript(script)
    }
    
    // MARK: - Private Methods
    
    private static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

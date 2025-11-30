//
//  BrowserMonitor.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 30/11/2025.
//

import Cocoa
import Combine
import ApplicationServices

// MARK: - IssueInfo

/// Represents a detected GitHub/GitLab issue.
struct IssueInfo: Equatable {
    let url: String
    let issueNumber: String
    let repository: String
    let browserName: String
}

// MARK: - BrowserMonitor

/// Monitors browser tabs for GitHub/GitLab issues pages using Accessibility API.
@MainActor
final class BrowserMonitor: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = BrowserMonitor()
    
    // MARK: - Published Properties
    
    @Published var isMonitoring = false
    @Published var currentIssue: IssueInfo?
    @Published var lastShownIssueURL: String?
    
    // MARK: - Properties
    
    private var monitorTimer: Timer?
    private var onIssueDetected: (@MainActor (IssueInfo) -> Void)?
    
    /// Regex pattern for GitHub issues.
    private let githubIssuePattern = #"github\.com/([^/]+/[^/]+)/issues/(\d+)"#
    
    /// Regex pattern for GitLab issues.
    private let gitlabIssuePattern = #"gitlab\.com/([^/]+(?:/[^/]+)*)/(?:-/)?issues/(\d+)"#
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Starts monitoring browser tabs for issues.
    ///
    /// - Parameters:
    ///   - interval: Check interval in seconds (default: 2.0).
    ///   - onIssueDetected: Callback when an issue page is detected.
    func startMonitoring(interval: TimeInterval = 2.0, onIssueDetected: @escaping @MainActor (IssueInfo) -> Void) {
        stopMonitoring()
        
        self.onIssueDetected = onIssueDetected
        isMonitoring = true
        
        print("🌐 Starting browser monitor...")
        
        // Check immediately
        checkCurrentTab()
        
        // Then check periodically
        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkCurrentTab()
            }
        }
    }
    
    /// Stops monitoring.
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
        onIssueDetected = nil
        currentIssue = nil
        print("🌐 Stopped browser monitor")
    }
    
    /// Resets the "already shown" state so the same issue can trigger again.
    func resetShownState() {
        lastShownIssueURL = nil
    }
    
    // MARK: - Private Methods
    
    private func checkCurrentTab() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            currentIssue = nil
            return
        }
        
        let browserName = frontApp.localizedName ?? "Browser"
        
        // Get URL using Accessibility API (works for any browser)
        guard let url = getURLFromFocusedApp(pid: frontApp.processIdentifier) else {
            // No URL found - this is normal for non-browser apps
            currentIssue = nil
            return
        }
        
        print("🌐 BrowserMonitor found URL: \(url.prefix(80))...")
        
        // Check if it's an issue page
        if let issueInfo = parseIssueURL(url, browserName: browserName) {
            print("🎯 Issue detected: \(issueInfo.repository)#\(issueInfo.issueNumber)")
            currentIssue = issueInfo
            
            // Only trigger callback if this is a new issue (not already shown)
            if issueInfo.url != lastShownIssueURL {
                print("🔔 New issue detected, showing notification...")
                lastShownIssueURL = issueInfo.url
                onIssueDetected?(issueInfo)
            } else {
                print("🔄 Same issue as before, skipping notification")
            }
        } else {
            print("📄 URL is not an issue page")
            currentIssue = nil
        }
    }
    
    /// Gets URL from any browser using Accessibility API.
    private func getURLFromFocusedApp(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get focused window
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else {
            return nil
        }
        
        // swiftlint:disable:next force_cast
        let windowElement = window as! AXUIElement
        
        // Search for URL in window elements
        let url = findURLInElement(windowElement, depth: 0)
        return url
    }
    
    /// Recursively searches for URL-like text in AX elements.
    private func findURLInElement(_ element: AXUIElement, depth: Int) -> String? {
        guard depth < 15 else { return nil }
        
        // Get role for debugging
        var role: AnyObject?
        var roleString = ""
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let r = role as? String {
            roleString = r
        }
        
        // Check element's value
        if let url = extractURLFromElement(element) {
            print("🔗 Found URL in \(roleString) at depth \(depth)")
            return url
        }
        
        // Check children
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else {
            return nil
        }
        
        for child in childArray {
            if let url = findURLInElement(child, depth: depth + 1) {
                return url
            }
        }
        
        return nil
    }
    
    /// Extracts URL from element's value or URL attribute.
    private func extractURLFromElement(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        
        // Try AXValue (text field content)
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String,
           isValidURL(text) {
            return text
        }
        
        // Try AXURL attribute (some browsers use this)
        if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success {
            if let url = value as? URL {
                return url.absoluteString
            }
            if let urlString = value as? String, isValidURL(urlString) {
                return urlString
            }
        }
        
        // Try kAXURLAttribute
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success {
            if let url = value as? URL {
                return url.absoluteString
            }
            if let urlString = value as? String, isValidURL(urlString) {
                return urlString
            }
        }
        
        // Check role - if it's a text field or combo box, check value more liberally
        var role: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleString = role as? String,
           roleString == "AXTextField" || roleString == "AXComboBox" {
            
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                // Check if it looks like a URL (contains github.com or gitlab.com)
                if text.contains("github.com") || text.contains("gitlab.com") {
                    // Add https:// if missing
                    if text.hasPrefix("http://") || text.hasPrefix("https://") {
                        return text
                    } else {
                        return "https://\(text)"
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Checks if string looks like a valid URL.
    private func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) &&
               trimmed.contains(".")
    }
    
    private func parseIssueURL(_ url: String, browserName: String) -> IssueInfo? {
        // Try GitHub pattern
        if let match = url.range(of: githubIssuePattern, options: .regularExpression) {
            let matchedString = String(url[match])
            
            // Extract components
            if let repoMatch = matchedString.range(of: #"github\.com/([^/]+/[^/]+)"#, options: .regularExpression),
               let issueMatch = matchedString.range(of: #"issues/(\d+)"#, options: .regularExpression) {
                
                let repo = String(matchedString[repoMatch])
                    .replacingOccurrences(of: "github.com/", with: "")
                let issueNumber = String(matchedString[issueMatch])
                    .replacingOccurrences(of: "issues/", with: "")
                
                return IssueInfo(
                    url: url,
                    issueNumber: issueNumber,
                    repository: repo,
                    browserName: browserName
                )
            }
        }
        
        // Try GitLab pattern
        if let match = url.range(of: gitlabIssuePattern, options: .regularExpression) {
            let matchedString = String(url[match])
            
            if let repoMatch = matchedString.range(of: #"gitlab\.com/([^/]+(?:/[^/]+)*)"#, options: .regularExpression),
               let issueMatch = matchedString.range(of: #"issues/(\d+)"#, options: .regularExpression) {
                
                let repo = String(matchedString[repoMatch])
                    .replacingOccurrences(of: "gitlab.com/", with: "")
                    .replacingOccurrences(of: "/-", with: "")
                let issueNumber = String(matchedString[issueMatch])
                    .replacingOccurrences(of: "issues/", with: "")
                
                return IssueInfo(
                    url: url,
                    issueNumber: issueNumber,
                    repository: repo,
                    browserName: browserName
                )
            }
        }
        
        return nil
    }
}



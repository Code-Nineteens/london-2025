//
//  ScreenTextMonitor.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Monitors screen for text changes in real-time
@MainActor
final class ScreenTextMonitor: ObservableObject {
    
    static let shared = ScreenTextMonitor()
    
    @Published var isMonitoring = false
    @Published var lastChanges: [TextChange] = []
    
    // Simple approach: track unique texts per app (not by position)
    private var previousTexts: [String: Set<String>] = [:] // appName -> texts
    private var monitorTimer: Timer?
    private var onChangeCallback: ((TextChange) -> Void)?
    private var isFirstCheck = true
    private var lastActiveAppName: String? = nil
    
    struct TextChange: Identifiable {
        let id = UUID()
        let timestamp: Date
        let appName: String
        let oldText: String?
        let newText: String
        let changeType: ChangeType
        
        enum ChangeType {
            case added
            case modified
            case removed
        }
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring for text changes
    func startMonitoring(interval: TimeInterval = 1.0, onChange: @escaping (TextChange) -> Void) {
        stopMonitoring()
        
        self.onChangeCallback = onChange
        self.isMonitoring = true
        self.lastChanges = []
        self.isFirstCheck = true
        
        print("📡 Starting monitor... taking baseline snapshot")
        
        // Take TWO snapshots with delay to ensure stability
        self.previousTexts = getCurrentTextsPerApp()
        
        // Wait 1 second, then take another snapshot as the REAL baseline
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.isMonitoring else { return }
            
            // Take fresh baseline after 1 second
            self.previousTexts = self.getCurrentTextsPerApp()
            self.lastActiveAppName = NSWorkspace.shared.frontmostApplication?.localizedName
            self.isFirstCheck = false
            
            print("📡 Baseline set: \(self.previousTexts.values.reduce(0) { $0 + $1.count }) texts in \(self.lastActiveAppName ?? "unknown")")
            
            // NOW start the timer
            self.monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkForChanges()
                }
            }
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
        onChangeCallback = nil
        previousTexts = [:]
        lastActiveAppName = nil
        isFirstCheck = true
        print("⏹️ Stopped monitoring")
    }
    
    // MARK: - Private Methods
    
    private let ignoredBundleIds: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.universalcontrol",
    ]
    
    private func checkForChanges() {
        guard !isFirstCheck else { return }
        
        // Get current active app
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let activeAppName = activeApp.localizedName else {
            return
        }
        
        // If active app changed, reset baseline (don't report as changes)
        if lastActiveAppName != activeAppName {
            print("📱 Active app changed to: \(activeAppName) - resetting baseline")
            lastActiveAppName = activeAppName
            previousTexts = getCurrentTextsPerApp()
            return // Don't check for changes on app switch
        }
        
        let currentTexts = getCurrentTextsPerApp()
        
        // Compare per app - only for active app
        for (appName, currentSet) in currentTexts {
            let previousSet = previousTexts[appName] ?? []
            
            // New texts in this app
            let addedTexts = currentSet.subtracting(previousSet)
            for text in addedTexts {
                reportChange(TextChange(
                    timestamp: Date(),
                    appName: appName,
                    oldText: nil,
                    newText: text,
                    changeType: .added
                ))
            }
            
            // Removed texts
            let removedTexts = previousSet.subtracting(currentSet)
            for text in removedTexts {
                reportChange(TextChange(
                    timestamp: Date(),
                    appName: appName,
                    oldText: text,
                    newText: "",
                    changeType: .removed
                ))
            }
        }
        
        previousTexts = currentTexts
    }
    
    private func reportChange(_ change: TextChange) {
        // Ignore own bundle ID
        if let myBundleId = Bundle.main.bundleIdentifier,
           change.appName.contains("vibecodeos") || change.appName == myBundleId {
            return
        }
        
        lastChanges.insert(change, at: 0)
        if lastChanges.count > 50 {
            lastChanges = Array(lastChanges.prefix(50))
        }
        
        onChangeCallback?(change)
    }
    
    private func getCurrentTextsPerApp() -> [String: Set<String>] {
        guard let screen = NSScreen.main else { return [:] }
        let screenRect = screen.frame
        
        var result: [String: Set<String>] = [:]
        
        // ONLY monitor the ACTIVE (frontmost) application
        // This prevents detecting automatic changes in background apps (like Dia's rotating placeholder)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            // Skip if not the active app
            guard app.isActive else { continue }
            
            guard let bundleId = app.bundleIdentifier,
                  !ignoredBundleIds.contains(bundleId),
                  bundleId != Bundle.main.bundleIdentifier else { continue }
            
            let appName = app.localizedName ?? "Unknown"
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            
            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }
            
            var appTexts: Set<String> = []
            
            for window in windows {
                let windowPos = extractPosition(from: window)
                let windowSize = extractSize(from: window)
                let windowRect = CGRect(origin: windowPos, size: windowSize)
                
                guard screenRect.intersects(windowRect) else { continue }
                
                let visibleRect = screenRect.intersection(windowRect)
                extractTexts(window, visibleRect: visibleRect, into: &appTexts)
            }
            
            if !appTexts.isEmpty {
                result[appName] = appTexts
            }
        }
        
        return result
    }
    
    private func extractTexts(_ element: AXUIElement, visibleRect: CGRect, into texts: inout Set<String>, depth: Int = 0) {
        guard depth < 15 else { return }
        
        let position = extractPosition(from: element)
        let size = extractSize(from: element)
        
        guard size.width > 0 && size.height > 0 else { return }
        
        let elementRect = CGRect(origin: position, size: size)
        guard visibleRect.intersects(elementRect) else { return }
        
        // Get text - only meaningful texts
        if let text = getTextFromElement(element),
           !text.isEmpty,
           text.count > 3,
           !text.allSatisfy({ $0.isWhitespace || $0.isNewline }) {
            texts.insert(text)
        }
        
        // Recurse children
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray {
                extractTexts(child, visibleRect: visibleRect, into: &texts, depth: depth + 1)
            }
        }
    }
    
    private func getTextFromElement(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }
        
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }
        
        return nil
    }
    
    private func extractPosition(from element: AXUIElement) -> CGPoint {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success else {
            return .zero
        }
        
        let axValue = value as! AXValue
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }
    
    private func extractSize(from element: AXUIElement) -> CGSize {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success else {
            return .zero
        }
        
        let axValue = value as! AXValue
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}

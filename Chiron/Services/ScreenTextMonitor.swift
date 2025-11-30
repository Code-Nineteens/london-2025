//
//  ScreenTextMonitor.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Monitors screen for text changes in real-time using OCR
@MainActor
final class ScreenTextMonitor: ObservableObject {
    
    static let shared = ScreenTextMonitor()
    
    @Published var isMonitoring = false
    @Published var lastChanges: [TextChange] = []
    @Published var useOCR = true // Toggle between OCR and Accessibility
    
    /// If true, collect ALL visible text each scan (not just changes)
    /// Better for context collection
    var collectFullContent = true
    
    // OCR service
    private let ocrService = ScreenOCRService.shared
    
    // Track unique texts per app
    private var previousTexts: Set<String> = []
    private var lastFullContentHash: Int = 0
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
    
    /// Start monitoring for text changes (using OCR)
    func startMonitoring(interval: TimeInterval = 2.0, onChange: @escaping (TextChange) -> Void) {
        stopMonitoring()
        
        self.onChangeCallback = onChange
        self.isMonitoring = true
        self.lastChanges = []
        self.isFirstCheck = true
        
        print("📡 ============================================")
        print("📡 Starting OCR monitor (interval: \(interval)s)")
        print("📡 ============================================")
        
        // Take baseline with OCR
        Task {
            print("📡 Taking baseline snapshot...")
            self.previousTexts = await getCurrentTextsWithOCR()
            self.lastActiveAppName = NSWorkspace.shared.frontmostApplication?.localizedName
            self.isFirstCheck = false
            
            print("📡 ✅ Baseline set: \(self.previousTexts.count) texts in \(self.lastActiveAppName ?? "unknown")")
            print("📡 Starting timer...")
            
            // Start the timer (longer interval for OCR - more CPU intensive)
            self.monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkForChangesWithOCR()
                }
            }
            print("📡 ✅ Timer started")
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
        onChangeCallback = nil
        previousTexts = []
        lastActiveAppName = nil
        isFirstCheck = true
        print("⏹️ Stopped OCR monitoring")
    }
    
    // MARK: - OCR Methods
    
    private let ignoredBundleIds: Set<String> = [
        // System apps
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.universalcontrol",
        "com.apple.SecurityAgent",  // Touch ID, password dialogs
        "com.apple.UserNotificationCenter",
        
        // Dev tools - too much noise
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        
        // IDEs - capture our own output
        "com.todesktop.230313mzl4w4u92",  // Windsurf
        "com.todesktop.cursor",  // Cursor
        "com.microsoft.VSCode",
    ]
    
    /// Get current texts using OCR
    private func getCurrentTextsWithOCR() async -> Set<String> {
        // Skip if we're the active app
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           activeApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            print("📡 OCR Monitor: skipping - we are active app")
            return previousTexts
        }
        
        // Skip ignored apps
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier,
           ignoredBundleIds.contains(bundleId) {
            print("📡 OCR Monitor: skipping - ignored app \(bundleId)")
            return previousTexts
        }
        
        print("📡 OCR Monitor: calling OCR service...")
        let texts = await ocrService.captureAndGetTexts()
        print("📡 OCR Monitor: got \(texts.count) texts")
        return texts
    }
    
    /// Check for text changes using OCR
    private func checkForChangesWithOCR() async {
        guard !isFirstCheck else { 
            print("📡 OCR Monitor: isFirstCheck=true, skipping")
            return 
        }
        
        // Get current active app
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let activeAppName = activeApp.localizedName else {
            print("📡 OCR Monitor: no active app")
            return
        }
        
        // If active app changed, reset
        if lastActiveAppName != activeAppName {
            print("📱 Active app changed to: \(activeAppName)")
            lastActiveAppName = activeAppName
            previousTexts = []
            lastFullContentHash = 0
        }
        
        let currentTexts = await getCurrentTextsWithOCR()
        guard !currentTexts.isEmpty else { return }
        
        if collectFullContent {
            // MODE 1: Collect ALL visible text (better for context)
            let meaningfulTexts = currentTexts.filter { text in
                text.count > 3 && !isNoiseText(text)
            }
            
            let combinedText = meaningfulTexts.sorted().joined(separator: "\n")
            let contentHash = combinedText.hashValue
            
            // Only report if content changed significantly
            if contentHash != lastFullContentHash && combinedText.count > 50 {
                lastFullContentHash = contentHash
                
                print("📡 OCR Full Content: \(meaningfulTexts.count) texts, \(combinedText.count) chars")
                
                reportChange(TextChange(
                    timestamp: Date(),
                    appName: activeAppName,
                    oldText: nil,
                    newText: combinedText,
                    changeType: .added
                ))
            }
        } else {
            // MODE 2: Only report changes (original behavior)
            let addedTexts = currentTexts.subtracting(previousTexts)
            let meaningfulTexts = addedTexts.filter { text in
                text.count > 3 && !isNoiseText(text)
            }
            
            if !meaningfulTexts.isEmpty {
                let combinedText = meaningfulTexts.sorted().joined(separator: "\n")
                print("📡 OCR Changes: \(meaningfulTexts.count) new texts")
                
                reportChange(TextChange(
                    timestamp: Date(),
                    appName: activeAppName,
                    oldText: nil,
                    newText: combinedText,
                    changeType: .added
                ))
            }
        }
        
        previousTexts = currentTexts
    }
    
    /// Check if text is noise (UI elements, etc.)
    private func isNoiseText(_ text: String) -> Bool {
        let lower = text.lowercased()
        
        // Only filter exact match menu items
        let noisePatterns = [
            "file", "edit", "view", "window", "help",
            "close", "minimize", "maximize", "zoom",
            "ok", "cancel", "save", "open", "new"
        ]
        
        // Only filter if it's an exact match (not part of larger text)
        if noisePatterns.contains(lower) { 
            return true 
        }
        
        // Filter keyboard shortcut symbols only
        if text.allSatisfy({ "⌘⇧⌥⌃◀▶▲▼←→↑↓".contains($0) }) {
            return true
        }
        
        return false
    }
    
    private func reportChange(_ change: TextChange) {
        // Ignore own bundle ID
        if let myBundleId = Bundle.main.bundleIdentifier,
           change.appName.contains("vibecodeos") || change.appName == myBundleId {
            print("📡 reportChange: SKIP - own app")
            return
        }
        
        print("📡 reportChange: ✅ sending \(change.newText.count) chars from \(change.appName)")
        
        lastChanges.insert(change, at: 0)
        if lastChanges.count > 50 {
            lastChanges = Array(lastChanges.prefix(50))
        }
        
        onChangeCallback?(change)
    }
}

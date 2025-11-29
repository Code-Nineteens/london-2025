//
//  NotificationCenterObserver.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Observes macOS Notification Center for incoming notifications using Accessibility API
@MainActor
final class NotificationCenterObserver: ObservableObject {

    static let shared = NotificationCenterObserver()

    // MARK: - Published Properties

    @Published var isObserving = false
    @Published var lastNotificationTime: Date?

    // MARK: - Private Properties

    private var observer: AXObserver?
    private var notificationCenterApp: AXUIElement?
    private var pollTimer: Timer?
    private var lastWindowCount = 0
    private var debounceWorkItem: DispatchWorkItem?

    // Callback when notification is detected
    var onNotificationDetected: ((String?, String?) -> Void)?

    private init() {}

    // MARK: - Public Methods

    func startObserving() {
        guard !isObserving else { return }

        print("🔔 Starting Notification Center observer...")

        // Start polling for notification windows
        startPolling()

        isObserving = true
        print("✅ Notification Center observer is active")
    }

    func stopObserving() {
        stopPolling()
        cleanupObserver()
        isObserving = false
        print("⏹️ Notification Center observer stopped")
    }

    // MARK: - Private Methods

    private func startPolling() {
        // Poll every 0.5 seconds for notification banners
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkForNotifications()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForNotifications() {
        // Look for NotificationCenter process
        let runningApps = NSWorkspace.shared.runningApplications

        guard let notificationCenter = runningApps.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }) else {
            return
        }

        let pid = notificationCenter.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get all windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            // No windows - reset counter
            if lastWindowCount > 0 {
                lastWindowCount = 0
            }
            return
        }

        let currentWindowCount = windows.count

        // New notification appeared
        if currentWindowCount > lastWindowCount && currentWindowCount > 0 {
            handleNewNotification(windows: windows)
        }

        lastWindowCount = currentWindowCount
    }

    private func handleNewNotification(windows: [AXUIElement]) {
        // Debounce to avoid multiple triggers
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.processNotification(windows: windows)
            }
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func processNotification(windows: [AXUIElement]) {
        guard let window = windows.first else { return }

        // Try to extract notification content
        let (title, body) = extractNotificationContent(from: window)

        print("🔔 System notification detected!")
        if let title = title {
            print("   Title: \(title)")
        }
        if let body = body {
            print("   Body: \(body)")
        }

        lastNotificationTime = Date()

        // Trigger callback
        onNotificationDetected?(title, body)
    }

    private func extractNotificationContent(from element: AXUIElement) -> (title: String?, body: String?) {
        // Collect all text from the notification hierarchy
        var allTexts: [String] = []
        collectAllText(from: element, into: &allTexts)

        // Debug: print all found texts
        print("   Found texts: \(allTexts)")

        // Filter out empty strings and common UI elements
        let filteredTexts = allTexts.filter { text in
            !text.isEmpty &&
            text != "Close" &&
            text != "Options" &&
            text != "Reply" &&
            !text.hasPrefix("Notification") &&
            text.count > 1
        }

        // Usually: first text is app/sender name, second is message content
        // For Messages: "Name", "Message content"
        let title = filteredTexts.first
        let body = filteredTexts.count > 1 ? filteredTexts.dropFirst().joined(separator: "\n") : nil

        return (title, body)
    }

    private func collectAllText(from element: AXUIElement, into texts: inout [String]) {
        // Try multiple attributes that might contain text
        let textAttributes = [
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute
        ]

        for attribute in textAttributes {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
               let text = valueRef as? String,
               !text.isEmpty {
                if !texts.contains(text) {
                    texts.append(text)
                }
            }
        }

        // Get role to check if it's a text element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // For static text, also try to get the value
        if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let text = valueRef as? String,
               !text.isEmpty,
               !texts.contains(text) {
                texts.append(text)
            }
        }

        // Recursively process children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectAllText(from: child, into: &texts)
            }
        }
    }

    private func cleanupObserver() {
        observer = nil
        notificationCenterApp = nil
    }
}

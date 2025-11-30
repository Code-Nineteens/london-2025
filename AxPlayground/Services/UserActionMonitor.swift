//
//  UserActionMonitor.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Monitors user actions: app launches, button clicks, text input, focus changes
@MainActor
final class UserActionMonitor: ObservableObject {
    
    nonisolated let objectWillChange = ObservableObjectPublisher()
    
    static let shared = UserActionMonitor()
    
    
    @Published var isMonitoring = false
    @Published var actionLog: [UserAction] = []
    
    private var onActionCallback: ((UserAction) -> Void)?
    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastFocusedElement: String? = nil
    private var lastActiveApp: String? = nil
    private var lastTextValue: String = ""
    private var currentlyFocusedRole: String? = nil
    private var textDebounceTimer: Timer?
    private var pendingTextAction: UserAction?
    private var lastReportedAction: String = ""
    
    private var lastReportTime: Date = .distantPast
    
    struct UserAction: Identifiable {
        let id = UUID()
        let timestamp: Date
        let actionType: ActionType
        let appName: String
        let details: String
        let rawNotification: String? // Raw AX notification name
        
        enum ActionType: String {
            case appLaunched = "🚀 App Launched"
            case appActivated = "📱 Switched to"
            case appQuit = "❌ App Closed"
            case buttonClicked = "🖱️ Clicked"
            case textEntered = "⌨️ Typed"
            case focusChanged = "👁️ Focused"
            case menuSelected = "📋 Menu"
            case windowOpened = "🪟 Window Opened"
            case windowClosed = "🪟 Window Closed"
        }
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func startMonitoring(onAction: @escaping (UserAction) -> Void) {
        stopMonitoring()
        
        self.onActionCallback = onAction
        self.isMonitoring = true
        self.actionLog = []
        self.lastActiveApp = NSWorkspace.shared.frontmostApplication?.localizedName
        
        print("📡 Starting user action monitoring...")
        
        setupWorkspaceObservers()
        setupAccessibilityObservers()
        
        // Nie logujemy sztucznych eventów "Monitoring started"
    }
    
    func stopMonitoring() {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        
        for (_, observer) in axObservers {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        axObservers.removeAll()
        
        textDebounceTimer?.invalidate()
        isMonitoring = false
        onActionCallback = nil
        print("⏹️ Stopped user action monitoring")
    }
    
    // MARK: - Workspace Observers
    
    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        
        let launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let appName = app.localizedName else { return }
            
            Task { @MainActor in
                self?.reportAction(UserAction(
                    timestamp: Date(),
                    actionType: .appLaunched,
                    appName: appName,
                    details: "Application started",
                    rawNotification: "NSWorkspace.didLaunchApplication"
                ))
            }
        }
        workspaceObservers.append(launchObserver)
        
        let quitObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let appName = app.localizedName else { return }
            
            Task { @MainActor in
                self?.reportAction(UserAction(
                    timestamp: Date(),
                    actionType: .appQuit,
                    appName: appName,
                    details: "Application closed",
                    rawNotification: "NSWorkspace.didTerminateApplication"
                ))
            }
        }
        workspaceObservers.append(quitObserver)
        
        let activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let appName = app.localizedName else { return }
            
            Task { @MainActor in
                guard let self = self else { return }
                
                if self.lastActiveApp != appName {
                    self.lastActiveApp = appName
                    self.reportAction(UserAction(
                        timestamp: Date(),
                        actionType: .appActivated,
                        appName: appName,
                        details: "Switched to this app",
                        rawNotification: "NSWorkspace.didActivateApplication"
                    ))
                    self.setupAXObserver(for: app)
                }
            }
        }
        workspaceObservers.append(activateObserver)
    }
    
    // MARK: - Accessibility Observers
    
    private func setupAccessibilityObservers() {
        if let app = NSWorkspace.shared.frontmostApplication {
            setupAXObserver(for: app)
        }
    }
    
    private func setupAXObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        
        if let existingObserver = axObservers[pid] {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(existingObserver),
                .defaultMode
            )
            axObservers.removeValue(forKey: pid)
        }
        
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)
        
        guard result == .success, let observer = observer else {
            print("⚠️ Failed to create AX observer for \(app.localizedName ?? "unknown")")
            return
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        let notifications: [String] = [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
        ]
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }
        
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        
        axObservers[pid] = observer
    }
    
    // MARK: - Handle AX Notifications
    
    fileprivate func handleAXNotification(_ notification: String, element: AXUIElement) {
        let appName = lastActiveApp ?? "Unknown"
        
        var roleValue: AnyObject?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success)
            ? (roleValue as? String ?? "")
            : ""
        
        var titleValue: AnyObject?
        let title = (AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success)
            ? (titleValue as? String ?? "")
            : ""
        
        var descValue: AnyObject?
        let desc = (AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue) == .success)
            ? (descValue as? String ?? "")
            : ""
        
        let elementName = !title.isEmpty ? title : (!desc.isEmpty ? desc : role)
        
        switch notification {
        case kAXFocusedUIElementChangedNotification:
            let focusId = "\(role):\(title)"
            if focusId != lastFocusedElement && !elementName.isEmpty {
                lastFocusedElement = focusId
                currentlyFocusedRole = role
                
                if role == "AXTextField" || role == "AXTextArea" || role == "AXSearchField" || role == "AXComboBox" {
                    var valueObj: AnyObject?
                    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj) == .success,
                       let value = valueObj as? String {
                        lastTextValue = value
                    } else {
                        lastTextValue = ""
                    }
                    reportAction(UserAction(
                        timestamp: Date(),
                        actionType: .focusChanged,
                        appName: appName,
                        details: "Role: \(role) | Element: \(elementName.isEmpty ? "(unnamed)" : elementName)",
                        rawNotification: kAXFocusedUIElementChangedNotification
                    ))
                } else if role == "AXButton" || role == "AXLink" {
                    reportAction(UserAction(
                        timestamp: Date(),
                        actionType: .buttonClicked,
                        appName: appName,
                        details: "Role: \(role) | Element: \(elementName)",
                        rawNotification: kAXFocusedUIElementChangedNotification
                    ))
                } else if role == "AXMenuItem" {
                    reportAction(UserAction(
                        timestamp: Date(),
                        actionType: .menuSelected,
                        appName: appName,
                        details: "Role: \(role) | Element: \(elementName)",
                        rawNotification: kAXFocusedUIElementChangedNotification
                    ))
                }
            }
            
        case kAXValueChangedNotification:
            let isTextField = role == "AXTextField" || role == "AXTextArea" || role == "AXSearchField" || role == "AXComboBox"
            let wasFocusedOnTextField = currentlyFocusedRole == "AXTextField" || currentlyFocusedRole == "AXTextArea" || currentlyFocusedRole == "AXSearchField" || currentlyFocusedRole == "AXComboBox"
            
            if isTextField || wasFocusedOnTextField {
                var valueObj: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj) == .success,
                   let value = valueObj as? String {
                    if value != lastTextValue && !value.isEmpty && value.count > 1 {
                        lastTextValue = value
                        
                        textDebounceTimer?.invalidate()
                        pendingTextAction = UserAction(
                            timestamp: Date(),
                            actionType: .textEntered,
                            appName: appName,
                            details: "Role: \(role) | Value: \(String(value.suffix(50)))",
                            rawNotification: kAXValueChangedNotification
                        )
                        textDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                if let action = self?.pendingTextAction {
                                    self?.reportAction(action)
                                    self?.pendingTextAction = nil
                                }
                            }
                        }
                    }
                }
            }
            
        default:
            break
        }
    }
    
    private func reportAction(_ action: UserAction) {
        if action.appName == "Chiron" { return }
        
        let trimmedDetails = action.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDetails.isEmpty { return }
        
        let actionKey = "\(action.actionType.rawValue)|\(action.appName)|\(trimmedDetails)"
        
        let now = Date()
        if actionKey == lastReportedAction && now.timeIntervalSince(lastReportTime) < 1.0 {
            return
        }
        
        lastReportedAction = actionKey
        lastReportTime = now
        
        actionLog.insert(action, at: 0)
        if actionLog.count > 100 {
            actionLog = Array(actionLog.prefix(100))
        }
        
        onActionCallback?(action)
        print("\(action.actionType.rawValue) [\(action.appName)] \(trimmedDetails)")
    }
}

// MARK: - AX Callback

private let axCallback: AXObserverCallback = { observer, element, notification, refcon in
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<UserActionMonitor>.fromOpaque(refcon).takeUnretainedValue()
    
    Task { @MainActor in
        monitor.handleAXNotification(notification as String, element: element)
    }
}

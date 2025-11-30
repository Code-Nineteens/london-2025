//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {

    init() {
        EnvManager.shared.loadSilently()
        setupNotificationObserver()
    }
    
    /// Load .env file and return dictionary of key-value pairs
    private func loadEnvFile() -> [String: String] {
        var result: [String: String] = [:]
        
        // Try project root .env
        let projectEnvPath = "/Users/filipwnek/Projects/london-2025/.env"
        
        guard let contents = try? String(contentsOfFile: projectEnvPath, encoding: .utf8) else {
            print("⚠️ Could not read .env file at \(projectEnvPath)")
            return result
        }
        
        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            // Parse KEY=VALUE
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
            
            // Remove quotes if present
            let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            
            result[key] = cleanValue
            print("📄 Loaded from .env: \(key)=\(String(cleanValue.prefix(10)))...")
        }
        
        return result
    }
  
    @StateObject private var textChangesOverlayController = TextChangesOverlayController.shared
    @StateObject private var accessibilityMonitor = AccessibilityMonitor()
    @StateObject private var notificationObserver = NotificationCenterObserver.shared
    @StateObject private var textMonitor = ScreenTextMonitor.shared
    @StateObject private var actionMonitor = UserActionMonitor.shared
    @StateObject private var activityLogger = ScreenActivityLogger.shared
    @StateObject private var automationService = AutomationSuggestionService.shared

    @State private var taskItems: [TaskItem] = [
        TaskItem(title: "Review accessibility events", status: .completed),
        TaskItem(title: "Analyze click patterns", status: .completed),
        TaskItem(title: "Configure monitoring filters", status: .inProgress),
        TaskItem(title: "Debug keyboard shortcuts", status: .inProgress),
        TaskItem(title: "Export captured data", status: .idle),
        TaskItem(title: "Add custom event filters", status: .idle),
        TaskItem(title: "Implement batch processing", status: .idle),
        TaskItem(title: "Create usage report", status: .idle),
        TaskItem(title: "Setup automated alerts", status: .idle)
    ]

    var body: some Scene {
        Window("Dashboard", id: "dashboard") {
            ContentView()
                .environmentObject(accessibilityMonitor)
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            MenuBarView(
                taskItems: $taskItems,
                accessibilityMonitor: accessibilityMonitor,
                notificationObserver: notificationObserver,
                screenTextMonitor: textMonitor,
                actionMonitor: actionMonitor,
                activityLogger: activityLogger,
                automationService: automationService
            )
        }
        .menuBarExtraStyle(.window)
    }

    private func setupNotificationObserver() {
        NotificationCenterObserver.shared.onNotificationDetected = { title, body in
            guard let body = body, !body.isEmpty else { return }

            print("📨 Notification received: \(body.prefix(100))")

            Task {
                // Collect context from notification
                await ContextCollector.shared.collectFromNotification(
                    title: title,
                    body: body,
                    app: title?.components(separatedBy: ",").first ?? "System"
                )

                // Send to AI for analysis - only send the body content
                await AutomationSuggestionService.shared.processAction(
                    actionType: "system_notification",
                    appName: title?.components(separatedBy: ",").first ?? "System",
                    details: body
                )
            }
        }

        // Auto-start observing
        NotificationCenterObserver.shared.startObserving()
        
        // Load .env file
        let envVars = loadEnvFile()
        
        // Initialize services
        Task {
            // Configure Anthropic API
            let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? envVars["ANTHROPIC_API_KEY"]
            if let key = anthropicKey, !key.isEmpty {
                print("🔑 Found Anthropic API key")
                await AutomationSuggestionService.shared.configureAPIKey(key)
            } else {
                print("⚠️ No Anthropic API key found")
            }
            
            // Configure OpenAI API (for embeddings)
            let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? envVars["OPENAI_API_KEY"]
            if let key = openAIKey, !key.isEmpty {
                print("🔑 Found OpenAI API key")
                await OpenAIEmbeddingService.shared.setAPIKey(key)
            } else {
                print("⚠️ No OpenAI API key found - embeddings disabled")
            }
            
            // Start context collection
            await ContextCollector.shared.startCollecting()
            print("🔍 Context collection started")
            
            // Enable AI suggestions
            AutomationSuggestionService.shared.setEnabled(true)
            print("🤖 AI Suggestions enabled")
            
            // Start monitoring user actions and collect context
            startUserActionMonitoring()
            
            // Start continuous screen text monitoring
            startScreenTextMonitoring()
        }
    }
    
    private func startUserActionMonitoring() {
        UserActionMonitor.shared.startMonitoring { action in
            Task {
                // Collect to context store
                await ContextCollector.shared.collectFromUserAction(action: action)
                
                // Also send to AI for intent analysis (if it's text input)
                if action.actionType == .textEntered {
                    await AutomationSuggestionService.shared.processAction(
                        actionType: action.actionType.rawValue,
                        appName: action.appName,
                        details: action.details
                    )
                }
            }
        }
        print("👁️ User action monitoring started")
    }
    
    private func startScreenTextMonitoring() {
        ScreenTextMonitor.shared.startMonitoring(interval: 1.0) { change in
            Task {
                // Convert to AXEvent and collect
                let event = AXEvent(
                    actionType: "screen_text_\(change.changeType)",
                    appName: change.appName,
                    elementRole: nil,
                    textContent: change.newText
                )
                await ContextCollector.shared.collectFromEvent(event)
            }
        }
        print("👁️ Screen text monitoring started (1s interval)")
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {

    @Binding var taskItems: [TaskItem]
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor
    @ObservedObject var notificationObserver: NotificationCenterObserver
    @ObservedObject var screenTextMonitor: ScreenTextMonitor
    @ObservedObject var actionMonitor: UserActionMonitor
    @ObservedObject var activityLogger: ScreenActivityLogger
    @ObservedObject var automationService: AutomationSuggestionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monitoringToggles
            Divider()
                .padding(.vertical, 6)
            taskQueueSection
            Divider()
                .padding(.vertical, 6)
            actionButtons
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var monitoringToggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItemButton(
                title: accessibilityMonitor.isMonitoring ? "Pause Monitoring" : "Resume Monitoring",
                systemImage: accessibilityMonitor.isMonitoring ? "pause.fill" : "play.fill"
            ) {
                if accessibilityMonitor.isMonitoring {
                    accessibilityMonitor.stopMonitoring()
                } else {
                    accessibilityMonitor.startMonitoring()
                }
            }

            MenuItemButton(
                title: notificationObserver.isObserving ? "Stop Notification Observer" : "Start Notification Observer",
                systemImage: notificationObserver.isObserving ? "bell.slash.fill" : "bell.fill"
            ) {
                if notificationObserver.isObserving {
                    notificationObserver.stopObserving()
                } else {
                    notificationObserver.startObserving()
                }
            }

            MenuItemButton(
                title: screenTextMonitor.isMonitoring ? "Stop Screen Monitor" : "Start Screen Monitor",
                systemImage: screenTextMonitor.isMonitoring ? "eye.slash.fill" : "eye.fill"
            ) {
                if screenTextMonitor.isMonitoring {
                    screenTextMonitor.stopMonitoring()
                } else {
                    screenTextMonitor.startMonitoring { change in
                        print("📝 Text change: \(change.changeType) in \(change.appName): \(change.newText.prefix(50))")
                    }
                }
            }

            MenuItemButton(
                title: actionMonitor.isMonitoring ? "Stop Action Log" : "Start Action Log",
                systemImage: actionMonitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
            ) {
                if actionMonitor.isMonitoring {
                    actionMonitor.stopMonitoring()
                } else {
                    actionMonitor.startMonitoring { action in
                        let icon: String
                        switch action.actionType {
                        case .appLaunched: icon = "app.badge.fill"
                        case .appActivated: icon = "macwindow"
                        case .appQuit: icon = "xmark.app.fill"
                        case .buttonClicked: icon = "hand.tap.fill"
                        case .textEntered: icon = "keyboard.fill"
                        case .focusChanged: icon = "eye.fill"
                        case .menuSelected: icon = "list.bullet"
                        case .windowOpened: icon = "macwindow.badge.plus"
                        case .windowClosed: icon = "macwindow.badge.minus"
                        }
                        
                        NotificationManager.shared.show(
                            title: "\(action.actionType.rawValue) \(action.appName)",
                            message: action.details,
                            icon: icon
                        )
                        
                        // Log to unified activity logger if it's running
                        ScreenActivityLogger.shared.logUserAction(action)
                    }
                }
            }
            
            MenuItemButton(
                title: activityLogger.isLogging ? "Stop Full Activity Log" : "Start Full Activity Log",
                systemImage: activityLogger.isLogging ? "stop.circle.fill" : "record.circle"
            ) {
                if activityLogger.isLogging {
                    activityLogger.stopLogging()
                } else {
                    activityLogger.startLogging()
                    
                    // Also start action monitor if not already running
                    if !actionMonitor.isMonitoring {
                        actionMonitor.startMonitoring { action in
                            ScreenActivityLogger.shared.logUserAction(action)
                        }
                    }
                    
                    // Show notification with log file path
                    if let logPath = activityLogger.logFilePath {
                        NotificationManager.shared.show(
                            title: "📝 Activity Logging Started",
                            message: "Saving to: \(logPath.components(separatedBy: "/").last ?? "log file")",
                            icon: "doc.text.fill"
                        )
                    }
                }
            }
            
            MenuItemButton(
                title: TextChangesOverlayController.shared.isVisible ? "Hide Text Changes Overlay" : "Show Text Changes Overlay",
                systemImage: TextChangesOverlayController.shared.isVisible ? "eye.slash.fill" : "eye.fill"
            ) {
                TextChangesOverlayController.shared.toggle()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // AI Automation Suggestions
            MenuItemButton(
                title: automationService.isEnabled ? "Disable AI Suggestions" : "Enable AI Suggestions",
                systemImage: automationService.isEnabled ? "wand.and.stars.inverse" : "wand.and.stars"
            ) {
                Task {
                    if automationService.isEnabled {
                        automationService.setEnabled(false)
                    } else {
                        let isReady = await automationService.isReady
                        if !isReady {
                            // API key should be set via environment variable ANTHROPIC_API_KEY
                            if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
                                await automationService.configureAPIKey(envKey)
                            } else {
                                print("⚠️ No ANTHROPIC_API_KEY environment variable set")
                            }
                        }
                        
                        automationService.setEnabled(true)
                        
                        // Start action monitor with AI processing
                        if !actionMonitor.isMonitoring {
                            actionMonitor.startMonitoring { action in
                                Task {
                                    await AutomationSuggestionService.shared.processAction(
                                        actionType: action.rawNotification ?? "unknown",
                                        appName: action.appName,
                                        details: action.details
                                    )
                                }
                                ScreenActivityLogger.shared.logUserAction(action)
                            }
                        }
                        
                        NotificationManager.shared.show(
                            title: "🤖 AI Suggestions Enabled",
                            message: "Analyzing your actions for automation opportunities",
                            icon: "wand.and.stars"
                        )
                    }
                }
            }
            
            if automationService.isEnabled {
                Text(automationService.statistics)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }

    private let maxVisibleTasks = 5

    private var visibleItems: [Binding<TaskItem>] {
        Array($taskItems.prefix(maxVisibleTasks))
    }

    private var hasMoreTasks: Bool {
        taskItems.count > maxVisibleTasks
    }

    private var remainingTasksCount: Int {
        taskItems.count - maxVisibleTasks
    }

    private var taskQueueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TASK QUEUE")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(taskItems.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ForEach(visibleItems) { $item in
                TaskItemRow(
                    item: $item,
                    onRun: { runTask(item) },
                    onDelete: { deleteTask(item) }
                )
            }

            if hasMoreTasks {
                showMoreButton
            }
        }
    }

    private var showMoreButton: some View {
        MenuItemButton(
            title: "Show \(remainingTasksCount) more...",
            systemImage: "ellipsis.circle"
        ) {
            TaskQueueWindowController.shared.show(taskItems: $taskItems)
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItemButton(title: "Test Mail (AppleScript)", systemImage: "envelope.fill") {
                MailHelper.openMailApp()
            }
            
            MenuItemButton(title: "View Context Stats", systemImage: "cylinder.fill") {
                Task {
                    await showContextStats()
                }
            }
            
            MenuItemButton(title: "Open Dashboard", systemImage: "macwindow") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuItemButton(title: "Run Devin", systemImage: "cpu") {
                Task {
                    do {
                        let session = try await DevinHelper.solveIssue(issueURL: "https://github.com/Code-Nineteens/london-2025/issues/7")
                        print("✅ Devin session created: \(session.sessionId)")
                    } catch {
                        print("❌ Devin error: \(error.localizedDescription)")
                    }
                }
            }

            MenuItemButton(title: "Show Notification", systemImage: "bell.fill") {
                NSApp.keyWindow?.close()
                NotificationManager.shared.show(
                    title: "Test Notification",
                    message: "This is a test notification from the dev menu.",
                    icon: "bell.fill",
                    onAddToQueue: {
                        TaskQueueWindowController.shared.show(taskItems: $taskItems)
                    }
                )
            }

            MenuItemButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func showContextStats() async {
        let count = (try? await ContextStore.shared.count()) ?? 0
        let recent = (try? await ContextStore.shared.getRecent(source: nil, limit: 5)) ?? []
        
        var message = "Chunks: \(count)\n\n"
        message += "Recent:\n"
        for chunk in recent {
            let preview = String(chunk.content.prefix(40))
            message += "• [\(chunk.source.rawValue)] \(preview)...\n"
        }
        
        NotificationManager.shared.show(
            title: "📦 Context Store",
            message: message,
            icon: "cylinder.fill"
        )
    }

    // MARK: - Actions

    private func runTask(_ item: TaskItem) {
        guard let index = taskItems.firstIndex(where: { $0.id == item.id }) else { return }
        taskItems[index].status = .inProgress
        print("Running task: \(item.title)")
    }

    private func deleteTask(_ item: TaskItem) {
        taskItems.removeAll { $0.id == item.id }
        print("Deleted task: \(item.title)")
    }
}

// MARK: - Task Item Row

struct TaskItemRow: View {

    @Binding var item: TaskItem
    let onRun: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            titleText
            Spacer()
            if isHovered {
                actionButtons
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Subviews

    private var statusIndicator: some View {
        Image(systemName: item.status.iconName)
            .font(.system(size: 12))
            .foregroundStyle(item.status.color)
            .frame(width: 14)
    }

    private var titleText: some View {
        Text(item.title)
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if item.status == .idle {
                Button(action: onRun) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Run now")
            }

            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
    }
}

// MARK: - Menu Item Button

struct MenuItemButton: View {

    let title: String
    var systemImage: String? = nil
    var fontWeight: Font.Weight = .regular
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(width: 16)
                }
                Text(title)
                    .font(.body)
                    .fontWeight(fontWeight)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//  Redesigned for next-level AI app aesthetic.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {

    init() {
        EnvManager.shared.loadSilently()
        setupNotificationObserver()
        setupBrowserMonitor()
    }
  
    @StateObject private var textChangesOverlayController = TextChangesOverlayController.shared
    @StateObject private var accessibilityMonitor = AccessibilityMonitor()
    @StateObject private var notificationObserver = NotificationCenterObserver.shared
    @StateObject private var textMonitor = ScreenTextMonitor.shared
    @StateObject private var actionMonitor = UserActionMonitor.shared
    @StateObject private var activityLogger = ScreenActivityLogger.shared
    @StateObject private var automationService = AutomationSuggestionService.shared
    @StateObject private var browserMonitor = BrowserMonitor.shared

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
            MenuBarViewNew(
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
                await ContextCollector.shared.collectFromNotification(
                    title: title,
                    body: body,
                    app: title?.components(separatedBy: ",").first ?? "System"
                )

                await AutomationSuggestionService.shared.processAction(
                    actionType: "system_notification",
                    appName: title?.components(separatedBy: ",").first ?? "System",
                    details: body
                )
            }
        }

        NotificationCenterObserver.shared.startObserving()
        
        Task {
            let anthropicKey = EnvManager.shared[.anthropicKey]
            if let key = anthropicKey, !key.isEmpty {
                print("🔑 Found Anthropic API key")
                await AutomationSuggestionService.shared.configureAPIKey(key)
            } else {
                print("⚠️ No Anthropic API key found")
            }
            
            let openAIKey = EnvManager.shared[.openAIKey]
            if let key = openAIKey, !key.isEmpty {
                print("🔑 Found OpenAI API key")
                await OpenAIEmbeddingService.shared.setAPIKey(key)
            } else {
                print("⚠️ No OpenAI API key found - embeddings disabled")
            }
            
            await ContextCollector.shared.startCollecting()
            print("🔍 Context collection started")
            
            AutomationSuggestionService.shared.setEnabled(true)
            print("🤖 AI Suggestions enabled")
            
            startUserActionMonitoring()
            startScreenTextMonitoring()
        }
    }
    
    private func startUserActionMonitoring() {
        UserActionMonitor.shared.startMonitoring { action in
            Task {
                if action.actionType == .textEntered {
                    await AutomationSuggestionService.shared.processAction(
                        actionType: action.actionType.rawValue,
                        appName: action.appName,
                        details: action.details
                    )
                }
            }
        }
        print("👁️ User action monitoring started (intent analysis only)")
    }
    
    private func startScreenTextMonitoring() {
        ScreenTextMonitor.shared.startMonitoring(interval: 3.0) { change in
            Task {
                await ContextCollector.shared.collectFromOCR(
                    text: change.newText,
                    appName: change.appName
                )
            }
        }
        print("👁️ OCR screen text monitoring started (3s interval)")
    }
    
    private func setupBrowserMonitor() {
        BrowserMonitor.shared.startMonitoring { issue in
            print("🔍 Detected issue: \(issue.repository)#\(issue.issueNumber)")
            
            NotificationManager.shared.show(
                title: "Issue #\(issue.issueNumber) detected",
                message: "Want AI to fix \(issue.repository)?",
                icon: "ant.fill",
                actionButtonTitle: "Fix with AI",
                actionButtonIcon: "cpu",
                onInsertNow: {
                    Task {
                        do {
                            print("🤖 Starting AI fix for: \(issue.url)")
                            let session = try await DevinHelper.solveIssue(issueURL: issue.url)
                            print("✅ Devin session created: \(session.sessionId)")
                        } catch {
                            print("❌ Failed to create Devin session: \(error.localizedDescription)")
                        }
                    }
                }
            )
        }
        print("🌐 Browser monitor started")
    }
}

// MARK: - Menu Bar View (Redesigned)

struct MenuBarViewNew: View {

    @Binding var taskItems: [TaskItem]
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor
    @ObservedObject var notificationObserver: NotificationCenterObserver
    @ObservedObject var screenTextMonitor: ScreenTextMonitor
    @ObservedObject var actionMonitor: UserActionMonitor
    @ObservedObject var activityLogger: ScreenActivityLogger
    @ObservedObject var automationService: AutomationSuggestionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            menuHeader
            
            Divider()
                .background(Color.axBorder)
            
            ScrollView {
                VStack(spacing: AXSpacing.sm) {
                    // Quick Status
                    quickStatusSection
                    
                    // Monitoring Controls
                    monitoringSection
                    
                    // AI Section
                    aiSection
                    
                    // Task Queue Preview
                    taskQueueSection
                    
                    // Quick Actions
                    quickActionsSection
                }
                .padding(AXSpacing.md)
            }
            
            Divider()
                .background(Color.axBorder)
            
            // Footer
            menuFooter
        }
        .frame(width: 340, height: 520)
        .background(Color.axSurface)
    }
    
    // MARK: - Header
    
    private var menuHeader: some View {
        HStack(spacing: AXSpacing.md) {
            ZStack {
                Circle()
                    .fill(AXGradients.primary)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text("AxPlayground")
                    .font(AXTypography.headlineSmall)
                    .foregroundColor(Color.axTextPrimary)
                
                Text("AI Assistant")
                    .font(AXTypography.labelSmall)
                    .foregroundColor(Color.axTextTertiary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: AXSpacing.xs) {
                Circle()
                    .fill(automationService.isEnabled ? Color.axSuccess : Color.axTextTertiary)
                    .frame(width: 6, height: 6)
                    .shadow(color: automationService.isEnabled ? .axSuccess.opacity(0.6) : .clear, radius: 4)
                
                Text(automationService.isEnabled ? "Active" : "Idle")
                    .font(AXTypography.labelSmall)
                    .foregroundColor(Color.axTextSecondary)
            }
            .padding(.horizontal, AXSpacing.sm)
            .padding(.vertical, AXSpacing.xs)
            .background(
                Capsule()
                    .fill(Color.axSurfaceElevated)
            )
        }
        .padding(AXSpacing.lg)
    }
    
    // MARK: - Quick Status
    
    private var quickStatusSection: some View {
        HStack(spacing: AXSpacing.sm) {
            StatusPill(
                icon: accessibilityMonitor.isMonitoring ? "eye.fill" : "eye.slash",
                label: "Monitor",
                isActive: accessibilityMonitor.isMonitoring
            )
            
            StatusPill(
                icon: notificationObserver.isObserving ? "bell.fill" : "bell.slash",
                label: "Alerts",
                isActive: notificationObserver.isObserving
            )
            
            StatusPill(
                icon: screenTextMonitor.isMonitoring ? "doc.text.fill" : "doc.text",
                label: "OCR",
                isActive: screenTextMonitor.isMonitoring
            )
        }
    }
    
    // MARK: - Monitoring Section
    
    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.sm) {
            SectionHeader(title: "MONITORING")
            
            VStack(spacing: 2) {
                MenuToggleRow(
                    title: "Accessibility Monitor",
                    icon: "eye.fill",
                    isOn: accessibilityMonitor.isMonitoring,
                    onToggle: {
                        if accessibilityMonitor.isMonitoring {
                            accessibilityMonitor.stopMonitoring()
                        } else {
                            accessibilityMonitor.startMonitoring()
                        }
                    }
                )
                
                MenuToggleRow(
                    title: "Notification Observer",
                    icon: "bell.fill",
                    isOn: notificationObserver.isObserving,
                    onToggle: {
                        if notificationObserver.isObserving {
                            notificationObserver.stopObserving()
                        } else {
                            notificationObserver.startObserving()
                        }
                    }
                )
                
                MenuToggleRow(
                    title: "Screen Text (OCR)",
                    icon: "doc.text.viewfinder",
                    isOn: screenTextMonitor.isMonitoring,
                    onToggle: {
                        if screenTextMonitor.isMonitoring {
                            screenTextMonitor.stopMonitoring()
                        } else {
                            screenTextMonitor.startMonitoring { change in
                                print("📝 Text change: \(change.changeType) in \(change.appName)")
                            }
                        }
                    }
                )
                
                MenuToggleRow(
                    title: "Activity Logger",
                    icon: "list.bullet.rectangle",
                    isOn: activityLogger.isLogging,
                    onToggle: {
                        if activityLogger.isLogging {
                            activityLogger.stopLogging()
                        } else {
                            activityLogger.startLogging()
                            if !actionMonitor.isMonitoring {
                                actionMonitor.startMonitoring { action in
                                    ScreenActivityLogger.shared.logUserAction(action)
                                }
                            }
                        }
                    }
                )
            }
            .axCard()
        }
    }
    
    // MARK: - AI Section
    
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.sm) {
            SectionHeader(title: "AI ASSISTANT")
            
            VStack(spacing: AXSpacing.sm) {
                // AI Toggle with special styling
                HStack {
                    HStack(spacing: AXSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(automationService.isEnabled ? Color.axPrimary.opacity(0.2) : Color.axSurfaceElevated)
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16))
                                .foregroundColor(automationService.isEnabled ? Color.axPrimary : Color.axTextTertiary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Suggestions")
                                .font(AXTypography.bodyMedium)
                                .foregroundColor(Color.axTextPrimary)
                            
                            Text(automationService.isEnabled ? "Analyzing actions" : "Disabled")
                                .font(AXTypography.labelSmall)
                                .foregroundColor(Color.axTextTertiary)
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { automationService.isEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    let isReady = await automationService.isReady
                                    if !isReady {
                                        if let envKey = EnvManager.shared[.anthropicKey] {
                                            await automationService.configureAPIKey(envKey)
                                        }
                                    }
                                    automationService.setEnabled(true)
                                } else {
                                    automationService.setEnabled(false)
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(.axPrimary)
                }
                .padding(AXSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AXRadius.md)
                        .fill(Color.axSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AXRadius.md)
                                .stroke(automationService.isEnabled ? Color.axPrimary.opacity(0.3) : Color.axBorder, lineWidth: 1)
                        )
                )
                
                if automationService.isEnabled {
                    Text(automationService.statistics)
                        .font(AXTypography.monoSmall)
                        .foregroundColor(Color.axTextTertiary)
                        .padding(.horizontal, AXSpacing.sm)
                }
            }
        }
    }
    
    // MARK: - Task Queue Section
    
    private let maxVisibleTasks = 3
    
    private var taskQueueSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.sm) {
            HStack {
                SectionHeader(title: "TASK QUEUE")
                
                Spacer()
                
                Text("\(taskItems.count)")
                    .font(AXTypography.mono)
                    .foregroundColor(Color.axTextTertiary)
                    .padding(.horizontal, AXSpacing.sm)
                    .padding(.vertical, AXSpacing.xxs)
                    .background(
                        Capsule()
                            .fill(Color.axSurfaceElevated)
                    )
            }
            
            VStack(spacing: 2) {
                ForEach(Array($taskItems.prefix(maxVisibleTasks))) { $item in
                    TaskRowCompact(
                        item: $item,
                        onRun: { runTask(item) },
                        onDelete: { deleteTask(item) }
                    )
                }
                
                if taskItems.count > maxVisibleTasks {
                    Button {
                        TaskQueueWindowController.shared.show(taskItems: $taskItems)
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                            Text("Show \(taskItems.count - maxVisibleTasks) more")
                                .font(AXTypography.labelMedium)
                        }
                        .foregroundColor(Color.axTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AXSpacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
            .axCard()
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.sm) {
            SectionHeader(title: "QUICK ACTIONS")
            
            VStack(spacing: 2) {
                MenuActionRow(title: "Test Email", icon: "envelope.fill", accent: true) {
                    Task { await testEmailWithFullContext() }
                }
                
                MenuActionRow(title: "View Context Stats", icon: "cylinder.fill") {
                    Task { await showContextStats() }
                }
                
                MenuActionRow(title: "Open Dashboard", icon: "macwindow") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .axCard()
        }
    }
    
    // MARK: - Footer
    
    private var menuFooter: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: AXSpacing.xs) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                    Text("Quit")
                        .font(AXTypography.labelMedium)
                }
                .foregroundColor(Color.axTextSecondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("v1.0")
                .font(AXTypography.labelSmall)
                .foregroundColor(Color.axTextTertiary)
        }
        .padding(AXSpacing.md)
    }
    
    // MARK: - Actions
    
    private func runTask(_ item: TaskItem) {
        guard let index = taskItems.firstIndex(where: { $0.id == item.id }) else { return }
        taskItems[index].status = .inProgress
    }

    private func deleteTask(_ item: TaskItem) {
        taskItems.removeAll { $0.id == item.id }
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
    
    private func testEmailWithFullContext() async {
        print("🧪 Testing email composition...")
        
        let testIntent = "napisz email do Kamila o projekcie"
        
        if let draft = await EmailDraftComposer.shared.composeEmailDraft(
            intent: testIntent,
            recentEvents: [],
            systemState: SystemState(activeApp: "Slack")
        ) {
            if draft.isActionable {
                MailHelper.compose(
                    to: draft.recipient,
                    subject: draft.emailSubject,
                    body: draft.emailBody
                )
            } else {
                NotificationManager.shared.show(
                    title: "📧 Draft (not actionable)",
                    message: draft.whyNotComposable ?? "Missing info",
                    icon: "envelope.badge.exclamationmark"
                )
            }
        } else {
            NotificationManager.shared.show(
                title: "❌ Test Failed",
                message: "Email composition failed",
                icon: "xmark.circle"
            )
        }
    }
}

// MARK: - Supporting Components

struct StatusPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: AXSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(AXTypography.labelSmall)
        }
        .foregroundColor(isActive ? Color.axTextPrimary : Color.axTextTertiary)
        .padding(.horizontal, AXSpacing.sm)
        .padding(.vertical, AXSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AXRadius.sm)
                .fill(isActive ? Color.axPrimary.opacity(0.15) : Color.axSurfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AXRadius.sm)
                .stroke(isActive ? Color.axPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(AXTypography.labelSmall)
            .foregroundColor(Color.axTextTertiary)
            .tracking(1)
    }
}

struct MenuToggleRow: View {
    let title: String
    let icon: String
    let isOn: Bool
    let onToggle: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AXSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isOn ? Color.axPrimary : Color.axTextTertiary)
                    .frame(width: 20)
                
                Text(title)
                    .font(AXTypography.bodyMedium)
                    .foregroundColor(Color.axTextPrimary)
                
                Spacer()
                
                Circle()
                    .fill(isOn ? Color.axSuccess : Color.axTextTertiary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, AXSpacing.md)
            .padding(.vertical, AXSpacing.sm)
            .background(isHovered ? Color.axSurfaceElevated : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct MenuActionRow: View {
    let title: String
    let icon: String
    var accent: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AXSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(accent ? Color.axPrimary : Color.axTextSecondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(AXTypography.bodyMedium)
                    .foregroundColor(Color.axTextPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color.axTextTertiary)
            }
            .padding(.horizontal, AXSpacing.md)
            .padding(.vertical, AXSpacing.sm)
            .background(isHovered ? Color.axSurfaceElevated : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct TaskRowCompact: View {
    @Binding var item: TaskItem
    let onRun: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: AXSpacing.sm) {
            Circle()
                .fill(item.status.color)
                .frame(width: 6, height: 6)
            
            Text(item.title)
                .font(AXTypography.bodySmall)
                .foregroundColor(Color.axTextPrimary)
                .lineLimit(1)
            
            Spacer()
            
            if isHovered {
                HStack(spacing: AXSpacing.xs) {
                    if item.status == .idle {
                        AXIconButton(icon: "play.fill", action: onRun, size: 22)
                    }
                    AXIconButton(icon: "trash", action: onDelete, size: 22, isDestructive: true)
                }
            }
        }
        .padding(.horizontal, AXSpacing.md)
        .padding(.vertical, AXSpacing.sm)
        .background(isHovered ? Color.axSurfaceElevated : Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// Keep old view for compatibility
struct MenuBarView: View {
    @Binding var taskItems: [TaskItem]
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor
    @ObservedObject var notificationObserver: NotificationCenterObserver
    @ObservedObject var screenTextMonitor: ScreenTextMonitor
    @ObservedObject var actionMonitor: UserActionMonitor
    @ObservedObject var activityLogger: ScreenActivityLogger
    @ObservedObject var automationService: AutomationSuggestionService
    
    var body: some View {
        MenuBarViewNew(
            taskItems: $taskItems,
            accessibilityMonitor: accessibilityMonitor,
            notificationObserver: notificationObserver,
            screenTextMonitor: screenTextMonitor,
            actionMonitor: actionMonitor,
            activityLogger: activityLogger,
            automationService: automationService
        )
    }
}

// Keep old components for compatibility
struct TaskItemRow: View {
    @Binding var item: TaskItem
    let onRun: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        TaskRowCompact(item: $item, onRun: onRun, onDelete: onDelete)
    }
}

struct MenuItemButton: View {
    let title: String
    var systemImage: String? = nil
    var fontWeight: Font.Weight = .regular
    let action: () -> Void
    
    var body: some View {
        MenuActionRow(title: title, icon: systemImage ?? "circle", action: action)
    }
}

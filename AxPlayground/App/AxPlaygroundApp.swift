//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {

    @StateObject private var accessibilityMonitor = AccessibilityMonitor()

    @State private var todoItems: [TodoItem] = [
        TodoItem(title: "Review accessibility events", status: .completed),
        TodoItem(title: "Analyze click patterns", status: .completed),
        TodoItem(title: "Configure monitoring filters", status: .inProgress),
        TodoItem(title: "Debug keyboard shortcuts", status: .inProgress),
        TodoItem(title: "Export captured data", status: .idle),
        TodoItem(title: "Add custom event filters", status: .idle),
        TodoItem(title: "Implement batch processing", status: .idle),
        TodoItem(title: "Create usage report", status: .idle),
        TodoItem(title: "Setup automated alerts", status: .idle)
    ]

    var body: some Scene {
        Window("Dashboard", id: "dashboard") {
            ContentView()
                .environmentObject(accessibilityMonitor)
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            MenuBarView(
                todoItems: $todoItems,
                accessibilityMonitor: accessibilityMonitor
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {

    @Binding var todoItems: [TodoItem]
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monitoringToggle
            Divider()
                .padding(.vertical, 6)
            todoSection
            Divider()
                .padding(.vertical, 6)
            actionButtons
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var monitoringToggle: some View {
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
    }

    private let maxVisibleTasks = 5

    private var visibleItems: [Binding<TodoItem>] {
        Array($todoItems.prefix(maxVisibleTasks))
    }

    private var hasMoreTasks: Bool {
        todoItems.count > maxVisibleTasks
    }

    private var remainingTasksCount: Int {
        todoItems.count - maxVisibleTasks
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODO")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(todoItems.count)")
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
                TodoItemRow(
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
            TaskListWindowController.shared.show(todoItems: $todoItems)
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItemButton(title: "Open Dashboard", systemImage: "macwindow") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuItemButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Actions

    private func runTask(_ item: TodoItem) {
        guard let index = todoItems.firstIndex(where: { $0.id == item.id }) else { return }
        todoItems[index].status = .inProgress
        print("Running task: \(item.title)")
    }

    private func deleteTask(_ item: TodoItem) {
        todoItems.removeAll { $0.id == item.id }
        print("Deleted task: \(item.title)")
    }
}

// MARK: - Todo Item Row

struct TodoItemRow: View {

    @Binding var item: TodoItem
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

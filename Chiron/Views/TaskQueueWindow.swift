//
//  TaskQueueWindow.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//  Redesigned with next-level AI aesthetic.
//

import SwiftUI

// MARK: - Task Queue Window Controller

final class TaskQueueWindowController {

    static let shared = TaskQueueWindowController()

    private var window: NSWindow?
    private var taskItems: Binding<[TaskItem]>?

    private init() {}

    func show(taskItems: Binding<[TaskItem]>) {
        self.taskItems = taskItems

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = TaskQueueWindowContent(taskItems: taskItems)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showExisting() {
        if let taskItems = taskItems {
            show(taskItems: taskItems)
        }
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Task Queue Window Content

struct TaskQueueWindowContent: View {

    @Binding var taskItems: [TaskItem]
    @State private var selectedFilter: TaskFilter = .all
    @State private var searchText = ""

    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case inProgress = "In Progress"
        case queued = "Queued"
        case completed = "Completed"
    }

    private var filteredTasks: [Binding<TaskItem>] {
        $taskItems.filter { item in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .inProgress: matchesFilter = item.wrappedValue.status == .inProgress
            case .queued: matchesFilter = item.wrappedValue.status == .idle
            case .completed: matchesFilter = item.wrappedValue.status == .completed
            }
            
            let matchesSearch = searchText.isEmpty || item.wrappedValue.title.localizedCaseInsensitiveContains(searchText)
            
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        ZStack {
            // Background with gradient
            backgroundView
            
            // Content
            VStack(spacing: 0) {
                headerView
                filterBar
                searchBar
                taskList
                footerView
            }
        }
        .frame(width: 420, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: AXRadius.xxl))
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            // Base color
            Color.axSurface
            
            // Gradient orbs
            Circle()
                .fill(Color.axPrimary.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -100, y: -150)
            
            Circle()
                .fill(Color.axAccent.opacity(0.05))
                .frame(width: 150, height: 150)
                .blur(radius: 50)
                .offset(x: 120, y: 180)
            
            // Border
            RoundedRectangle(cornerRadius: AXRadius.xxl)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.axPrimary.opacity(0.4), location: 0),
                            .init(color: Color.axBorder, location: 0.3),
                            .init(color: Color.axAccent.opacity(0.2), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.axPrimary.opacity(0.1), radius: 40, x: 0, y: 20)
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 15)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: AXSpacing.xxs) {
                Text("Task Queue")
                    .font(AXTypography.displayMedium)
                    .foregroundColor(Color.axTextPrimary)
                
                Text("\(taskItems.count) tasks total")
                    .font(AXTypography.labelMedium)
                    .foregroundColor(Color.axTextTertiary)
            }

            Spacer()

            Button(action: { TaskQueueWindowController.shared.close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.axTextTertiary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.axSurfaceElevated)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AXSpacing.xl)
        .padding(.top, AXSpacing.xl)
        .padding(.bottom, AXSpacing.lg)
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        HStack(spacing: AXSpacing.xs) {
            ForEach(TaskFilter.allCases, id: \.self) { filter in
                FilterChip(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    count: countForFilter(filter)
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                }
            }
        }
        .padding(.horizontal, AXSpacing.xl)
        .padding(.bottom, AXSpacing.md)
    }
    
    private func countForFilter(_ filter: TaskFilter) -> Int {
        switch filter {
        case .all: return taskItems.count
        case .inProgress: return taskItems.filter { $0.status == .inProgress }.count
        case .queued: return taskItems.filter { $0.status == .idle }.count
        case .completed: return taskItems.filter { $0.status == .completed }.count
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: AXSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color.axTextTertiary)
            
            TextField("Search tasks...", text: $searchText)
                .textFieldStyle(.plain)
                .font(AXTypography.bodyMedium)
                .foregroundColor(Color.axTextPrimary)
        }
        .padding(.horizontal, AXSpacing.md)
        .padding(.vertical, AXSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .fill(Color.axSurfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .stroke(Color.axBorder, lineWidth: 1)
        )
        .padding(.horizontal, AXSpacing.xl)
        .padding(.bottom, AXSpacing.md)
    }

    // MARK: - Task List

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: AXSpacing.sm) {
                if filteredTasks.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredTasks) { $item in
                        TaskQueueRowNew(
                            item: $item,
                            onRun: { runTask(item) },
                            onDelete: { deleteTask(item) }
                        )
                    }
                }
            }
            .padding(.horizontal, AXSpacing.xl)
            .padding(.vertical, AXSpacing.md)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: AXSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.axSurfaceElevated)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundColor(Color.axTextTertiary)
            }
            
            Text(searchText.isEmpty ? "No tasks in this category" : "No matching tasks")
                .font(AXTypography.bodyMedium)
                .foregroundColor(Color.axTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AXSpacing.xxxl)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Quick stats
            HStack(spacing: AXSpacing.lg) {
                StatBadge(value: taskItems.filter { $0.status == .inProgress }.count, label: "Active", color: .axWarning)
                StatBadge(value: taskItems.filter { $0.status == .idle }.count, label: "Queued", color: .axTextTertiary)
                StatBadge(value: taskItems.filter { $0.status == .completed }.count, label: "Done", color: .axSuccess)
            }
            
            Spacer()
            
            // Clear completed button
            if taskItems.contains(where: { $0.status == .completed }) {
                Button {
                    withAnimation {
                        taskItems.removeAll { $0.status == .completed }
                    }
                } label: {
                    Text("Clear Completed")
                        .font(AXTypography.labelSmall)
                        .foregroundColor(Color.axTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AXSpacing.lg)
        .background(Color.axSurface.opacity(0.8))
    }

    // MARK: - Actions

    private func runTask(_ item: TaskItem) {
        guard let index = taskItems.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation {
            taskItems[index].status = .inProgress
        }
    }

    private func deleteTask(_ item: TaskItem) {
        withAnimation {
            taskItems.removeAll { $0.id == item.id }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AXSpacing.xs) {
                Text(title)
                    .font(AXTypography.labelSmall)
                
                if count > 0 {
                    Text("\(count)")
                        .font(AXTypography.labelSmall)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .axTextTertiary)
                }
            }
            .foregroundStyle(isSelected ? .white : .axTextSecondary)
            .padding(.horizontal, AXSpacing.md)
            .padding(.vertical, AXSpacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? Color.axPrimary : Color.axSurfaceElevated)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: AXSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text("\(value)")
                .font(AXTypography.mono)
                .foregroundColor(Color.axTextPrimary)
            
            Text(label)
                .font(AXTypography.labelSmall)
                .foregroundColor(Color.axTextTertiary)
        }
    }
}

// MARK: - Task Queue Row (Redesigned)

struct TaskQueueRowNew: View {

    @Binding var item: TaskItem
    let onRun: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AXSpacing.md) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(item.status.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: item.status.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(item.status.color)
            }

            // Task info
            VStack(alignment: .leading, spacing: AXSpacing.xxs) {
                Text(item.title)
                    .font(AXTypography.bodyMedium)
                    .foregroundColor(Color.axTextPrimary)
                    .lineLimit(1)
                
                Text(item.status.displayName)
                    .font(AXTypography.labelSmall)
                    .foregroundColor(Color.axTextTertiary)
            }

            Spacer()

            // Action buttons
            if isHovered {
                HStack(spacing: AXSpacing.xs) {
                    if item.status == .idle {
                        Button(action: onRun) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.axPrimary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.axPrimary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Run now")
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(Color.axError)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.axError.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(AXSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .fill(isHovered ? Color.axSurfaceElevated : Color.axSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .stroke(isHovered ? Color.axBorder : Color.axBorder.opacity(0.5), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - TaskStatus Extension

extension TaskStatus {
    var displayName: String {
        switch self {
        case .idle: return "Queued"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

// Keep old component for compatibility
struct TaskQueueRow: View {
    @Binding var item: TaskItem
    let onRun: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        TaskQueueRowNew(item: $item, onRun: onRun, onDelete: onDelete)
    }
}

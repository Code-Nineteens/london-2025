//
//  TaskListWindow.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

// MARK: - Task List Window Controller

final class TaskListWindowController {

    static let shared = TaskListWindowController()

    private var window: NSWindow?

    private init() {}

    func show(todoItems: Binding<[TodoItem]>) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = TaskListWindowContent(todoItems: todoItems)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
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

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Task List Window Content

struct TaskListWindowContent: View {

    @Binding var todoItems: [TodoItem]

    private var completedTasks: [Binding<TodoItem>] {
        $todoItems.filter { $0.wrappedValue.status == .completed }
    }

    private var inProgressTasks: [Binding<TodoItem>] {
        $todoItems.filter { $0.wrappedValue.status == .inProgress }
    }

    private var idleTasks: [Binding<TodoItem>] {
        $todoItems.filter { $0.wrappedValue.status == .idle }
    }

    var body: some View {
        ZStack {
            glassBackground
            contentView
        }
        .frame(width: 380, height: 500)
    }

    // MARK: - Background

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.2),
                                Color.clear,
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
                .padding(.horizontal, 16)
            taskListView
        }
        .padding(.vertical, 16)
    }

    private var headerView: some View {
        HStack {
            Text("All Tasks")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Text("\(todoItems.count) tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: { TaskListWindowController.shared.close() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var taskListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !inProgressTasks.isEmpty {
                    taskSection(title: "In Progress", icon: "circle.dotted", color: .yellow, tasks: inProgressTasks)
                }

                if !idleTasks.isEmpty {
                    taskSection(title: "Idle", icon: "circle", color: .gray, tasks: idleTasks)
                }

                if !completedTasks.isEmpty {
                    taskSection(title: "Completed", icon: "checkmark.circle.fill", color: .green, tasks: completedTasks)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func taskSection(title: String, icon: String, color: Color, tasks: [Binding<TodoItem>]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                ForEach(tasks) { $item in
                    TaskListRow(
                        item: $item,
                        onRun: { runTask(item) },
                        onDelete: { deleteTask(item) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func runTask(_ item: TodoItem) {
        guard let index = todoItems.firstIndex(where: { $0.id == item.id }) else { return }
        todoItems[index].status = .inProgress
    }

    private func deleteTask(_ item: TodoItem) {
        todoItems.removeAll { $0.id == item.id }
    }
}

// MARK: - Task List Row

struct TaskListRow: View {

    @Binding var item: TodoItem
    let onRun: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.status.iconName)
                .font(.system(size: 14))
                .foregroundStyle(item.status.color)
                .frame(width: 16)

            Text(item.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if isHovered {
                HStack(spacing: 6) {
                    if item.status == .idle {
                        Button(action: onRun) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Run now")
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

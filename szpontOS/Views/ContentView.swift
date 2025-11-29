//
//  ContentView.swift
//  szpontOS
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

// MARK: - Main Content View

/// The main view displaying accessibility monitoring controls and event list.
struct ContentView: View {

    // MARK: - Properties

    @EnvironmentObject var monitor: AccessibilityMonitor
    @State private var selectedApp: String?
    
    // MARK: - Computed Properties
    
    private var filteredEvents: [AccessibilityEvent] {
        guard let app = selectedApp else {
            return monitor.events
        }
        return monitor.events.filter { $0.appName == app }
    }
    
    private var groupedEvents: [(String, [AccessibilityEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.appName }
        return grouped.sorted { $0.key < $1.key }
    }
    
    // MARK: - Body
    
    var body: some View {
        HSplitView {
            controlPanel
            eventsPanel
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            startPermissionCheckTimer()
        }
    }
    
    // MARK: - Private Views
    
    private var controlPanel: some View {
        VStack(spacing: 20) {
            monitorStatusIcon
            titleSection
            permissionStatus
            
            if !monitor.hasPermission {
                grantPermissionButton
            }
            
            controlButtons
            clearEventsButton
            
            Divider()
            
            appFilterSection
            
            Spacer()
            
            eventCountLabel
        }
        .padding(20)
        .frame(width: 220)
    }
    
    private var monitorStatusIcon: some View {
        Image(systemName: monitor.isMonitoring ? "eye.fill" : "eye.slash.fill")
            .imageScale(.large)
            .foregroundStyle(monitor.isMonitoring ? .green : .gray)
            .font(.system(size: 48))
    }
    
    private var titleSection: some View {
        Text("Accessibility Monitor")
            .font(.title2)
            .fontWeight(.bold)
    }
    
    private var permissionStatus: some View {
        HStack {
            Image(systemName: monitor.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(monitor.hasPermission ? .green : .orange)
            Text(monitor.hasPermission ? "Permission granted" : "Permission required")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(monitor.hasPermission ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var grantPermissionButton: some View {
        Button(action: handleGrantPermission) {
            Label("Grant Permission", systemImage: "lock.open.fill")
                .frame(width: 160)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }
    
    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button(action: handleStartMonitoring) {
                Label("Start", systemImage: "play.fill")
                    .frame(width: 80)
            }
            .disabled(monitor.isMonitoring || !monitor.hasPermission)

            Button(action: handleStopMonitoring) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(width: 80)
            }
            .disabled(!monitor.isMonitoring)
        }
        .buttonStyle(.borderedProminent)
    }
    
    private var clearEventsButton: some View {
        Button(action: handleClearEvents) {
            Label("Clear Events", systemImage: "trash")
                .frame(width: 160)
        }
        .buttonStyle(.bordered)
        .disabled(monitor.events.isEmpty)
    }
    
    private var appFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter by App")
                .font(.headline)
            
            Picker("App", selection: $selectedApp) {
                Text("All Apps").tag(nil as String?)
                ForEach(monitor.uniqueAppNames, id: \.self) { app in
                    Text(app).tag(app as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }
    
    private var eventCountLabel: some View {
        Text("\(monitor.events.count) events captured")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    private var eventsPanel: some View {
        VStack(spacing: 0) {
            eventsHeader
            Divider()
            eventsContent
        }
        .frame(minWidth: 400)
    }
    
    private var eventsHeader: some View {
        HStack {
            Text("Events")
                .font(.headline)
            Spacer()
            if let app = selectedApp {
                Text("Showing: \(app)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var eventsContent: some View {
        if filteredEvents.isEmpty {
            emptyStateView
        } else {
            eventsList
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(monitor.events.isEmpty ? "No events yet" : "No events for selected app")
                .foregroundStyle(.secondary)
            if monitor.events.isEmpty {
                Text("Start monitoring and click anywhere")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var eventsList: some View {
        List {
            ForEach(groupedEvents, id: \.0) { appName, events in
                Section(header: AppSectionHeader(appName: appName, count: events.count)) {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
    
    // MARK: - Private Methods
    
    private func handleGrantPermission() {
        monitor.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            monitor.checkPermission()
        }
    }
    
    private func handleStartMonitoring() {
        monitor.startMonitoring()
    }

    private func handleStopMonitoring() {
        monitor.stopMonitoring()
    }
    
    private func handleClearEvents() {
        monitor.clearEvents()
        selectedApp = nil
    }
    
    private func startPermissionCheckTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            monitor.checkPermission()
        }
    }
}

// MARK: - App Section Header

/// Header view for grouped events by application.
struct AppSectionHeader: View {
    
    // MARK: - Properties
    
    let appName: String
    let count: Int
    
    // MARK: - Body
    
    var body: some View {
        HStack {
            Text(appName)
                .fontWeight(.semibold)
            Spacer()
            countBadge
        }
    }
    
    // MARK: - Private Views
    
    private var countBadge: some View {
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
    }
}

// MARK: - Event Row

/// Row view displaying a single accessibility event.
struct EventRow: View {
    
    // MARK: - Properties
    
    let event: AccessibilityEvent
    
    // MARK: - Computed Properties
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: event.timestamp)
    }
    
    private var hasTitle: Bool {
        guard let title = event.title else { return false }
        return !title.isEmpty
    }
    
    private var hasRoleDescription: Bool {
        guard let roleDesc = event.roleDescription else { return false }
        return !roleDesc.isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            
            if hasTitle {
                titleLabel
            }
            
            if hasRoleDescription {
                roleDescriptionLabel
            }
            
            metadataRow
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Private Views
    
    private var headerRow: some View {
        HStack {
            Text(event.role ?? "Unknown")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            Spacer()
            Text(timeString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var titleLabel: some View {
        Text("Title: \(event.title ?? "")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    private var roleDescriptionLabel: some View {
        Text(event.roleDescription ?? "")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    
    private var metadataRow: some View {
        HStack {
            Text("Click: (\(Int(event.clickLocation.x)), \(Int(event.clickLocation.y)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            if let size = event.size {
                Text("Size: \(Int(size.width))x\(Int(size.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AccessibilityMonitor())
}

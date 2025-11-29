//
//  ContentView.swift
//  AxPlayground
//
//  Created by Piotr Pasztor on 29/11/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = AccessibilityMonitor()
    @State private var isMonitoring = false
    @State private var selectedApp: String? = nil

    var filteredEvents: [AccessibilityEvent] {
        if let app = selectedApp {
            return monitor.events.filter { $0.appName == app }
        }
        return monitor.events
    }

    var groupedEvents: [(String, [AccessibilityEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.appName }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        HSplitView {
            // Left panel - Controls
            VStack(spacing: 20) {
                Image(systemName: isMonitoring ? "eye.fill" : "eye.slash.fill")
                    .imageScale(.large)
                    .foregroundStyle(isMonitoring ? .green : .gray)
                    .font(.system(size: 48))

                Text("Accessibility Monitor")
                    .font(.title2)
                    .fontWeight(.bold)

                // Permission status
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

                if !monitor.hasPermission {
                    Button(action: {
                        monitor.requestPermission()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            monitor.checkPermission()
                        }
                    }) {
                        Label("Grant Permission", systemImage: "lock.open.fill")
                            .frame(width: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                HStack(spacing: 10) {
                    Button(action: {
                        monitor.startMonitoring()
                        isMonitoring = true
                    }) {
                        Label("Start", systemImage: "play.fill")
                            .frame(width: 80)
                    }
                    .disabled(isMonitoring || !monitor.hasPermission)

                    Button(action: {
                        monitor.stopMonitoring()
                        isMonitoring = false
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(width: 80)
                    }
                    .disabled(!isMonitoring)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    monitor.clearEvents()
                    selectedApp = nil
                }) {
                    Label("Clear Events", systemImage: "trash")
                        .frame(width: 160)
                }
                .buttonStyle(.bordered)
                .disabled(monitor.events.isEmpty)

                Divider()

                // App filter
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

                Spacer()

                Text("\(monitor.events.count) events captured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 220)

            // Right panel - Events list
            VStack(spacing: 0) {
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

                Divider()

                if filteredEvents.isEmpty {
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
                } else {
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
            }
            .frame(minWidth: 400)
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                monitor.checkPermission()
            }
        }
    }
}

struct AppSectionHeader: View {
    let appName: String
    let count: Int

    var body: some View {
        HStack {
            Text(appName)
                .fontWeight(.semibold)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
    }
}

struct EventRow: View {
    let event: AccessibilityEvent

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.role ?? "Unknown")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let title = event.title, !title.isEmpty {
                Text("Title: \(title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let roleDesc = event.roleDescription, !roleDesc.isEmpty {
                Text(roleDesc)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

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
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}

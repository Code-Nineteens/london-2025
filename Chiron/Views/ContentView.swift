//
//  ContentView.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//  Redesigned for next-level AI app aesthetic.
//

import SwiftUI

// MARK: - Main Content View

/// The main dashboard view with modern, dark aesthetic.
struct ContentView: View {

    // MARK: - Properties

    @EnvironmentObject var monitor: AccessibilityMonitor
    @State private var selectedApp: String?
    @State private var showingSettings = false
    
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
        ZStack {
            // Background
            backgroundGradient
            
            HSplitView {
                sidebarPanel
                mainContentPanel
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            startPermissionCheckTimer()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        ZStack {
            Color.axBackground
            
            // Subtle gradient orbs
            Circle()
                .fill(Color.axPrimary.opacity(0.08))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: -200, y: -150)
            
            Circle()
                .fill(Color.axAccent.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 250, y: 200)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Sidebar Panel
    
    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // Logo/Brand Section
            brandHeader
            
            Divider()
                .background(Color.axBorder)
                .padding(.horizontal, AXSpacing.lg)
            
            // Status Section
            statusSection
                .padding(.top, AXSpacing.xl)
            
            // Controls Section
            controlsSection
                .padding(.top, AXSpacing.xl)
            
            Spacer()
            
            // Filter Section
            filterSection
            
            Spacer()
            
            // Stats Footer
            statsFooter
        }
        .padding(.vertical, AXSpacing.xl)
        .frame(width: 260)
        .background(Color.axSurface.opacity(0.5))
    }
    
    private var brandHeader: some View {
        HStack(spacing: AXSpacing.md) {
            // Animated logo icon
            ZStack {
                Circle()
                    .fill(AXGradients.primary)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .axPulsingGlow()
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ChironaAI")
                    .font(AXTypography.headlineMedium)
                    .foregroundColor(Color.axTextPrimary)
                
                Text("AI Assistant")
                    .font(AXTypography.labelSmall)
                    .foregroundColor(Color.axTextTertiary)
            }
            
            Spacer()
        }
        .padding(.horizontal, AXSpacing.xl)
        .padding(.bottom, AXSpacing.lg)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.md) {
            Text("STATUS")
                .font(AXTypography.labelSmall)
                .foregroundColor(Color.axTextTertiary)
                .tracking(1.2)
            
            // Monitoring Status Card
            HStack(spacing: AXSpacing.md) {
                ZStack {
                    Circle()
                        .fill(monitor.isMonitoring ? Color.axSuccess.opacity(0.15) : Color.axSurfaceElevated)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: monitor.isMonitoring ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(monitor.isMonitoring ? Color.axSuccess : Color.axTextTertiary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.isMonitoring ? "Active" : "Paused")
                        .font(AXTypography.headlineSmall)
                        .foregroundColor(Color.axTextPrimary)
                    
                    Text("Accessibility Monitor")
                        .font(AXTypography.labelSmall)
                        .foregroundColor(Color.axTextTertiary)
                }
                
                Spacer()
                
                Circle()
                    .fill(monitor.isMonitoring ? Color.axSuccess : Color.axTextTertiary)
                    .frame(width: 8, height: 8)
                    .shadow(color: monitor.isMonitoring ? .axSuccess.opacity(0.6) : .clear, radius: 6)
            }
            .padding(AXSpacing.md)
            .axCard(elevated: true)
            
            // Permission Status
            HStack(spacing: AXSpacing.sm) {
                Image(systemName: monitor.hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundColor(monitor.hasPermission ? Color.axSuccess : Color.axWarning)
                
                Text(monitor.hasPermission ? "Permissions granted" : "Permissions required")
                    .font(AXTypography.labelMedium)
                    .foregroundColor(Color.axTextSecondary)
                
                Spacer()
            }
            .padding(.horizontal, AXSpacing.sm)
            
            if !monitor.hasPermission {
                Button(action: handleGrantPermission) {
                    HStack(spacing: AXSpacing.sm) {
                        Image(systemName: "lock.open.fill")
                        Text("Grant Permission")
                    }
                }
                .axPrimaryButton(compact: true)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AXSpacing.xl)
    }
    
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.md) {
            Text("CONTROLS")
                .font(AXTypography.labelSmall)
                .foregroundColor(Color.axTextTertiary)
                .tracking(1.2)
            
            HStack(spacing: AXSpacing.sm) {
                // Start Button
                Button(action: handleStartMonitoring) {
                    HStack(spacing: AXSpacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Start")
                    }
                }
                .axPrimaryButton(compact: true)
                .buttonStyle(.plain)
                .disabled(monitor.isMonitoring || !monitor.hasPermission)
                .opacity(monitor.isMonitoring || !monitor.hasPermission ? 0.5 : 1)
                
                // Stop Button
                Button(action: handleStopMonitoring) {
                    HStack(spacing: AXSpacing.xs) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                        Text("Stop")
                    }
                }
                .axSecondaryButton(compact: true)
                .buttonStyle(.plain)
                .disabled(!monitor.isMonitoring)
                .opacity(!monitor.isMonitoring ? 0.5 : 1)
            }
            
            // Clear Events Button
            Button(action: handleClearEvents) {
                HStack(spacing: AXSpacing.sm) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("Clear Events")
                }
            }
            .axGhostButton()
            .buttonStyle(.plain)
            .disabled(monitor.events.isEmpty)
            .opacity(monitor.events.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, AXSpacing.xl)
    }
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: AXSpacing.md) {
            Text("FILTER")
                .font(AXTypography.labelSmall)
                .foregroundColor(Color.axTextTertiary)
                .tracking(1.2)
            
            Menu {
                Button("All Apps") {
                    selectedApp = nil
                }
                
                Divider()
                
                ForEach(monitor.uniqueAppNames, id: \.self) { app in
                    Button(app) {
                        selectedApp = app
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14))
                        .foregroundColor(Color.axTextSecondary)
                    
                    Text(selectedApp ?? "All Apps")
                        .font(AXTypography.bodyMedium)
                        .foregroundColor(Color.axTextPrimary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Color.axTextTertiary)
                }
                .padding(AXSpacing.md)
                .axCard(elevated: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AXSpacing.xl)
    }
    
    private var statsFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(monitor.events.count)")
                    .font(AXTypography.displayMedium)
                    .foregroundColor(Color.axTextPrimary)
                
                Text("events captured")
                    .font(AXTypography.labelSmall)
                    .foregroundColor(Color.axTextTertiary)
            }
            
            Spacer()
            
            // Mini chart placeholder
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.axPrimary.opacity(Double(i + 3) / 10))
                        .frame(width: 4, height: CGFloat(8 + i * 3))
                }
            }
        }
        .padding(AXSpacing.lg)
        .axCard()
        .padding(.horizontal, AXSpacing.xl)
    }
    
    // MARK: - Main Content Panel
    
    private var mainContentPanel: some View {
        VStack(spacing: 0) {
            // Header
            mainContentHeader
            
            // Content
            if filteredEvents.isEmpty {
                emptyStateView
            } else {
                eventsList
            }
        }
        .frame(minWidth: 500)
    }
    
    private var mainContentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Event Stream")
                    .font(AXTypography.headlineLarge)
                    .foregroundColor(Color.axTextPrimary)
                
                if let app = selectedApp {
                    HStack(spacing: AXSpacing.xs) {
                        Text("Filtered by:")
                            .font(AXTypography.labelSmall)
                            .foregroundColor(Color.axTextTertiary)
                        
                        Text(app)
                            .font(AXTypography.labelSmall)
                            .foregroundColor(Color.axPrimary)
                            .padding(.horizontal, AXSpacing.sm)
                            .padding(.vertical, AXSpacing.xxs)
                            .background(
                                Capsule()
                                    .fill(Color.axPrimary.opacity(0.15))
                            )
                    }
                }
            }
            
            Spacer()
            
            // Live indicator
            if monitor.isMonitoring {
                HStack(spacing: AXSpacing.xs) {
                    Circle()
                        .fill(Color.axError)
                        .frame(width: 6, height: 6)
                        .shadow(color: .axError.opacity(0.6), radius: 4)
                    
                    Text("LIVE")
                        .font(AXTypography.labelSmall)
                        .foregroundColor(Color.axTextSecondary)
                        .tracking(1)
                }
                .padding(.horizontal, AXSpacing.md)
                .padding(.vertical, AXSpacing.xs)
                .background(
                    Capsule()
                        .fill(Color.axError.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, AXSpacing.xl)
        .padding(.vertical, AXSpacing.lg)
        .background(Color.axSurface.opacity(0.3))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AXSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.axSurfaceElevated)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 32))
                    .foregroundColor(Color.axTextTertiary)
            }
            
            VStack(spacing: AXSpacing.sm) {
                Text(monitor.events.isEmpty ? "No events yet" : "No events for selected app")
                    .font(AXTypography.headlineMedium)
                    .foregroundColor(Color.axTextSecondary)
                
                if monitor.events.isEmpty {
                    Text("Start monitoring and interact with any app")
                        .font(AXTypography.bodySmall)
                        .foregroundColor(Color.axTextTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: AXSpacing.md, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedEvents, id: \.0) { appName, events in
                    Section {
                        ForEach(events) { event in
                            EventRowNew(event: event)
                        }
                    } header: {
                        AppSectionHeaderNew(appName: appName, count: events.count)
                    }
                }
            }
            .padding(AXSpacing.xl)
        }
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

// MARK: - App Section Header (Redesigned)

struct AppSectionHeaderNew: View {
    let appName: String
    let count: Int
    
    var body: some View {
        HStack {
            HStack(spacing: AXSpacing.sm) {
                // App icon placeholder
                RoundedRectangle(cornerRadius: AXRadius.sm)
                    .fill(Color.axPrimary.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(appName.prefix(1)))
                            .font(AXTypography.labelSmall)
                            .foregroundColor(Color.axPrimary)
                    )
                
                Text(appName)
                    .font(AXTypography.headlineSmall)
                    .foregroundColor(Color.axTextPrimary)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(AXTypography.mono)
                .foregroundColor(Color.axTextTertiary)
                .padding(.horizontal, AXSpacing.sm)
                .padding(.vertical, AXSpacing.xxs)
                .background(
                    Capsule()
                        .fill(Color.axSurfaceElevated)
                )
        }
        .padding(.vertical, AXSpacing.sm)
        .padding(.horizontal, AXSpacing.md)
        .background(Color.axBackground.opacity(0.9))
    }
}

// MARK: - Event Row (Redesigned)

struct EventRowNew: View {
    let event: AccessibilityEvent
    @State private var isHovered = false
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: event.timestamp)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AXSpacing.md) {
            // Event type indicator
            VStack {
                Circle()
                    .fill(Color.axPrimary.opacity(0.2))
                    .frame(width: 8, height: 8)
                
                Rectangle()
                    .fill(Color.axBorder)
                    .frame(width: 1)
            }
            .frame(width: 8)
            
            // Event content
            VStack(alignment: .leading, spacing: AXSpacing.sm) {
                HStack {
                    Text(event.role ?? "Unknown")
                        .font(AXTypography.mono)
                        .foregroundColor(Color.axPrimary)
                        .padding(.horizontal, AXSpacing.sm)
                        .padding(.vertical, AXSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: AXRadius.xs)
                                .fill(Color.axPrimary.opacity(0.1))
                        )
                    
                    Spacer()
                    
                    Text(timeString)
                        .font(AXTypography.monoSmall)
                        .foregroundColor(Color.axTextTertiary)
                }
                
                if let title = event.title, !title.isEmpty {
                    Text(title)
                        .font(AXTypography.bodyMedium)
                        .foregroundColor(Color.axTextSecondary)
                        .lineLimit(2)
                }
                
                // Metadata row
                HStack(spacing: AXSpacing.md) {
                    Label("(\(Int(event.clickLocation.x)), \(Int(event.clickLocation.y)))", systemImage: "cursorarrow.click")
                        .font(AXTypography.labelSmall)
                        .foregroundColor(Color.axTextTertiary)
                    
                    if let size = event.size {
                        Label("\(Int(size.width))×\(Int(size.height))", systemImage: "rectangle.dashed")
                            .font(AXTypography.labelSmall)
                            .foregroundColor(Color.axTextTertiary)
                    }
                }
            }
        }
        .padding(AXSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .fill(isHovered ? Color.axSurfaceElevated : Color.axSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AXRadius.md)
                .stroke(Color.axBorder.opacity(isHovered ? 1 : 0.5), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AccessibilityMonitor())
}

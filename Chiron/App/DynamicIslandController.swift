//
//  DynamicIslandController.swift
//  Chiron
//
//  Shows an idle notch bar that expands into Dynamic Island menu
//

import SwiftUI
import AppKit
import Combine

// MARK: - Dynamic Island Controller

@MainActor
final class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    @Published var hasActivity = false
    @Published var activityIcon: String = "sparkles"
    @Published var activityColor: Color = .purple
    @Published var isExpanded = false
    @Published var isVisible = true

    private var islandWindow: IslandWindow?

    // Window dimensions (needs to fit expanded state)
    private let windowWidth: CGFloat = IslandDimensions.expandedWidth + (IslandDimensions.expandedInvertedRadius * 2) + 20
    private let windowHeight: CGFloat = IslandDimensions.expandedHeight + 20

    // Menu content provider
    var menuContentProvider: (() -> AnyView)?

    private init() {}

    // MARK: - Public API

    func show() {
        guard islandWindow == nil else { return }
        createIslandWindow()
    }

    func hide() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        islandWindow?.orderOut(nil)
        islandWindow = nil
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func expand() {
        guard !isExpanded else { return }
        // Expand window frame FIRST, before triggering animation
        updateWindowFrame(expanded: true)
        // Small delay to let window resize complete before animation
        DispatchQueue.main.async { [weak self] in
            self?.isExpanded = true
            self?.isVisible = true
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isVisible = false

        // Wait for animation then reset state and resize window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isExpanded = false
            self?.updateWindowFrame(expanded: false)
        }
    }

    private func updateWindowFrame(expanded: Bool) {
        guard let window = islandWindow, let screen = NSScreen.main else { return }

        let width: CGFloat
        let height: CGFloat

        if expanded {
            width = windowWidth
            height = windowHeight
        } else {
            // Just enough for the idle notch
            let idleTotalWidth = IslandDimensions.idleWidth + (IslandDimensions.idleInvertedRadius * 2) + 20
            width = idleTotalWidth
            height = IslandDimensions.idleHeight + 10
        }

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true, animate: false)
        window.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    // MARK: - Activity

    func setActivity(icon: String = "sparkles", color: Color = .purple) {
        self.activityIcon = icon
        self.activityColor = color
        self.hasActivity = true
    }

    func clearActivity() {
        self.hasActivity = false
    }

    // MARK: - Private - Unified Island Window

    private func createIslandWindow() {
        guard let screen = NSScreen.main else { return }

        // Start with idle size - only covers the notch area
        let idleTotalWidth = IslandDimensions.idleWidth + (IslandDimensions.idleInvertedRadius * 2) + 20
        let idleWindowHeight = IslandDimensions.idleHeight + 10

        // Position at top center, flush to top of screen
        let frame = NSRect(
            x: screen.frame.midX - idleTotalWidth / 2,
            y: screen.frame.maxY - idleWindowHeight,
            width: idleTotalWidth,
            height: idleWindowHeight
        )

        let window = IslandWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.controller = self

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        let contentView = UnifiedIslandView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: idleTotalWidth, height: idleWindowHeight)
        window.contentView = hostingView

        window.orderFrontRegardless()
        islandWindow = window

        setupClickOutsideMonitor()
    }

    // MARK: - Private - Click Outside Monitor

    private var clickMonitor: Any?

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isExpanded, let window = self.islandWindow else { return }

            let clickLocation = NSEvent.mouseLocation
            if !window.frame.contains(clickLocation) {
                Task { @MainActor in
                    self.collapse()
                }
            }
        }
    }
}

// MARK: - Custom Window for Click-Through

class IslandWindow: NSPanel {
    weak var controller: DynamicIslandController?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool {
        return controller?.isExpanded ?? false
    }

    override var canBecomeMain: Bool {
        return false
    }
}


// MARK: - Shared Island Dimensions

enum IslandDimensions {
    // Idle/Collapsed state (wider than MacBook notch)
    static let idleWidth: CGFloat = 360
    static let idleHeight: CGFloat = 38
    static let idleCornerRadius: CGFloat = 14
    static let idleInvertedRadius: CGFloat = 14

    // Expanded state
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 400
    static let expandedCornerRadius: CGFloat = 24
    static let expandedInvertedRadius: CGFloat = 24

    // Orb
    static let orbSize: CGFloat = 20
}

// MARK: - Unified Dynamic Island View (Idle + Expanded)

struct UnifiedIslandView: View {
    @ObservedObject var controller: DynamicIslandController
    @State private var animationProgress: CGFloat = 0.0
    @State private var contentOpacity: CGFloat = 0.0

    private var currentWidth: CGFloat {
        IslandDimensions.idleWidth + (IslandDimensions.expandedWidth - IslandDimensions.idleWidth) * animationProgress
    }

    private var currentHeight: CGFloat {
        IslandDimensions.idleHeight + (IslandDimensions.expandedHeight - IslandDimensions.idleHeight) * animationProgress
    }

    private var currentCornerRadius: CGFloat {
        IslandDimensions.idleCornerRadius + (IslandDimensions.expandedCornerRadius - IslandDimensions.idleCornerRadius) * animationProgress
    }

    private var currentInvertedRadius: CGFloat {
        IslandDimensions.idleInvertedRadius + (IslandDimensions.expandedInvertedRadius - IslandDimensions.idleInvertedRadius) * animationProgress
    }

    private var orbOpacity: CGFloat {
        1.0 - animationProgress
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Black background with inverted top corners
            DynamicIslandShape(
                bottomCornerRadius: currentCornerRadius,
                topInvertedRadius: currentInvertedRadius
            )
            .fill(Color.black)
            .frame(width: currentWidth + (currentInvertedRadius * 2), height: currentHeight)
            .contentShape(
                DynamicIslandShape(
                    bottomCornerRadius: currentCornerRadius,
                    topInvertedRadius: currentInvertedRadius
                )
            )
            .onTapGesture {
                if !controller.isExpanded {
                    controller.expand()
                }
            }

            // Idle state: Orb on the right
            if animationProgress < 1.0 {
                HStack {
                    Spacer()
                    SiriOrbCompact(size: IslandDimensions.orbSize, isActive: controller.hasActivity)
                        .frame(width: IslandDimensions.orbSize * 2, height: IslandDimensions.orbSize * 2)
                }
                .padding(.trailing, currentInvertedRadius + 6)
                .frame(width: currentWidth + (currentInvertedRadius * 2), height: IslandDimensions.idleHeight)
                .opacity(orbOpacity)
                .allowsHitTesting(false)
            }

            // Expanded state: Menu content
            if animationProgress > 0 {
                menuContent
                    .frame(width: IslandDimensions.expandedWidth, height: IslandDimensions.expandedHeight)
                    .opacity(contentOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: controller.isExpanded) { _, expanded in
            if expanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    animationProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        contentOpacity = 1.0
                    }
                }
            }
        }
        .onChange(of: controller.isVisible) { _, visible in
            if !visible {
                withAnimation(.easeIn(duration: 0.1)) {
                    contentOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        animationProgress = 0.0
                    }
                }
            }
        }
    }

    // MARK: - Menu Content

    private var menuContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)

                Text("vibecodeos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    controller.collapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .background(Color.white.opacity(0.1))

            // Menu items
            VStack(spacing: 4) {
                MenuItemRow(icon: "bolt.fill", title: "Monitoring", subtitle: "Active", color: .green)
                MenuItemRow(icon: "eye.fill", title: "Screen OCR", subtitle: "Enabled", color: .blue)
                MenuItemRow(icon: "bell.fill", title: "Notifications", subtitle: "Watching", color: .orange)
                MenuItemRow(icon: "keyboard.fill", title: "Keyboard", subtitle: "Listening", color: .purple)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(Color.white.opacity(0.1))

            // Footer
            HStack {
                Text("AI Assistant Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Menu Item Row

struct MenuItemRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

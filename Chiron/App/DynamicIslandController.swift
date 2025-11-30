//
//  DynamicIslandController.swift
//  AxPlayground
//
//  Shows a small glowing orb that expands into Dynamic Island menu
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
    
    private var orbWindow: NSWindow?
    private var islandWindow: NSWindow?
    
    // Dimensions
    private let orbSize: CGFloat = 20
    private let margin: CGFloat = 30
    
    // Menu dimensions (longer than notification)
    private let menuWidth: CGFloat = 380 + (28 * 2)
    private let menuHeight: CGFloat = 450 // Dłuższe dla menu
    
    // Position (shared between orb and island)
    private var centerX: CGFloat = 0
    private var topY: CGFloat = 0
    
    // Menu content provider
    var menuContentProvider: (() -> AnyView)?
    
    private init() {}
    
    // MARK: - Public API
    
    func show() {
        guard orbWindow == nil else { return }
        calculatePosition()
        createOrbWindow()
    }
    
    func hide() {
        orbWindow?.orderOut(nil)
        orbWindow = nil
        hideIsland()
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
        isExpanded = true
        isVisible = true
        
        // Show island (orb stays visible on top)
        showIsland()
    }
    
    func collapse() {
        guard isExpanded else { return }
        
        // Animate out
        isVisible = false
        
        // Wait for animation then hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hideIsland()
            self?.isExpanded = false
        }
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
    
    // MARK: - Private - Position
    
    private func calculatePosition() {
        guard let screen = NSScreen.main else { return }
        
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let menuBarHeight = fullFrame.height - visibleFrame.height - visibleFrame.origin.y + fullFrame.origin.y
        
        if #available(macOS 12.0, *) {
            if let rightArea = screen.auxiliaryTopRightArea {
                centerX = rightArea.origin.x + 40
            } else {
                centerX = screen.frame.midX + 100
            }
        } else {
            centerX = screen.frame.midX + 100
        }
        
        topY = screen.frame.maxY - menuBarHeight / 2
    }
    
    // MARK: - Private - Orb Window
    
    private func createOrbWindow() {
        let windowSize = orbSize + margin * 2
        
        let frame = NSRect(
            x: centerX - windowSize / 2,
            y: topY - windowSize / 2,
            width: windowSize,
            height: windowSize
        )
        
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Orb above island menu
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        
        let contentView = OrbView(controller: self, size: orbSize)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowSize, height: windowSize)
        window.contentView = hostingView
        
        window.orderFrontRegardless()
        orbWindow = window
    }
    
    // MARK: - Private - Island Window
    
    private func showIsland() {
        guard let screen = NSScreen.main else { return }
        
        // Position at top center of screen (where the notch is)
        let windowX = screen.frame.midX - menuWidth / 2
        let windowY = screen.frame.maxY - menuHeight
        
        let frame = NSRect(
            x: windowX,
            y: windowY,
            width: menuWidth,
            height: menuHeight
        )
        
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // High z-index, same as orb
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        
        let contentView = IslandMenuView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight)
        window.contentView = hostingView
        
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        
        islandWindow = window
        setupClickOutsideMonitor()
    }
    
    private func hideIsland() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        islandWindow?.orderOut(nil)
        islandWindow = nil
    }
    
    private var clickMonitor: Any?
    
    private func setupClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
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

// MARK: - Orb View

struct OrbView: View {
    @ObservedObject var controller: DynamicIslandController
    let size: CGFloat
    
    var body: some View {
        ZStack {
            SiriOrbCompact(size: size, isActive: controller.hasActivity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle()) // Make entire area tappable, not just the ring stroke
        .onTapGesture {
            controller.toggle()
        }
    }
}

// MARK: - Island Menu View (Extended menu)

struct IslandMenuView: View {
    @ObservedObject var controller: DynamicIslandController
    
    @State private var animationProgress: CGFloat = 0.0
    @State private var contentOpacity: CGFloat = 0.0
    
    // Dimensions
    private let expandedWidth: CGFloat = 380
    private let expandedHeight: CGFloat = 400
    private let collapsedWidth: CGFloat = 180
    private let collapsedHeight: CGFloat = 32
    private let cornerRadius: CGFloat = 28
    
    private var currentWidth: CGFloat {
        collapsedWidth + (expandedWidth - collapsedWidth) * animationProgress
    }
    
    private var currentHeight: CGFloat {
        collapsedHeight + (expandedHeight - collapsedHeight) * animationProgress
    }
    
    private var currentCornerRadius: CGFloat {
        16 + (cornerRadius - 16) * animationProgress
    }
    
    private var currentTopInvertedRadius: CGFloat {
        cornerRadius * animationProgress
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background with inverted top corners
            DynamicIslandShape(
                bottomCornerRadius: currentCornerRadius,
                topInvertedRadius: currentTopInvertedRadius
            )
            .fill(.black)
            .shadow(color: .black.opacity(0.4 * animationProgress), radius: 16, x: 0, y: 8)
            .frame(width: currentWidth + (currentTopInvertedRadius * 2), height: currentHeight)
            
            // Content
            menuContent
                .frame(width: expandedWidth, height: expandedHeight)
                .opacity(contentOpacity)
        }
        .frame(width: expandedWidth + (cornerRadius * 2), height: expandedHeight + 20, alignment: .top)
        .onAppear {
            withAnimation(.timingCurve(0.76, 0, 0.24, 1, duration: 0.4)) {
                animationProgress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.2)) {
                    contentOpacity = 1.0
                }
            }
        }
        .onChange(of: controller.isVisible) { _, visible in
            if !visible {
                withAnimation(.easeIn(duration: 0.15)) {
                    contentOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.timingCurve(0.76, 0, 0.24, 1, duration: 0.3)) {
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
                
                Text("Chiron")
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

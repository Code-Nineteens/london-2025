import SwiftUI
import Combine
import AppKit

/// Global manager for showing Dynamic Island style notifications at top center
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isShowing = false
    @Published var isVisible = false
    @Published var title = "Notification"
    @Published var message: String? = nil
    @Published var icon: String? = "bell.fill"
    @Published var actionButtonTitle: String = "Insert Now"
    @Published var actionButtonIcon: String = "sparkles"

    private var overlayWindow: NSWindow?
    private var dismissTimer: Timer?

    // Action callbacks
    private var onInsertNow: (() -> Void)?

    private init() {}

    func show(
        title: String,
        message: String? = nil,
        icon: String? = "bell.fill",
        actionButtonTitle: String = "Insert Now",
        actionButtonIcon: String = "sparkles",
        autoDismissAfter: TimeInterval = 6.0,
        onAddToQueue: (() -> Void)? = nil,
        onInsertNow: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil
    ) {
        print("🏝️ NotificationManager.show() called: \(title)")
        
        self.title = title
        self.message = message
        self.icon = icon
        self.actionButtonTitle = actionButtonTitle
        self.actionButtonIcon = actionButtonIcon
        self.onInsertNow = onInsertNow
        self.isShowing = true
        self.isVisible = true

        showDynamicIsland()
        print("🏝️ Dynamic Island window created")

        // Auto-dismiss after specified time
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.hide()
            }
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Trigger scale down animation
        isVisible = false

        // Wait for animation to complete before removing window (0.15 content fade + 0.3 scale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hideDynamicIsland()
            self?.isShowing = false
        }
    }

    // MARK: - Private Methods

    private func showDynamicIsland() {
        print("🏝️ showDynamicIsland() - START")
        
        // Close previous window if exists
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        guard let screen = NSScreen.main else {
            print("🏝️ ❌ No main screen!")
            return
        }
        print("🏝️ Screen found: \(screen.frame)")

        // Dynamic Island dimensions (extra width for inverted corners)
        let maxWidth: CGFloat = 380 + (28 * 2) // base width + inverted radius on each side
        let maxHeight: CGFloat = 160

        // Position at top center of screen (where the notch would be)
        let windowX = screen.frame.midX - maxWidth / 2
        let windowY = screen.frame.maxY - maxHeight // No top margin - aligned with top

        let windowFrame = NSRect(
            x: windowX,
            y: windowY,
            width: maxWidth,
            height: maxHeight
        )

        // Create window
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver // Above everything including menu bar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false

        // SwiftUI content with binding to isVisible
        let contentView = DynamicIslandContainerView(
            title: title,
            message: message,
            icon: icon,
            actionButtonTitle: actionButtonTitle,
            actionButtonIcon: actionButtonIcon,
            manager: self,
            onInsertNow: onInsertNow
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: maxHeight)
        window.contentView = hostingView

        // Show with fade in
        window.alphaValue = 0
        window.orderFrontRegardless()
        print("🏝️ Window ordered front, frame: \(window.frame)")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        overlayWindow = window
        print("🏝️ showDynamicIsland() - DONE ✅")
    }

    private func hideDynamicIsland() {
        guard let window = overlayWindow else { return }
        window.orderOut(nil)
        overlayWindow = nil
    }
}

// MARK: - Container View for Binding

private struct DynamicIslandContainerView: View {
    let title: String
    let message: String?
    let icon: String?
    let actionButtonTitle: String
    let actionButtonIcon: String
    @ObservedObject var manager: NotificationManager
    let onInsertNow: (() -> Void)?

    var body: some View {
        DynamicIslandView(
            title: title,
            message: message,
            icon: icon,
            onClose: {
                manager.hide()
            },
            onInsertNow: onInsertNow,
            actionButtonTitle: actionButtonTitle,
            actionButtonIcon: actionButtonIcon,
            isVisible: $manager.isVisible
        )
    }
}

import SwiftUI
import Combine
import AppKit

/// Globalny manager do pokazywania powiadomień jako overlay w prawym górnym rogu
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isShowing = false
    @Published var title = "Powiadomienie"
    @Published var message: String? = nil
    @Published var icon: String? = "bell.fill"
    
    private var overlayWindow: NSWindow?
    private var dismissTimer: Timer?
    
    // Action callbacks
    private var onAddToQueue: (() -> Void)?
    private var onInsertNow: (() -> Void)?
    private var onReject: (() -> Void)?
    
    private init() {}
    
    func show(
        title: String,
        message: String? = nil,
        icon: String? = "bell.fill",
        autoDismissAfter: TimeInterval = 5.0,
        onAddToQueue: (() -> Void)? = nil,
        onInsertNow: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.onAddToQueue = onAddToQueue
        self.onInsertNow = onInsertNow
        self.onReject = onReject
        self.isShowing = true
        
        showOverlayWindow()
        
        // Auto-dismiss po określonym czasie
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }
    
    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        hideOverlayWindow()
        isShowing = false
    }
    
    // MARK: - Private Methods
    
    private func showOverlayWindow() {
        // Zamknij poprzednie okno jeśli istnieje
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        
        guard let screen = NSScreen.main else { return }

        // SwiftUI content
        let contentView = NotificationContentView(
            title: title,
            message: message,
            icon: icon,
            onClose: { [weak self] in
                self?.hide()
            },
            onAddToQueue: onAddToQueue,
            onInsertNow: onInsertNow,
            onReject: onReject
        )

        let hostingView = NSHostingView(rootView: contentView)

        // Calculate intrinsic size
        let fittingSize = hostingView.fittingSize
        let notificationWidth = min(fittingSize.width, 320)
        let notificationHeight = fittingSize.height

        let padding: CGFloat = 16
        let topMargin: CGFloat = 50

        // Pozycja w prawym górnym rogu
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let windowX = screen.frame.maxX - notificationWidth - padding
        let windowY = screen.frame.maxY - menuBarHeight - topMargin - notificationHeight

        let windowFrame = NSRect(
            x: windowX,
            y: windowY,
            width: notificationWidth,
            height: notificationHeight
        )

        // Małe okno tylko na powiadomienie
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false

        hostingView.frame = NSRect(x: 0, y: 0, width: notificationWidth, height: notificationHeight)
        window.contentView = hostingView
        
        // Animacja pojawienia się (slide in from top)
        window.setFrameOrigin(NSPoint(x: windowX, y: windowY + 20))
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(NSPoint(x: windowX, y: windowY))
            window.animator().alphaValue = 1
        }
        
        overlayWindow = window
    }
    
    private func hideOverlayWindow() {
        guard let window = overlayWindow else { return }
        
        let currentFrame = window.frame
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrameOrigin(NSPoint(x: currentFrame.origin.x, y: currentFrame.origin.y + 20))
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.overlayWindow = nil
        })
    }
}

// MARK: - Notification Content View

private struct NotificationContentView: View {
    let title: String
    let message: String?
    let icon: String?
    let onClose: () -> Void
    let onAddToQueue: (() -> Void)?
    let onInsertNow: (() -> Void)?
    let onReject: (() -> Void)?
    
    var body: some View {
        GlassNotificationView(
            title: title,
            message: message,
            icon: icon,
            onClose: onClose,
            onAddToQueue: onAddToQueue,
            onInsertNow: onInsertNow,
            onReject: onReject
        )
    }
}

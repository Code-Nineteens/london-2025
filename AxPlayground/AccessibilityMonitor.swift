//
//  AccessibilityMonitor.swift
//  AxPlayground
//
//  Created by Piotr Pasztor on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

struct AccessibilityEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let appName: String
    let appBundleId: String?
    let role: String?
    let roleDescription: String?
    let title: String?
    let value: String?
    let description: String?
    let position: CGPoint?
    let size: CGSize?
    let clickLocation: CGPoint
}

class InputFieldInfo {
    private let elementRef: Unmanaged<AXUIElement>
    let position: CGPoint
    let size: CGSize
    let originalValue: String
    let exampleText: String

    var element: AXUIElement {
        elementRef.takeUnretainedValue()
    }

    /// Returns a retained copy of the element that the caller is responsible for releasing
    func retainElement() -> AXUIElement {
        return elementRef.retain().takeUnretainedValue()
    }

    init(element: AXUIElement, position: CGPoint, size: CGSize, originalValue: String, exampleText: String) {
        // Retain the element to prevent it from being released
        self.elementRef = Unmanaged.passRetained(element)
        self.position = position
        self.size = size
        self.originalValue = originalValue
        self.exampleText = exampleText
    }

    deinit {
        elementRef.release()
    }
}

class AccessibilityMonitor: ObservableObject {
    @Published var hasPermission = false
    @Published var events: [AccessibilityEvent] = []
    @Published var currentInputField: InputFieldInfo?
    @Published var showOverlay = false

    private var eventTap: CFMachPort?
    private var keyboardEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyboardRunLoopSource: CFRunLoopSource?
    private var overlayWindow: NSWindow?

    var uniqueAppNames: [String] {
        Array(Set(events.map { $0.appName })).sorted()
    }

    func clearEvents() {
        events.removeAll()
    }

    // Example texts based on field description/title
    private func generateExampleText(for element: AXUIElement) -> String {
        let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String ?? ""
        let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String ?? ""
        let placeholder = getAttributeValue(element: element, attribute: kAXPlaceholderValueAttribute as CFString) as? String ?? ""

        let combined = "\(description) \(title) \(placeholder)".lowercased()

        if combined.contains("email") {
            return "john.doe@example.com"
        } else if combined.contains("password") {
            return "SecureP@ss123"
        } else if combined.contains("name") || combined.contains("user") {
            return "John Doe"
        } else if combined.contains("phone") || combined.contains("tel") {
            return "+1 (555) 123-4567"
        } else if combined.contains("address") {
            return "123 Main Street, City"
        } else if combined.contains("search") {
            return "Search query example"
        } else if combined.contains("url") || combined.contains("website") {
            return "https://example.com"
        } else if combined.contains("date") {
            return "2025-01-15"
        } else {
            return "Example input text"
        }
    }

    private func isInputField(role: String?) -> Bool {
        guard let role = role else { return false }
        return role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox" || role == "AXSearchField"
    }

    init() {
        checkPermission()
    }

    func checkPermission() {
        hasPermission = AXIsProcessTrusted()
    }

    func requestPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let wasGranted = AXIsProcessTrustedWithOptions(options)
        hasPermission = wasGranted

        if !wasGranted {
            // Open System Settings to Privacy & Security
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func startMonitoring() {
        // Check if we have accessibility permissions
        checkPermission()
        if !hasPermission {
            print("⚠️ Accessibility permissions not granted. Please enable in System Settings > Privacy & Security > Accessibility")
            requestPermission()
            return
        }

        print("✅ Starting accessibility monitor...")

        // Create event tap for left mouse down events
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Get the monitor instance
                let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handleClick(event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap")
            return
        }

        self.eventTap = eventTap

        // Create run loop source and add to current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Create keyboard event tap for Cmd+Shift+S shortcut
        let keyboardEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let keyboardTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(keyboardEventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleKeyDown(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create keyboard event tap")
            return
        }

        self.keyboardEventTap = keyboardTap

        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyboardTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)

        CGEvent.tapEnable(tap: keyboardTap, enable: true)

        print("🎯 Monitor is active. Press Cmd+Shift+S on an input field to show suggestions!")
    }

    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
        }
        if let keyboardTap = keyboardEventTap {
            CGEvent.tapEnable(tap: keyboardTap, enable: false)
            if let keyboardSource = keyboardRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyboardSource, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        keyboardEventTap = nil
        keyboardRunLoopSource = nil
        hideOverlay()
        print("⏹️ Monitor stopped")
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check for Cmd+Shift+S (keycode 1 = 'S')
        let isCmd = flags.contains(.maskCommand)
        let isShift = flags.contains(.maskShift)
        let isSKey = keyCode == 1

        if isCmd && isShift && isSKey {
            print("⌨️ Cmd+Shift+S pressed!")

            DispatchQueue.main.async {
                self.checkFocusedElementAndShowOverlay()
            }

            // Consume the event so it doesn't propagate
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func checkFocusedElementAndShowOverlay() {
        // Get the focused element from the system
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard error == .success, let element = focusedElement else {
            print("   No focused element found")
            return
        }

        let axElement = element as! AXUIElement
        let role = getAttributeValue(element: axElement, attribute: kAXRoleAttribute as CFString) as? String

        if isInputField(role: role) {
            print("   📝 Input field is focused! Showing overlay...")
            handleInputFieldFocus(element: axElement)
        } else {
            print("   Focused element is not an input field (role: \(role ?? "unknown"))")
        }
    }

    private func handleInputFieldFocus(element: AXUIElement) {
        // Get position and size
        var position = CGPoint.zero
        var size = CGSize.zero

        if let posValue = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        }

        if let sizeValue = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        // Get current value
        let currentValue = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) as? String ?? ""

        // Generate example text
        let exampleText = generateExampleText(for: element)

        let inputInfo = InputFieldInfo(
            element: element,
            position: position,
            size: size,
            originalValue: currentValue,
            exampleText: exampleText
        )

        currentInputField = inputInfo
        showOverlay = true

        // Show the overlay window
        showOverlayWindow(for: inputInfo)
    }

    private func handleClick(event: CGEvent) {
        let location = event.location

        // Check if click is on our overlay window - if so, ignore it
        if let overlay = overlayWindow {
            let windowFrame = overlay.frame
            // Convert screen coordinates (top-left origin for CGEvent, bottom-left for NSWindow)
            if let screen = NSScreen.main {
                let screenHeight = screen.frame.height
                let clickY = screenHeight - location.y
                let clickPoint = NSPoint(x: location.x, y: clickY)
                if windowFrame.contains(clickPoint) {
                    print("   Click on overlay - ignoring")
                    return
                }
            }
        }

        print("\n🖱️ Click detected at: (\(Int(location.x)), \(Int(location.y)))")

        // Hide overlay when clicking elsewhere
        if showOverlay {
            DispatchQueue.main.async {
                self.hideOverlay()
            }
        }

        // Get the accessibility element at this position
        if let element = getAccessibilityElement(at: location) {
            let accessibilityEvent = createEvent(from: element, at: location)
            DispatchQueue.main.async {
                self.events.insert(accessibilityEvent, at: 0)
            }
            logElementInfo(element)
        } else {
            print("   No accessibility element found at this location")
        }
    }

    private func showOverlayWindow(for inputInfo: InputFieldInfo) {
        // Close existing overlay if any
        overlayWindow?.close()

        // Calculate overlay position (below the input field)
        let overlayWidth: CGFloat = max(inputInfo.size.width, 300)
        let overlayHeight: CGFloat = 90

        // Convert from top-left origin to bottom-left origin for NSWindow
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let overlayY = screenHeight - inputInfo.position.y - inputInfo.size.height - overlayHeight - 8

        let overlayFrame = NSRect(
            x: inputInfo.position.x,
            y: overlayY,
            width: overlayWidth,
            height: overlayHeight
        )

        // Create the overlay window
        let window = NSWindow(
            contentRect: overlayFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        // Create the main container view
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight))
        containerView.wantsLayer = true

        // Create visual effect view for liquid glass blur effect
        let visualEffectView = NSVisualEffectView(frame: containerView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true

        // Add a subtle gradient overlay for liquid glass effect
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = containerView.bounds
        gradientLayer.cornerRadius = 16
        gradientLayer.colors = [
            NSColor.white.withAlphaComponent(0.15).cgColor,
            NSColor.white.withAlphaComponent(0.05).cgColor,
            NSColor.clear.cgColor
        ]
        gradientLayer.locations = [0.0, 0.3, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)

        // Add inner glow/border effect
        let borderLayer = CALayer()
        borderLayer.frame = containerView.bounds
        borderLayer.cornerRadius = 16
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        // Add subtle shadow inside
        let innerShadowLayer = CALayer()
        innerShadowLayer.frame = containerView.bounds.insetBy(dx: 1, dy: 1)
        innerShadowLayer.cornerRadius = 15
        innerShadowLayer.borderWidth = 1
        innerShadowLayer.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor

        containerView.addSubview(visualEffectView)
        containerView.layer?.addSublayer(gradientLayer)
        containerView.layer?.addSublayer(borderLayer)

        // Content container with padding
        let contentView = NSView(frame: NSRect(x: 16, y: 12, width: overlayWidth - 32, height: overlayHeight - 24))

        // Example text label with subtle styling
        let label = NSTextField(labelWithString: inputInfo.exampleText)
        label.frame = NSRect(x: 0, y: 38, width: overlayWidth - 32, height: 22)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor.labelColor
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingTail
        contentView.addSubview(label)

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Suggested text")
        subtitle.frame = NSRect(x: 0, y: 56, width: overlayWidth - 32, height: 14)
        subtitle.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        subtitle.textColor = NSColor.secondaryLabelColor
        subtitle.backgroundColor = .clear
        contentView.addSubview(subtitle)

        // Button container
        let buttonContainer = NSView(frame: NSRect(x: 0, y: 0, width: overlayWidth - 32, height: 32))

        // Accept button with custom styling
        let acceptButton = NSButton(frame: NSRect(x: 0, y: 0, width: 90, height: 28))
        acceptButton.title = "Accept"
        acceptButton.bezelStyle = .rounded
        acceptButton.controlSize = .regular
        acceptButton.target = self
        acceptButton.action = #selector(acceptButtonClicked)
        acceptButton.keyEquivalent = "\r" // Enter key
        buttonContainer.addSubview(acceptButton)

        // Deny button
        let denyButton = NSButton(frame: NSRect(x: 98, y: 0, width: 90, height: 28))
        denyButton.title = "Dismiss"
        denyButton.bezelStyle = .rounded
        denyButton.controlSize = .regular
        denyButton.target = self
        denyButton.action = #selector(denyButtonClicked)
        denyButton.keyEquivalent = "\u{1b}" // Escape key
        buttonContainer.addSubview(denyButton)

        contentView.addSubview(buttonContainer)
        containerView.addSubview(contentView)

        window.contentView = containerView

        // Animate window appearance
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        overlayWindow = window
    }

    @objc private func acceptButtonClicked() {
        guard let inputInfo = currentInputField else { return }

        // Retain element and capture text before hiding overlay
        let element = inputInfo.retainElement()
        let text = inputInfo.exampleText

        // Hide overlay first
        hideOverlay()

        // Set the value
        let error = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if error == .success {
            print("   ✅ Example text inserted: \(text)")
        } else {
            print("   ❌ Failed to insert text: \(error.rawValue)")
        }

        // Release the retained element
        Unmanaged.passUnretained(element).release()
    }

    @objc private func denyButtonClicked() {
        guard let inputInfo = currentInputField else { return }

        // Retain element and capture original value before hiding overlay
        let element = inputInfo.retainElement()
        let originalValue = inputInfo.originalValue

        // Hide overlay first
        hideOverlay()

        // Restore the value
        let error = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            originalValue as CFTypeRef
        )

        if error == .success {
            print("   ↩️ Original value restored")
        } else {
            print("   ❌ Failed to restore value: \(error.rawValue)")
        }

        // Release the retained element
        Unmanaged.passUnretained(element).release()
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        currentInputField = nil
        showOverlay = false
    }

    private func createEvent(from element: AXUIElement, at location: CGPoint) -> AccessibilityEvent {
        // Get the app info by traversing up to the application element
        let (appName, bundleId) = getAppInfo(for: element)

        let role = getAttributeValue(element: element, attribute: kAXRoleAttribute as CFString) as? String
        let roleDescription = getAttributeValue(element: element, attribute: kAXRoleDescriptionAttribute as CFString) as? String
        let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String
        let value: String? = {
            if let val = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) {
                return String(describing: val)
            }
            return nil
        }()
        let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String

        var position: CGPoint?
        if let posValue = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) {
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            position = point
        }

        var size: CGSize?
        if let sizeValue = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) {
            var cgSize = CGSize.zero
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize)
            size = cgSize
        }

        return AccessibilityEvent(
            timestamp: Date(),
            appName: appName,
            appBundleId: bundleId,
            role: role,
            roleDescription: roleDescription,
            title: title,
            value: value,
            description: description,
            position: position,
            size: size,
            clickLocation: location
        )
    }

    private func getAppInfo(for element: AXUIElement) -> (appName: String, bundleId: String?) {
        // Try to get the application element by traversing up
        var currentElement: AXUIElement? = element

        while let current = currentElement {
            if let role = getAttributeValue(element: current, attribute: kAXRoleAttribute as CFString) as? String,
               role == "AXApplication" {
                let appTitle = getAttributeValue(element: current, attribute: kAXTitleAttribute as CFString) as? String ?? "Unknown"

                // Try to get the PID and then bundle ID
                var pid: pid_t = 0
                if AXUIElementGetPid(current, &pid) == .success {
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        return (app.localizedName ?? appTitle, app.bundleIdentifier)
                    }
                }
                return (appTitle, nil)
            }

            // Get parent
            currentElement = getAttributeValue(element: current, attribute: kAXParentAttribute as CFString) as! AXUIElement?
        }

        return ("Unknown", nil)
    }

    private func getAccessibilityElement(at point: CGPoint) -> AXUIElement? {
        // Get system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()

        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        if error == .success {
            return element
        } else {
            print("   Error getting element: \(error.rawValue)")
            return nil
        }
    }

    private func logElementInfo(_ element: AXUIElement) {
        print("   📋 Accessibility Element Info:")

        // Get role
        if let role = getAttributeValue(element: element, attribute: kAXRoleAttribute as CFString) as? String {
            print("   • Role: \(role)")
        }

        // Get role description
        if let roleDescription = getAttributeValue(element: element, attribute: kAXRoleDescriptionAttribute as CFString) as? String {
            print("   • Role Description: \(roleDescription)")
        }

        // Get title
        if let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String {
            print("   • Title: \(title)")
        }

        // Get value
        if let value = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) {
            print("   • Value: \(value)")
        }

        // Get description
        if let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String {
            print("   • Description: \(description)")
        }

        // Get help text
        if let help = getAttributeValue(element: element, attribute: kAXHelpAttribute as CFString) as? String {
            print("   • Help: \(help)")
        }

        // Get position
        if let position = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) {
            var point = CGPoint.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            print("   • Position: (\(Int(point.x)), \(Int(point.y)))")
        }

        // Get size
        if let size = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) {
            var cgSize = CGSize.zero
            AXValueGetValue(size as! AXValue, .cgSize, &cgSize)
            print("   • Size: \(Int(cgSize.width)) × \(Int(cgSize.height))")
        }
    }

    private func getAttributeValue(element: AXUIElement, attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    deinit {
        stopMonitoring()
    }
}

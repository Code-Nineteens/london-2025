//
//  AccessibilityMonitor+Overlay.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa
import ApplicationServices

// MARK: - Overlay Window

extension AccessibilityMonitor {
    
    func showOverlayWindow(for inputInfo: InputFieldInfo) {
        overlayWindow?.close()
        
        guard let screen = NSScreen.main else { return }
        
        let overlayFrame = calculateOverlayFrame(for: inputInfo, screenHeight: screen.frame.height)
        let window = createOverlayWindow(frame: overlayFrame)
        let containerView = createOverlayContentView(width: overlayFrame.width, height: overlayFrame.height, inputInfo: inputInfo)
        
        window.contentView = containerView
        animateWindowAppearance(window)
        
        overlayWindow = window
    }
    
    private func calculateOverlayFrame(for inputInfo: InputFieldInfo, screenHeight: CGFloat) -> NSRect {
        let overlayWidth: CGFloat = max(inputInfo.size.width, 300)
        let overlayHeight: CGFloat = 90
        let overlayY = screenHeight - inputInfo.position.y - inputInfo.size.height - overlayHeight - 8
        
        return NSRect(
            x: inputInfo.position.x,
            y: overlayY,
            width: overlayWidth,
            height: overlayHeight
        )
    }
    
    private func createOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        
        return window
    }
    
    private func createOverlayContentView(width: CGFloat, height: CGFloat, inputInfo: InputFieldInfo) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        containerView.wantsLayer = true
        
        addVisualEffectView(to: containerView)
        addGradientAndBorderLayers(to: containerView)
        addContentView(to: containerView, inputInfo: inputInfo)
        
        return containerView
    }
    
    private func addVisualEffectView(to containerView: NSView) {
        let visualEffectView = NSVisualEffectView(frame: containerView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        
        containerView.addSubview(visualEffectView)
    }
    
    private func addGradientAndBorderLayers(to containerView: NSView) {
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
        
        let borderLayer = CALayer()
        borderLayer.frame = containerView.bounds
        borderLayer.cornerRadius = 16
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        
        containerView.layer?.addSublayer(gradientLayer)
        containerView.layer?.addSublayer(borderLayer)
    }
    
    private func addContentView(to containerView: NSView, inputInfo: InputFieldInfo) {
        let contentWidth = containerView.bounds.width - 32
        let contentView = NSView(frame: NSRect(x: 16, y: 12, width: contentWidth, height: containerView.bounds.height - 24))
        
        addLabels(to: contentView, exampleText: inputInfo.exampleText, width: contentWidth)
        addButtons(to: contentView, width: contentWidth)
        
        containerView.addSubview(contentView)
    }
    
    private func addLabels(to contentView: NSView, exampleText: String, width: CGFloat) {
        let label = NSTextField(labelWithString: exampleText)
        label.frame = NSRect(x: 0, y: 38, width: width, height: 22)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor.labelColor
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingTail
        contentView.addSubview(label)
        
        let subtitle = NSTextField(labelWithString: "Suggested text")
        subtitle.frame = NSRect(x: 0, y: 56, width: width, height: 14)
        subtitle.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        subtitle.textColor = NSColor.secondaryLabelColor
        subtitle.backgroundColor = .clear
        contentView.addSubview(subtitle)
    }
    
    private func addButtons(to contentView: NSView, width: CGFloat) {
        let buttonContainer = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        
        let acceptButton = NSButton(frame: NSRect(x: 0, y: 0, width: 90, height: 28))
        acceptButton.title = "Accept"
        acceptButton.bezelStyle = .rounded
        acceptButton.controlSize = .regular
        acceptButton.target = self
        acceptButton.action = #selector(acceptButtonClicked)
        acceptButton.keyEquivalent = "\r"
        buttonContainer.addSubview(acceptButton)
        
        let denyButton = NSButton(frame: NSRect(x: 98, y: 0, width: 90, height: 28))
        denyButton.title = "Dismiss"
        denyButton.bezelStyle = .rounded
        denyButton.controlSize = .regular
        denyButton.target = self
        denyButton.action = #selector(denyButtonClicked)
        denyButton.keyEquivalent = "\u{1b}"
        buttonContainer.addSubview(denyButton)
        
        contentView.addSubview(buttonContainer)
    }
    
    private func animateWindowAppearance(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
}

// MARK: - Button Actions

extension AccessibilityMonitor {
    
    @objc func acceptButtonClicked() {
        guard let inputInfo = currentInputField else { return }
        
        let element = inputInfo.retainElement()
        let text = inputInfo.exampleText
        
        hideOverlay()
        
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
        
        Unmanaged.passUnretained(element).release()
    }
    
    @objc func denyButtonClicked() {
        guard let inputInfo = currentInputField else { return }
        
        let element = inputInfo.retainElement()
        let originalValue = inputInfo.originalValue
        
        hideOverlay()
        
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
        
        Unmanaged.passUnretained(element).release()
    }
}


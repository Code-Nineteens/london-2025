//
//  AccessibilityMonitor.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Monitors system-wide accessibility events and provides input field assistance.
final class AccessibilityMonitor: ObservableObject, AccessibilityMonitoring {
    
    // MARK: - Published Properties
    
    @Published var hasPermission = false
    @Published var events: [AccessibilityEvent] = []
    @Published var currentInputField: InputFieldInfo?
    @Published var showOverlay = false
    
    // MARK: - Internal Properties
    
    var eventTap: CFMachPort?
    var keyboardEventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var keyboardRunLoopSource: CFRunLoopSource?
    var overlayWindow: NSWindow?
    
    // MARK: - Computed Properties
    
    var uniqueAppNames: [String] {
        Array(Set(events.map { $0.appName })).sorted()
    }
    
    // MARK: - Initialization
    
    init() {
        checkPermission()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func clearEvents() {
        events.removeAll()
    }
    
    func checkPermission() {
        hasPermission = AXIsProcessTrusted()
    }
    
    func requestPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let wasGranted = AXIsProcessTrustedWithOptions(options)
        hasPermission = wasGranted
        
        if !wasGranted {
            openAccessibilitySettings()
        }
    }
    
    func startMonitoring() {
        checkPermission()
        
        guard hasPermission else {
            print("⚠️ Accessibility permissions not granted. Please enable in System Settings > Privacy & Security > Accessibility")
            requestPermission()
            return
        }
        
        print("✅ Starting accessibility monitor...")
        
        setupMouseEventTap()
        setupKeyboardEventTap()
        
        print("🎯 Monitor is active. Press Cmd+Shift+S on an input field to show suggestions!")
    }
    
    func stopMonitoring() {
        disableEventTap(eventTap, runLoopSource: runLoopSource)
        disableEventTap(keyboardEventTap, runLoopSource: keyboardRunLoopSource)
        
        eventTap = nil
        runLoopSource = nil
        keyboardEventTap = nil
        keyboardRunLoopSource = nil
        
        hideOverlay()
        print("⏹️ Monitor stopped")
    }
    
    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        currentInputField = nil
        showOverlay = false
    }
    
    // MARK: - Private Methods - Setup
    
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    private func setupMouseEventTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, _, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleClick(event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func setupKeyboardEventTap() {
        let keyboardEventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(keyboardEventMask),
            callback: { (_, _, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleKeyDown(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create keyboard event tap")
            return
        }
        
        keyboardEventTap = tap
        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func disableEventTap(_ tap: CFMachPort?, runLoopSource: CFRunLoopSource?) {
        guard let tap = tap else { return }
        
        CGEvent.tapEnable(tap: tap, enable: false)
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}

//
//  AccessibilityMonitor+EventHandling.swift
//  szpontOS
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa
import ApplicationServices

// MARK: - Event Handling

extension AccessibilityMonitor {
    
    func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        let isCmdShiftS = flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 1
        
        guard isCmdShiftS else {
            return Unmanaged.passRetained(event)
        }
        
        print("⌨️ Cmd+Shift+S pressed!")
        
        DispatchQueue.main.async { [weak self] in
            self?.checkFocusedElementAndShowOverlay()
        }
        
        return nil
    }
    
    func handleClick(event: CGEvent) {
        let location = event.location
        
        if isClickOnOverlay(at: location) {
            print("   Click on overlay - ignoring")
            return
        }
        
        print("\n🖱️ Click detected at: (\(Int(location.x)), \(Int(location.y)))")
        
        if showOverlay {
            DispatchQueue.main.async { [weak self] in
                self?.hideOverlay()
            }
        }
        
        if let element = getAccessibilityElement(at: location) {
            let accessibilityEvent = createEvent(from: element, at: location)
            DispatchQueue.main.async { [weak self] in
                self?.events.insert(accessibilityEvent, at: 0)
            }
            logElementInfo(element)
        } else {
            print("   No accessibility element found at this location")
        }
    }
    
    private func isClickOnOverlay(at location: CGPoint) -> Bool {
        guard let overlay = overlayWindow, let screen = NSScreen.main else {
            return false
        }
        
        let screenHeight = screen.frame.height
        let clickY = screenHeight - location.y
        let clickPoint = NSPoint(x: location.x, y: clickY)
        
        return overlay.frame.contains(clickPoint)
    }
}

// MARK: - Focus Handling

extension AccessibilityMonitor {
    
    func checkFocusedElementAndShowOverlay() {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard error == .success, let rawElement = focusedElement else {
            print("   No focused element found")
            return
        }
        
        // swiftlint:disable:next force_cast
        let element = rawElement as! AXUIElement
        
        let role = getAttributeValue(element: element, attribute: kAXRoleAttribute as CFString) as? String
        
        if isInputField(role: role) {
            print("   📝 Input field is focused! Showing overlay...")
            handleInputFieldFocus(element: element)
        } else {
            print("   Focused element is not an input field (role: \(role ?? "unknown"))")
        }
    }
    
    func handleInputFieldFocus(element: AXUIElement) {
        let position = extractPosition(from: element)
        let size = extractSize(from: element)
        let currentValue = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) as? String ?? ""
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
        
        showOverlayWindow(for: inputInfo)
    }
    
    func isInputField(role: String?) -> Bool {
        guard let role = role else { return false }
        
        let inputFieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        return inputFieldRoles.contains(role)
    }
}

// MARK: - Example Text Generation

extension AccessibilityMonitor {
    
    func generateExampleText(for element: AXUIElement) -> String {
        let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String ?? ""
        let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String ?? ""
        let placeholder = getAttributeValue(element: element, attribute: kAXPlaceholderValueAttribute as CFString) as? String ?? ""
        
        let combined = "\(description) \(title) \(placeholder)".lowercased()
        
        return exampleTextForFieldType(combined)
    }
    
    private func exampleTextForFieldType(_ fieldDescription: String) -> String {
        let fieldPatterns: [(pattern: String, example: String)] = [
            ("email", "john.doe@example.com"),
            ("password", "SecureP@ss123"),
            ("name", "John Doe"),
            ("user", "John Doe"),
            ("phone", "+1 (555) 123-4567"),
            ("tel", "+1 (555) 123-4567"),
            ("address", "123 Main Street, City"),
            ("search", "Search query example"),
            ("url", "https://example.com"),
            ("website", "https://example.com"),
            ("date", "2025-01-15")
        ]
        
        for (pattern, example) in fieldPatterns {
            if fieldDescription.contains(pattern) {
                return example
            }
        }
        
        return "Example input text"
    }
}

// MARK: - Event Creation

extension AccessibilityMonitor {
    
    func createEvent(from element: AXUIElement, at location: CGPoint) -> AccessibilityEvent {
        let (appName, bundleId) = getAppInfo(for: element)
        
        let role = getAttributeValue(element: element, attribute: kAXRoleAttribute as CFString) as? String
        let roleDescription = getAttributeValue(element: element, attribute: kAXRoleDescriptionAttribute as CFString) as? String
        let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String
        let value = extractStringValue(from: element)
        let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String
        
        let position = extractPosition(from: element)
        let size = extractSize(from: element)
        
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
    
    private func extractStringValue(from element: AXUIElement) -> String? {
        guard let val = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) else {
            return nil
        }
        return String(describing: val)
    }
}


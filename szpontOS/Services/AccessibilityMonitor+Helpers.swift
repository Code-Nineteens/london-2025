//
//  AccessibilityMonitor+Helpers.swift
//  szpontOS
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Cocoa
import ApplicationServices

// MARK: - Accessibility Helpers

extension AccessibilityMonitor {
    
    func getAccessibilityElement(at point: CGPoint) -> AXUIElement? {
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
    
    func getAttributeValue(element: AXUIElement, attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return error == .success ? value : nil
    }
    
    func extractPosition(from element: AXUIElement) -> CGPoint {
        guard let posValue = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) else {
            return .zero
        }
        
        // swiftlint:disable:next force_cast
        let axValue = posValue as! AXValue
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }
    
    func extractSize(from element: AXUIElement) -> CGSize {
        guard let sizeValue = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) else {
            return .zero
        }
        
        // swiftlint:disable:next force_cast
        let axValue = sizeValue as! AXValue
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}

// MARK: - App Info

extension AccessibilityMonitor {
    
    func getAppInfo(for element: AXUIElement) -> (appName: String, bundleId: String?) {
        var currentElement: AXUIElement? = element
        
        while let current = currentElement {
            guard let role = getAttributeValue(element: current, attribute: kAXRoleAttribute as CFString) as? String,
                  role == "AXApplication" else {
                // swiftlint:disable:next force_cast
                currentElement = getAttributeValue(element: current, attribute: kAXParentAttribute as CFString).map { $0 as! AXUIElement }
                continue
            }
            
            let appTitle = getAttributeValue(element: current, attribute: kAXTitleAttribute as CFString) as? String ?? "Unknown"
            
            var pid: pid_t = 0
            if AXUIElementGetPid(current, &pid) == .success,
               let app = NSRunningApplication(processIdentifier: pid) {
                return (app.localizedName ?? appTitle, app.bundleIdentifier)
            }
            
            return (appTitle, nil)
        }
        
        return ("Unknown", nil)
    }
}

// MARK: - Logging

extension AccessibilityMonitor {
    
    func logElementInfo(_ element: AXUIElement) {
        print("   📋 Accessibility Element Info:")
        
        logAttribute(element: element, attribute: kAXRoleAttribute as CFString, label: "Role")
        logAttribute(element: element, attribute: kAXRoleDescriptionAttribute as CFString, label: "Role Description")
        logAttribute(element: element, attribute: kAXTitleAttribute as CFString, label: "Title")
        logAttribute(element: element, attribute: kAXValueAttribute as CFString, label: "Value")
        logAttribute(element: element, attribute: kAXDescriptionAttribute as CFString, label: "Description")
        logAttribute(element: element, attribute: kAXHelpAttribute as CFString, label: "Help")
        
        logPosition(element: element)
        logSize(element: element)
    }
    
    private func logAttribute(element: AXUIElement, attribute: CFString, label: String) {
        if let value = getAttributeValue(element: element, attribute: attribute) {
            print("   • \(label): \(value)")
        }
    }
    
    private func logPosition(element: AXUIElement) {
        guard let posValue = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) else {
            return
        }
        
        // swiftlint:disable:next force_cast
        let axValue = posValue as! AXValue
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        print("   • Position: (\(Int(point.x)), \(Int(point.y)))")
    }
    
    private func logSize(element: AXUIElement) {
        guard let sizeValue = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) else {
            return
        }
        
        // swiftlint:disable:next force_cast
        let axValue = sizeValue as! AXValue
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        print("   • Size: \(Int(size.width)) × \(Int(size.height))")
    }
}


//
//  ScreenTextExtractor.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Cocoa
import ApplicationServices

/// Extracts all visible text from the screen using Accessibility APIs
@MainActor
final class ScreenTextExtractor {
    
    static let shared = ScreenTextExtractor()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Extracts all visible text from the currently focused application
    func extractVisibleText() -> String {
        guard let focusedApp = getFocusedApplication() else {
            return ""
        }
        
        var allText: [String] = []
        extractTextFromElement(focusedApp, into: &allText)
        
        return allText.joined(separator: "\n")
    }
    
    /// Extracts all visible text from all windows on screen
    func extractAllScreenText() -> String {
        let systemWide = AXUIElementCreateSystemWide()
        
        var allText: [String] = []
        
        // Get all running applications
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            extractTextFromElement(appElement, into: &allText)
        }
        
        return allText.joined(separator: "\n")
    }
    
    /// Extracts text from a specific window area
    func extractTextFromArea(rect: CGRect) -> String {
        var allText: [String] = []
        
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            extractTextFromElementInArea(appElement, rect: rect, into: &allText)
        }
        
        return allText.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    
    private func getFocusedApplication() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedApp: AnyObject?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        
        guard error == .success else { return nil }
        return (focusedApp as! AXUIElement)
    }
    
    private func extractTextFromElement(_ element: AXUIElement, into texts: inout [String], depth: Int = 0) {
        // Limit recursion depth to avoid infinite loops
        guard depth < 50 else { return }
        
        // Extract text from this element
        if let text = getTextFromElement(element), !text.isEmpty {
            texts.append(text)
        }
        
        // Get children and recurse
        var children: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        guard error == .success, let childArray = children as? [AXUIElement] else { return }
        
        for child in childArray {
            extractTextFromElement(child, into: &texts, depth: depth + 1)
        }
    }
    
    private func extractTextFromElementInArea(_ element: AXUIElement, rect: CGRect, into texts: inout [String], depth: Int = 0) {
        guard depth < 50 else { return }
        
        // Check if element is within the specified area
        let position = extractPosition(from: element)
        let size = extractSize(from: element)
        let elementRect = CGRect(origin: position, size: size)
        
        guard rect.intersects(elementRect) || rect.contains(elementRect) || elementRect.contains(rect) else {
            return
        }
        
        // Extract text from this element
        if let text = getTextFromElement(element), !text.isEmpty {
            texts.append(text)
        }
        
        // Get children and recurse
        var children: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        guard error == .success, let childArray = children as? [AXUIElement] else { return }
        
        for child in childArray {
            extractTextFromElementInArea(child, rect: rect, into: &texts, depth: depth + 1)
        }
    }
    
    private func getTextFromElement(_ element: AXUIElement) -> String? {
        // Try to get value (for text fields, text areas)
        if let value = getAttributeValue(element: element, attribute: kAXValueAttribute as CFString) as? String,
           !value.isEmpty {
            return value
        }
        
        // Try to get title (for buttons, labels, etc.)
        if let title = getAttributeValue(element: element, attribute: kAXTitleAttribute as CFString) as? String,
           !title.isEmpty {
            return title
        }
        
        // Try to get description
        if let description = getAttributeValue(element: element, attribute: kAXDescriptionAttribute as CFString) as? String,
           !description.isEmpty {
            return description
        }
        
        // Try to get help text
        if let help = getAttributeValue(element: element, attribute: kAXHelpAttribute as CFString) as? String,
           !help.isEmpty {
            return help
        }
        
        return nil
    }
    
    private func getAttributeValue(element: AXUIElement, attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return error == .success ? value : nil
    }
    
    private func extractPosition(from element: AXUIElement) -> CGPoint {
        guard let posValue = getAttributeValue(element: element, attribute: kAXPositionAttribute as CFString) else {
            return .zero
        }
        
        let axValue = posValue as! AXValue
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }
    
    private func extractSize(from element: AXUIElement) -> CGSize {
        guard let sizeValue = getAttributeValue(element: element, attribute: kAXSizeAttribute as CFString) else {
            return .zero
        }
        
        let axValue = sizeValue as! AXValue
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}

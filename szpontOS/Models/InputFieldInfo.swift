//
//  InputFieldInfo.swift
//  szpontOS
//
//  Created by Kamil Moskała on 29/11/2025.
//

import ApplicationServices

/// Holds information about a focused input field for overlay display.
@MainActor
final class InputFieldInfo {
    
    // MARK: - Properties
    
    private let elementRef: Unmanaged<AXUIElement>
    let position: CGPoint
    let size: CGSize
    let originalValue: String
    let exampleText: String
    
    var element: AXUIElement {
        elementRef.takeUnretainedValue()
    }
    
    // MARK: - Initialization
    
    /// Creates a new InputFieldInfo with the given accessibility element.
    /// - Parameters:
    ///   - element: The AXUIElement representing the input field
    ///   - position: The screen position of the field
    ///   - size: The size of the field
    ///   - originalValue: The current value in the field
    ///   - exampleText: The suggested example text
    init(element: AXUIElement, position: CGPoint, size: CGSize, originalValue: String, exampleText: String) {
        self.elementRef = Unmanaged.passRetained(element)
        self.position = position
        self.size = size
        self.originalValue = originalValue
        self.exampleText = exampleText
    }
    
    deinit {
        elementRef.release()
    }
    
    // MARK: - Public Methods
    
    /// Returns a retained copy of the element that the caller is responsible for releasing.
    func retainElement() -> AXUIElement {
        elementRef.retain().takeUnretainedValue()
    }
}


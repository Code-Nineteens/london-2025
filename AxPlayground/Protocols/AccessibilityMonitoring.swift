//
//  AccessibilityMonitoring.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Foundation

/// Protocol defining the accessibility monitoring interface.
protocol AccessibilityMonitoring: ObservableObject {
    var hasPermission: Bool { get }
    var events: [AccessibilityEvent] { get }
    var currentInputField: InputFieldInfo? { get }
    var showOverlay: Bool { get }
    var uniqueAppNames: [String] { get }
    
    func checkPermission()
    func requestPermission()
    func startMonitoring()
    func stopMonitoring()
    func clearEvents()
    func hideOverlay()
}


//
//  AccessibilityEvent.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import Foundation

/// Represents a captured accessibility event from user interaction.
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


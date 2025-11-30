//
//  SiriOrb.swift
//  AxPlayground
//
//  Glowing Edge Ring Orb (Transparent Center) - Sharp Version
//

import SwiftUI
import Foundation

@available(macOS 15.0, *)
struct SiriOrbMesh: View {
    let size: CGFloat
    let isActive: Bool
    
    @State private var rotation: Double = 0
    @State private var pulse: Double = 1.0
    
    var body: some View {
        ZStack {
            // 1. Background Ambient Glow (Wide & Soft)
            // This provides the "atmosphere" without pixelating the main ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.4,
                        endRadius: size * 1.2
                    )
                )
                .frame(width: size * 2.4, height: size * 2.4)
                .blur(radius: size * 0.3)
            
            // 2. Inner Glow (Softness inside the ring)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.4, blue: 0.2), // Orange
                            Color(red: 1.0, green: 0.1, blue: 0.6), // Pink
                            Color(red: 0.8, green: 0.1, blue: 0.9), // Magenta
                            Color(red: 0.2, green: 0.6, blue: 1.0), // Cyan
                            Color(red: 0.8, green: 0.1, blue: 0.9), // Magenta
                            Color(red: 1.0, green: 0.1, blue: 0.6), // Pink
                            Color(red: 1.0, green: 0.4, blue: 0.2)  // Orange
                        ],
                        center: .center,
                        startAngle: .degrees(-90 + rotation),
                        endAngle: .degrees(270 + rotation)
                    ),
                    lineWidth: size * 0.2
                )
                .blur(radius: size * 0.15) // Blurry backing for the ring
                .opacity(0.7)
                .frame(width: size, height: size)
            
            // 3. MAIN SHARP RING (The crisp definition)
            // No blur here! This ensures high-quality edges
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.5, blue: 0.3), // Light Orange
                            Color(red: 1.0, green: 0.2, blue: 0.7), // Bright Pink
                            Color(red: 0.9, green: 0.2, blue: 1.0), // Bright Magenta
                            Color(red: 0.3, green: 0.7, blue: 1.0), // Bright Cyan
                            Color(red: 0.9, green: 0.2, blue: 1.0), // Bright Magenta
                            Color(red: 1.0, green: 0.2, blue: 0.7), // Bright Pink
                            Color(red: 1.0, green: 0.5, blue: 0.3)  // Light Orange
                        ],
                        center: .center,
                        startAngle: .degrees(-90 + rotation),
                        endAngle: .degrees(270 + rotation)
                    ),
                    lineWidth: size * 0.12 // Slightly thinner than glow
                )
                .frame(width: size, height: size)
                // High quality, no blur
            
            // 4. Inner Rim Highlight (Sharp white-ish edge for glass effect)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.6)
                        ],
                        center: .center,
                        startAngle: .degrees(rotation * 2),
                        endAngle: .degrees(rotation * 2 + 360)
                    ),
                    lineWidth: 1
                )
                .frame(width: size - size * 0.12, height: size - size * 0.12)
                .opacity(0.5)
        }
        .scaleEffect(pulse)
        .onAppear {
            if isActive { startAnimation() }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue { startAnimation() } else { stopAnimation() }
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulse = 1.05
        }
    }
    
    private func stopAnimation() {
        withAnimation {
            rotation = 0
            pulse = 1.0
        }
    }
}

// MARK: - Compact Version

struct SiriOrbCompact: View {
    let size: CGFloat
    let isActive: Bool
    
    var body: some View {
        if #available(macOS 15.0, *) {
            SiriOrbMesh(size: size, isActive: isActive)
        } else {
            Circle()
                .strokeBorder(Color.purple, lineWidth: 3)
                .frame(width: size, height: size)
        }
    }
}

#Preview("Sharp Ring Orb") {
    ZStack {
        Color.black.ignoresSafeArea()
        if #available(macOS 15.0, *) {
            SiriOrbMesh(size: 50, isActive: true)
        }
    }
    .frame(width: 100, height: 100)
}

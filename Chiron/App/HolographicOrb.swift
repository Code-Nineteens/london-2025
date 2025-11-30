//
//  HolographicOrb.swift
//  AxPlayground
//
//  Beautiful holographic orb/bubble effect for AI activity indicator
//

import SwiftUI

struct HolographicOrb: View {
    let size: CGFloat
    @Binding var isActive: Bool
    
    @State private var rotation: Double = 0
    @State private var innerRotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -1
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(isActive ? 0.4 : 0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 8)
                .scaleEffect(pulse)
            
            // Main orb
            ZStack {
                // Deep blue/purple core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.2, green: 0.1, blue: 0.5),
                                Color(red: 0.1, green: 0.05, blue: 0.3),
                                Color(red: 0.05, green: 0.02, blue: 0.15)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
                
                // Inner swirl effect
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.cyan.opacity(0.3),
                                Color.blue.opacity(0.2),
                                Color.purple.opacity(0.3),
                                Color.blue.opacity(0.3)
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        )
                    )
                    .rotationEffect(.degrees(innerRotation))
                    .blur(radius: 3)
                    .opacity(0.6)
                
                // Holographic rainbow rim
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.8),  // Red/pink
                                Color(red: 1.0, green: 0.6, blue: 0.3).opacity(0.6),  // Orange
                                Color(red: 0.3, green: 1.0, blue: 0.5).opacity(0.7),  // Green
                                Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.8),  // Cyan
                                Color(red: 0.5, green: 0.3, blue: 1.0).opacity(0.7),  // Purple
                                Color(red: 1.0, green: 0.3, blue: 0.6).opacity(0.8),  // Pink
                                Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.8)   // Back to red
                            ],
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: size * 0.12
                    )
                    .blur(radius: 1.5)
                
                // Inner highlight (top-left light reflection)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.3, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.3
                        )
                    )
                
                // Bottom green/cyan reflection
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.2, green: 1.0, blue: 0.6).opacity(0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.5, height: size * 0.3)
                    .offset(x: -size * 0.1, y: size * 0.25)
                    .blur(radius: 4)
                
                // Shimmer effect (moving highlight)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: UnitPoint(x: shimmerOffset, y: 0),
                            endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 1)
                        )
                    )
                    .blur(radius: 2)
                
                // Glass edge highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.1),
                                Color.clear,
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: Color.purple.opacity(0.3), radius: 10, y: 5)
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimations()
            }
        }
    }
    
    private func startAnimations() {
        // Slow rotation for rainbow rim
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        
        // Faster inner swirl
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            innerRotation = -360
        }
        
        // Pulse effect
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            pulse = isActive ? 1.1 : 1.0
        }
        
        // Shimmer sweep
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.5
        }
    }
}

// MARK: - Compact version for the pill

struct HolographicOrbCompact: View {
    let size: CGFloat
    let isActive: Bool
    
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.purple.opacity(0.5),
                                Color.blue.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.2,
                            endRadius: size * 0.8
                        )
                    )
                    .frame(width: size * 1.5, height: size * 1.5)
                    .blur(radius: 4)
                    .scaleEffect(pulse)
            }
            
            // Orb
            ZStack {
                // Core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.3, green: 0.2, blue: 0.6),
                                Color(red: 0.15, green: 0.08, blue: 0.35),
                                Color(red: 0.08, green: 0.04, blue: 0.2)
                            ],
                            center: UnitPoint(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: size * 0.6
                        )
                    )
                
                // Rainbow rim
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.pink.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.green.opacity(0.6),
                                Color.cyan.opacity(0.7),
                                Color.purple.opacity(0.6),
                                Color.pink.opacity(0.7)
                            ],
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: size * 0.1
                    )
                    .blur(radius: 1)
                
                // Highlight
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.3, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                
                // Bottom reflection
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.green.opacity(0.4),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.4, y: 0.8),
                            startRadius: 0,
                            endRadius: size * 0.2
                        )
                    )
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = 1.15
            }
        }
    }
}

// MARK: - Preview

#Preview("Holographic Orb") {
    ZStack {
        Color(white: 0.9)
            .ignoresSafeArea()
        
        VStack(spacing: 40) {
            HolographicOrb(size: 120, isActive: .constant(true))
            
            HStack(spacing: 30) {
                HolographicOrbCompact(size: 28, isActive: true)
                HolographicOrbCompact(size: 28, isActive: false)
            }
        }
    }
}


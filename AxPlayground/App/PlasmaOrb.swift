//
//  PlasmaOrb.swift
//  AxPlayground
//
//  Plasma/energy orb with flowing organic light tendrils
//

import SwiftUI
import Combine

// MARK: - Plasma Orb View

struct PlasmaOrb: View {
    let size: CGFloat
    let isActive: Bool
    
    @State private var time: Double = 0
    @State private var phase1: Double = 0
    @State private var phase2: Double = 0
    @State private var phase3: Double = 0
    
    private let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.4, green: 0.3, blue: 0.9).opacity(isActive ? 0.5 : 0.2),
                            Color(red: 0.2, green: 0.1, blue: 0.5).opacity(0.3),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: 15)
            
            // Main orb with plasma effect
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.9
                
                // Draw multiple plasma layers
                drawPlasmaLayer(context: context, center: center, radius: radius, phase: phase1, color1: Color(red: 0.3, green: 0.5, blue: 1.0), color2: Color(red: 0.6, green: 0.3, blue: 0.9), opacity: 0.6, frequency: 3)
                
                drawPlasmaLayer(context: context, center: center, radius: radius * 0.95, phase: phase2, color1: Color(red: 0.8, green: 0.4, blue: 0.9), color2: Color(red: 0.4, green: 0.6, blue: 1.0), opacity: 0.5, frequency: 4)
                
                drawPlasmaLayer(context: context, center: center, radius: radius * 0.9, phase: phase3, color1: Color(red: 0.5, green: 0.7, blue: 1.0), color2: Color(red: 0.9, green: 0.5, blue: 0.8), opacity: 0.4, frequency: 5)
                
                // Inner glow
                let innerGlow = Path(ellipseIn: CGRect(
                    x: center.x - radius * 0.6,
                    y: center.y - radius * 0.6,
                    width: radius * 1.2,
                    height: radius * 1.2
                ))
                context.fill(innerGlow, with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.5, green: 0.6, blue: 1.0).opacity(0.3),
                        Color.clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius * 0.6
                ))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .blur(radius: 0.5)
            
            // Highlight tendrils overlay
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.85
                
                // Bright highlight tendrils
                drawTendril(context: context, center: center, radius: radius, phase: phase1 * 1.2, color: .white, opacity: 0.4, width: 2)
                drawTendril(context: context, center: center, radius: radius * 0.8, phase: phase2 * 0.8, color: .white, opacity: 0.3, width: 1.5)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .blur(radius: 1)
            
            // Glass rim
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size - 2, height: size - 2)
        }
        .onReceive(timer) { _ in
            if isActive {
                time += 0.016
                withAnimation(.linear(duration: 0.016)) {
                    phase1 = time * 0.5
                    phase2 = time * 0.7
                    phase3 = time * 0.3
                }
            }
        }
    }
    
    // MARK: - Drawing Functions
    
    private func drawPlasmaLayer(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        phase: Double,
        color1: Color,
        color2: Color,
        opacity: Double,
        frequency: Double
    ) {
        let path = createPlasmaBlobPath(center: center, radius: radius, phase: phase, frequency: frequency)
        
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [color1.opacity(opacity), color2.opacity(opacity)]),
                startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius)
            ),
            lineWidth: 2
        )
        
        // Add glow
        var glowContext = context
        glowContext.addFilter(.blur(radius: 4))
        glowContext.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [color1.opacity(opacity * 0.5), color2.opacity(opacity * 0.5)]),
                startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius)
            ),
            lineWidth: 4
        )
    }
    
    private func drawTendril(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        phase: Double,
        color: Color,
        opacity: Double,
        width: CGFloat
    ) {
        let path = createTendrilPath(center: center, radius: radius, phase: phase)
        
        context.stroke(
            path,
            with: .color(color.opacity(opacity)),
            lineWidth: width
        )
    }
    
    private func createPlasmaBlobPath(center: CGPoint, radius: CGFloat, phase: Double, frequency: Double) -> Path {
        var path = Path()
        let points = 60
        
        for i in 0...points {
            let angle = (Double(i) / Double(points)) * 2 * .pi
            
            // Multiple noise layers for organic look
            let noise1 = sin(angle * frequency + phase) * 0.15
            let noise2 = sin(angle * (frequency + 2) - phase * 1.3) * 0.1
            let noise3 = cos(angle * (frequency - 1) + phase * 0.7) * 0.08
            
            let r = radius * (1 + noise1 + noise2 + noise3)
            
            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
    
    private func createTendrilPath(center: CGPoint, radius: CGFloat, phase: Double) -> Path {
        var path = Path()
        
        // Create flowing tendril
        let startAngle = phase
        let segments = 40
        
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let angle = startAngle + t * .pi * 1.5
            
            let wobble = sin(t * 8 + phase * 2) * 0.2
            let r = radius * (0.3 + t * 0.6 + wobble * 0.1)
            
            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

// MARK: - Compact Version for Menu Bar (Organic plasma tendrils)

struct PlasmaOrbCompact: View {
    let size: CGFloat
    let isActive: Bool
    
    @State private var phase: Double = 0
    
    private let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.4, green: 0.45, blue: 0.9).opacity(0.25),
                                Color(red: 0.3, green: 0.2, blue: 0.6).opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size * 1.3, height: size * 1.3)
                    .blur(radius: 4)
            }
            
            // Plasma tendrils
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let maxRadius = min(canvasSize.width, canvasSize.height) / 2 * 0.9
                
                if isActive {
                    // Draw many overlapping organic curves
                    let tendrilCount = 12
                    
                    for i in 0..<tendrilCount {
                        let basePhase = phase + Double(i) * 0.3
                        let angleOffset = Double(i) * (.pi * 2 / Double(tendrilCount))
                        
                        // Color varies by tendril
                        let hue = Double(i) / Double(tendrilCount)
                        let color1: Color
                        let color2: Color
                        
                        if hue < 0.33 {
                            // Blue range
                            color1 = Color(red: 0.3 + hue, green: 0.5 + hue * 0.3, blue: 1.0)
                            color2 = Color(red: 0.5, green: 0.6, blue: 0.95)
                        } else if hue < 0.66 {
                            // Purple range
                            color1 = Color(red: 0.6 + (hue - 0.33) * 0.5, green: 0.35, blue: 0.95)
                            color2 = Color(red: 0.8, green: 0.5, blue: 0.9)
                        } else {
                            // Pink/white range
                            color1 = Color(red: 0.85, green: 0.6, blue: 0.95)
                            color2 = Color(red: 0.95, green: 0.85, blue: 1.0)
                        }
                        
                        // Create organic flowing tendril
                        let path = createTendrilPath(
                            center: center,
                            maxRadius: maxRadius,
                            phase: basePhase,
                            angleOffset: angleOffset,
                            seed: i
                        )
                        
                        let opacity = 0.4 + sin(basePhase * 0.5) * 0.2
                        let lineWidth: CGFloat = 1.0 + CGFloat(i % 3) * 0.5
                        
                        // Glow layer
                        var glowCtx = context
                        glowCtx.addFilter(.blur(radius: 4))
                        glowCtx.stroke(path, with: .linearGradient(
                            Gradient(colors: [color1.opacity(opacity * 0.4), color2.opacity(opacity * 0.4)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                        ), style: StrokeStyle(lineWidth: lineWidth * 4, lineCap: .round, lineJoin: .round))
                        
                        // Main stroke
                        context.stroke(path, with: .linearGradient(
                            Gradient(colors: [color1.opacity(opacity), color2.opacity(opacity)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                        ), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        
                        // Bright core on some tendrils
                        if i % 3 == 0 {
                            context.stroke(path, with: .color(Color.white.opacity(opacity * 0.5)),
                                style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    
                    // Add some crossing inner tendrils
                    for i in 0..<6 {
                        let innerPhase = phase * 1.3 + Double(i) * 0.5
                        let path = createInnerTendrilPath(
                            center: center,
                            maxRadius: maxRadius * 0.7,
                            phase: innerPhase,
                            seed: i + 100
                        )
                        
                        let color = Color(red: 0.7 + Double(i % 3) * 0.1, green: 0.75, blue: 1.0)
                        
                        var glowCtx = context
                        glowCtx.addFilter(.blur(radius: 2))
                        glowCtx.stroke(path, with: .color(color.opacity(0.3)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        
                        context.stroke(path, with: .color(color.opacity(0.5)),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                    
                } else {
                    // Idle - subtle static shape
                    let path = createTendrilPath(center: center, maxRadius: maxRadius * 0.5, phase: 0, angleOffset: 0, seed: 0)
                    context.stroke(path, with: .color(Color.white.opacity(0.15)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
            }
            .frame(width: size, height: size)
        }
        .onReceive(timer) { _ in
            if isActive {
                phase += 0.025
            }
        }
    }
    
    // Creates a flowing, organic tendril that loops around
    private func createTendrilPath(center: CGPoint, maxRadius: CGFloat, phase: Double, angleOffset: Double, seed: Int) -> Path {
        var path = Path()
        let points = 50
        let seedOffset = Double(seed) * 1.7
        
        for i in 0...points {
            let t = Double(i) / Double(points)
            let angle = angleOffset + t * .pi * 2
            
            // Multiple noise frequencies for organic look
            let noise1 = sin(angle * 3 + phase + seedOffset) * 0.3
            let noise2 = cos(angle * 5 - phase * 0.7 + seedOffset * 0.5) * 0.2
            let noise3 = sin(angle * 2 + phase * 1.5 + seedOffset * 0.3) * 0.15
            let noise4 = cos(angle * 7 - phase * 0.3) * 0.1
            
            // Radius varies organically
            let radiusFactor = 0.4 + noise1 + noise2 + noise3 + noise4
            let r = maxRadius * max(0.2, min(1.0, radiusFactor))
            
            // Add some wobble to the angle too
            let angleWobble = sin(angle * 4 + phase * 0.8 + seedOffset) * 0.15
            let finalAngle = angle + angleWobble
            
            let x = center.x + cos(finalAngle) * r
            let y = center.y + sin(finalAngle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
    
    // Creates smaller inner crossing tendrils
    private func createInnerTendrilPath(center: CGPoint, maxRadius: CGFloat, phase: Double, seed: Int) -> Path {
        var path = Path()
        let points = 30
        let seedOffset = Double(seed) * 2.3
        let startAngle = seedOffset + phase * 0.5
        
        for i in 0...points {
            let t = Double(i) / Double(points)
            let angle = startAngle + t * .pi * 1.5  // Partial arc, not full circle
            
            let noise1 = sin(angle * 4 + phase * 1.2 + seedOffset) * 0.35
            let noise2 = cos(angle * 3 - phase + seedOffset * 0.7) * 0.25
            
            let r = maxRadius * (0.3 + t * 0.5 + noise1 + noise2)
            
            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

// MARK: - Preview

#Preview("Plasma Orb") {
    ZStack {
        Color(red: 0.08, green: 0.08, blue: 0.12)
            .ignoresSafeArea()
        
        VStack(spacing: 50) {
            PlasmaOrb(size: 200, isActive: true)
            
            HStack(spacing: 30) {
                PlasmaOrbCompact(size: 32, isActive: true)
                PlasmaOrbCompact(size: 32, isActive: false)
            }
        }
    }
}


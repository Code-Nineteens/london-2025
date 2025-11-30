//
//  DesignSystem.swift
//  AxPlayground
//
//  A unified design system for a next-level AI app aesthetic.
//  Inspired by: Linear, Raycast, Arc Browser, Notion
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    
    // Primary brand colors - Deep purple/violet with electric accents
    static let axPrimary = Color(hex: "8B5CF6")        // Vibrant violet
    static let axPrimaryLight = Color(hex: "A78BFA")   // Lighter violet
    static let axPrimaryDark = Color(hex: "6D28D9")    // Deep violet
    
    // Accent colors for highlights and CTAs
    static let axAccent = Color(hex: "06B6D4")         // Cyan/teal
    static let axAccentGlow = Color(hex: "22D3EE")     // Bright cyan
    
    // Success, Warning, Error states
    static let axSuccess = Color(hex: "10B981")        // Emerald green
    static let axWarning = Color(hex: "F59E0B")        // Amber
    static let axError = Color(hex: "EF4444")          // Red
    
    // Neutral palette - Cool grays with slight blue tint
    static let axBackground = Color(hex: "09090B")     // Near black
    static let axSurface = Color(hex: "18181B")        // Dark surface
    static let axSurfaceElevated = Color(hex: "27272A") // Elevated surface
    static let axBorder = Color(hex: "3F3F46")         // Subtle border
    static let axBorderLight = Color(hex: "52525B")    // Lighter border
    
    // Text colors
    static let axTextPrimary = Color(hex: "FAFAFA")    // Almost white
    static let axTextSecondary = Color(hex: "A1A1AA")  // Muted
    static let axTextTertiary = Color(hex: "71717A")   // Very muted
    
    // Gradient stops for glass effects
    static let axGlassLight = Color.white.opacity(0.08)
    static let axGlassBorder = Color.white.opacity(0.12)
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

struct AXTypography {
    // Display - Hero text
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
    
    // Headings
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let headlineMedium = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let headlineSmall = Font.system(size: 13, weight: .semibold, design: .rounded)
    
    // Body text
    static let bodyLarge = Font.system(size: 14, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
    
    // Labels and captions
    static let labelLarge = Font.system(size: 12, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)
    
    // Monospace for code/data
    static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Spacing

struct AXSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius

struct AXRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let pill: CGFloat = 999
}

// MARK: - Gradients

struct AXGradients {
    // Primary brand gradient
    static let primary = LinearGradient(
        colors: [.axPrimary, .axPrimaryDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Accent gradient for CTAs
    static let accent = LinearGradient(
        colors: [.axAccent, .axPrimary],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Glow effect gradient
    static let glow = LinearGradient(
        colors: [.axPrimary.opacity(0.6), .axAccent.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Glass border gradient
    static let glassBorder = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.2), location: 0),
            .init(color: .white.opacity(0.08), location: 0.3),
            .init(color: .clear, location: 0.6),
            .init(color: .white.opacity(0.05), location: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Mesh-like background gradient
    static let meshBackground = LinearGradient(
        colors: [
            .axBackground,
            Color(hex: "0F0A1A"),
            .axBackground
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

struct AXCardStyle: ViewModifier {
    var isElevated: Bool = false
    var hasBorder: Bool = true
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AXRadius.lg, style: .continuous)
                    .fill(isElevated ? Color.axSurfaceElevated : Color.axSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AXRadius.lg, style: .continuous)
                    .stroke(hasBorder ? Color.axBorder : .clear, lineWidth: 1)
            )
    }
}

struct AXGlassCard: ViewModifier {
    var cornerRadius: CGFloat = AXRadius.lg
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.axGlassLight)
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AXGradients.glassBorder, lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
    }
}

struct AXPrimaryButton: ViewModifier {
    var isCompact: Bool = false
    
    func body(content: Content) -> some View {
        content
            .font(isCompact ? AXTypography.labelMedium : AXTypography.labelLarge)
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? AXSpacing.md : AXSpacing.lg)
            .padding(.vertical, isCompact ? AXSpacing.sm : AXSpacing.md)
            .background(
                Capsule()
                    .fill(AXGradients.primary)
            )
            .shadow(color: .axPrimary.opacity(0.4), radius: 12, x: 0, y: 4)
    }
}

struct AXSecondaryButton: ViewModifier {
    var isCompact: Bool = false
    
    func body(content: Content) -> some View {
        content
            .font(isCompact ? AXTypography.labelMedium : AXTypography.labelLarge)
            .foregroundStyle(.axTextPrimary)
            .padding(.horizontal, isCompact ? AXSpacing.md : AXSpacing.lg)
            .padding(.vertical, isCompact ? AXSpacing.sm : AXSpacing.md)
            .background(
                Capsule()
                    .fill(Color.axSurfaceElevated)
            )
            .overlay(
                Capsule()
                    .stroke(Color.axBorder, lineWidth: 1)
            )
    }
}

struct AXGhostButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AXTypography.labelMedium)
            .foregroundStyle(.axTextSecondary)
            .padding(.horizontal, AXSpacing.md)
            .padding(.vertical, AXSpacing.sm)
            .background(
                Capsule()
                    .fill(Color.clear)
            )
            .contentShape(Capsule())
    }
}

// MARK: - View Extensions

extension View {
    func axCard(elevated: Bool = false, border: Bool = true) -> some View {
        modifier(AXCardStyle(isElevated: elevated, hasBorder: border))
    }
    
    func axGlassCard(cornerRadius: CGFloat = AXRadius.lg) -> some View {
        modifier(AXGlassCard(cornerRadius: cornerRadius))
    }
    
    func axPrimaryButton(compact: Bool = false) -> some View {
        modifier(AXPrimaryButton(isCompact: compact))
    }
    
    func axSecondaryButton(compact: Bool = false) -> some View {
        modifier(AXSecondaryButton(isCompact: compact))
    }
    
    func axGhostButton() -> some View {
        modifier(AXGhostButton())
    }
}

// MARK: - Status Badge Component

struct AXStatusBadge: View {
    enum Status {
        case active, idle, warning, error, success
        
        var color: Color {
            switch self {
            case .active: return .axAccent
            case .idle: return .axTextTertiary
            case .warning: return .axWarning
            case .error: return .axError
            case .success: return .axSuccess
            }
        }
        
        var icon: String {
            switch self {
            case .active: return "bolt.fill"
            case .idle: return "circle"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }
    
    let status: Status
    let label: String?
    
    init(_ status: Status, label: String? = nil) {
        self.status = status
        self.label = label
    }
    
    var body: some View {
        HStack(spacing: AXSpacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .shadow(color: status.color.opacity(0.6), radius: 4)
            
            if let label {
                Text(label)
                    .font(AXTypography.labelSmall)
                    .foregroundStyle(.axTextSecondary)
            }
        }
        .padding(.horizontal, AXSpacing.sm)
        .padding(.vertical, AXSpacing.xs)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
    }
}

// MARK: - Icon Button Component

struct AXIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 28
    var isDestructive: Bool = false
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(isDestructive ? .axError : .axTextSecondary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isHovered ? Color.axSurfaceElevated : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Animated Gradient Border

struct AXAnimatedBorder: View {
    @State private var rotation: Double = 0
    var cornerRadius: CGFloat = AXRadius.lg
    var lineWidth: CGFloat = 1.5
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                AngularGradient(
                    colors: [
                        .axPrimary,
                        .axAccent,
                        .axPrimaryLight,
                        .axPrimary
                    ],
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: lineWidth
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Pulsing Glow Effect

struct AXPulsingGlow: ViewModifier {
    @State private var isPulsing = false
    var color: Color = .axPrimary
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(isPulsing ? 0.6 : 0.3),
                radius: isPulsing ? 16 : 8
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func axPulsingGlow(color: Color = .axPrimary) -> some View {
        modifier(AXPulsingGlow(color: color))
    }
}



//
//  GlassNotificationView.swift
//  AxPlayground
//
//  Redesigned notification with next-level AI aesthetic.
//

import SwiftUI

struct GlassNotificationView: View {
    let title: String
    let message: String?
    let icon: String?
    let onClose: (() -> Void)?
    var onAddToQueue: (() -> Void)? = nil
    var onInsertNow: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    var actionButtonTitle: String = "Execute"
    var actionButtonIcon: String = "sparkles"
    
    @State private var isHovering = false
    @State private var appearAnimation = false
    @State private var glowPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: AXSpacing.md) {
            // Header with icon and title
            HStack(spacing: AXSpacing.md) {
                // Animated icon with gradient glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(Color.axPrimary.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .blur(radius: glowPulse ? 8 : 4)
                    
                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.axPrimary.opacity(0.3),
                                    Color.axAccent.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.axPrimaryLight, .axAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse, options: .repeating, value: appearAnimation)
                    }
                }
                
                VStack(alignment: .leading, spacing: AXSpacing.xxs) {
                    Text(title)
                        .font(AXTypography.headlineSmall)
                        .foregroundColor(Color.axTextPrimary)
                    
                    if let message {
                        Text(message)
                            .font(AXTypography.bodySmall)
                            .foregroundColor(Color.axTextSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Close button
                Button {
                    onReject?()
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.axTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.axSurfaceElevated)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.6)
            }

            // Action buttons
            HStack(spacing: AXSpacing.sm) {
                // Primary action button
                Button {
                    onInsertNow?()
                    onClose?()
                } label: {
                    HStack(spacing: AXSpacing.xs) {
                        Image(systemName: actionButtonIcon)
                            .font(.system(size: 12, weight: .medium))
                        Text(actionButtonTitle)
                            .font(AXTypography.labelMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AXSpacing.lg)
                    .padding(.vertical, AXSpacing.sm)
                    .background(
                        Capsule()
                            .fill(AXGradients.primary)
                    )
                    .shadow(color: .axPrimary.opacity(0.4), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                
                // Secondary action (if available)
                if onAddToQueue != nil {
                    Button {
                        onAddToQueue?()
                        onClose?()
                    } label: {
                        HStack(spacing: AXSpacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12, weight: .medium))
                            Text("Queue")
                                .font(AXTypography.labelMedium)
                        }
                        .foregroundColor(Color.axTextPrimary)
                        .padding(.horizontal, AXSpacing.md)
                        .padding(.vertical, AXSpacing.sm)
                        .background(
                            Capsule()
                                .fill(Color.axSurfaceElevated)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.axBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AXSpacing.lg)
        .frame(minWidth: 280, maxWidth: 360)
        .fixedSize()
        .background(
            ZStack {
                // Main glass background
                RoundedRectangle(cornerRadius: AXRadius.xl)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: AXRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.axPrimary.opacity(0.05),
                                Color.clear,
                                Color.axAccent.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border with gradient
                RoundedRectangle(cornerRadius: AXRadius.xl)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.axPrimary.opacity(0.4), location: 0),
                                .init(color: Color.white.opacity(0.15), location: 0.3),
                                .init(color: Color.clear, location: 0.6),
                                .init(color: Color.axAccent.opacity(0.2), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.axPrimary.opacity(0.15), radius: 30, x: 0, y: 15)
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                appearAnimation = true
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
}

// MARK: - Liquid Glass Modifier (Updated)

extension View {
    @ViewBuilder
    func liquidGlass() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: AXRadius.xxl))
        } else {
            self
                .background {
                    ZStack {
                        // Base blur material
                        RoundedRectangle(cornerRadius: AXRadius.xxl, style: .continuous)
                            .fill(.ultraThinMaterial)
                        
                        // Subtle color tint
                        RoundedRectangle(cornerRadius: AXRadius.xxl, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.axPrimary.opacity(0.08),
                                        Color.axAccent.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Top specular highlight
                        RoundedRectangle(cornerRadius: AXRadius.xxl, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.4), location: 0),
                                        .init(color: .white.opacity(0.15), location: 0.03),
                                        .init(color: .white.opacity(0.05), location: 0.1),
                                        .init(color: .clear, location: 0.4)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner glow border
                        RoundedRectangle(cornerRadius: AXRadius.xxl, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.axPrimary.opacity(0.5), location: 0),
                                        .init(color: .white.opacity(0.2), location: 0.2),
                                        .init(color: .white.opacity(0.05), location: 0.5),
                                        .init(color: Color.axAccent.opacity(0.3), location: 1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .shadow(color: .axPrimary.opacity(0.1), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.axBackground
            .ignoresSafeArea()
        
        GlassNotificationView(
            title: "AI Suggestion",
            message: "I detected you're writing an email. Would you like me to help compose it?",
            icon: "wand.and.stars",
            onClose: {},
            onAddToQueue: {},
            onInsertNow: {}
        )
    }
}

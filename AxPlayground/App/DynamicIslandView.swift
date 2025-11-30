//
//  DynamicIslandView.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//  Redesigned with next-level AI aesthetic.
//

import SwiftUI

struct DynamicIslandView: View {
    let title: String
    let message: String?
    let icon: String?
    let onClose: (() -> Void)?
    var onInsertNow: (() -> Void)? = nil
    var actionButtonTitle: String = "Execute"
    var actionButtonIcon: String = "sparkles"

    @Binding var isVisible: Bool

    @State private var isHovering = false
    @State private var animationProgress: CGFloat = 0.0
    @State private var contentOpacity: CGFloat = 0.0
    @State private var glowIntensity: CGFloat = 0.3

    // Dimensions
    private let expandedWidth: CGFloat = 400
    private let expandedHeight: CGFloat = 180
    private let collapsedWidth: CGFloat = 180
    private let collapsedHeight: CGFloat = 32
    private let cornerRadius: CGFloat = 32

    private var currentWidth: CGFloat {
        collapsedWidth + (expandedWidth - collapsedWidth) * animationProgress
    }

    private var currentHeight: CGFloat {
        collapsedHeight + (expandedHeight - collapsedHeight) * animationProgress
    }

    private var currentCornerRadius: CGFloat {
        16 + (cornerRadius - 16) * animationProgress
    }

    private var currentTopInvertedRadius: CGFloat {
        cornerRadius * animationProgress
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background with glow effect
            ZStack {
                // Outer glow
                DynamicIslandShape(
                    bottomCornerRadius: currentCornerRadius,
                    topInvertedRadius: currentTopInvertedRadius
                )
                .fill(Color.axPrimary.opacity(0.15 * animationProgress))
                .blur(radius: 20)
                .frame(width: currentWidth + (currentTopInvertedRadius * 2) + 20, height: currentHeight + 10)
                
                // Main background
                DynamicIslandShape(
                    bottomCornerRadius: currentCornerRadius,
                    topInvertedRadius: currentTopInvertedRadius
                )
                .fill(Color.axBackground)
                .overlay(
                    // Gradient border
                    DynamicIslandShape(
                        bottomCornerRadius: currentCornerRadius,
                        topInvertedRadius: currentTopInvertedRadius
                    )
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.axPrimary.opacity(0.5 * animationProgress), location: 0),
                                .init(color: Color.axBorder.opacity(0.3), location: 0.3),
                                .init(color: Color.axAccent.opacity(0.3 * animationProgress), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.5 * animationProgress), radius: 20, x: 0, y: 10)
                .frame(width: currentWidth + (currentTopInvertedRadius * 2), height: currentHeight)
            }

            // Content
            expandedContent
                .frame(width: expandedWidth, height: expandedHeight)
                .opacity(contentOpacity)
        }
        .frame(width: expandedWidth + (cornerRadius * 2), height: expandedHeight, alignment: .top)
        .onHover { hovering in
            isHovering = hovering
            withAnimation(.easeInOut(duration: 0.3)) {
                glowIntensity = hovering ? 0.5 : 0.3
            }
        }
        .onAppear {
            // Animate island expansion
            withAnimation(.timingCurve(0.76, 0, 0.24, 1, duration: 0.5)) {
                animationProgress = 1.0
            }
            // Fade in content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.25)) {
                    contentOpacity = 1.0
                }
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                // Fade out content first
                withAnimation(.easeIn(duration: 0.15)) {
                    contentOpacity = 0.0
                }
                // Then collapse island
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.timingCurve(0.76, 0, 0.24, 1, duration: 0.3)) {
                        animationProgress = 0.0
                    }
                }
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: AXSpacing.lg) {
            // Header
            HStack(spacing: AXSpacing.md) {
                // Icon with glow
                if let icon {
                    ZStack {
                        Circle()
                            .fill(Color.axPrimary.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .blur(radius: 8)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.axPrimary.opacity(0.3), Color.axAccent.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.axPrimaryLight, .axAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }

                VStack(alignment: .leading, spacing: AXSpacing.xxs) {
                    Text(title)
                        .font(AXTypography.headlineMedium)
                        .foregroundStyle(.axTextPrimary)
                        .lineLimit(1)

                    if let message {
                        Text(message)
                            .font(AXTypography.bodySmall)
                            .foregroundStyle(.axTextSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // Close button
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.axTextTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.axSurfaceElevated)
                        )
                }
                .buttonStyle(.plain)
            }

            // Action button
            HStack {
                Spacer()

                Button {
                    onInsertNow?()
                    onClose?()
                } label: {
                    HStack(spacing: AXSpacing.sm) {
                        Image(systemName: actionButtonIcon)
                            .font(.system(size: 13, weight: .medium))
                        Text(actionButtonTitle)
                            .font(AXTypography.labelLarge)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AXSpacing.xl)
                    .padding(.vertical, AXSpacing.md)
                    .background(
                        Capsule()
                            .fill(AXGradients.primary)
                    )
                    .shadow(color: .axPrimary.opacity(0.5), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 70)
        .padding(.horizontal, AXSpacing.xl)
        .padding(.bottom, AXSpacing.xl)
    }
}

// MARK: - Dynamic Island Shape with Inverted Top Corners

struct DynamicIslandShape: Shape {
    var bottomCornerRadius: CGFloat
    var topInvertedRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomCornerRadius, topInvertedRadius) }
        set {
            bottomCornerRadius = newValue.first
            topInvertedRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let invertedRadius = topInvertedRadius
        let bottomRadius = bottomCornerRadius

        // Start from top-left inverted corner
        path.move(to: CGPoint(x: 0, y: 0))

        // Top-left inverted curve (concave)
        if invertedRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: invertedRadius, y: invertedRadius),
                control: CGPoint(x: invertedRadius, y: 0)
            )
        }

        // Left edge down to bottom-left corner
        path.addLine(to: CGPoint(x: invertedRadius, y: rect.height - bottomRadius))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: invertedRadius + bottomRadius, y: rect.height),
            control: CGPoint(x: invertedRadius, y: rect.height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.width - invertedRadius - bottomRadius, y: rect.height))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.width - invertedRadius, y: rect.height - bottomRadius),
            control: CGPoint(x: rect.width - invertedRadius, y: rect.height)
        )

        // Right edge up to top-right inverted corner
        path.addLine(to: CGPoint(x: rect.width - invertedRadius, y: invertedRadius))

        // Top-right inverted curve (concave)
        if invertedRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: 0),
                control: CGPoint(x: rect.width - invertedRadius, y: 0)
            )
        }

        // Top edge back to start
        path.addLine(to: CGPoint(x: 0, y: 0))

        return path
    }
}

#Preview {
    @Previewable @State var isVisible = true

    ZStack {
        Color.axBackground
            .ignoresSafeArea()

        VStack {
            DynamicIslandView(
                title: "AI Assistant",
                message: "Ready to help compose your email",
                icon: "wand.and.stars",
                onClose: {},
                isVisible: $isVisible
            )

            Spacer()
        }
    }
}

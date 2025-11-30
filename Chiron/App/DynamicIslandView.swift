//
//  DynamicIslandView.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

struct DynamicIslandView: View {
    let title: String
    let message: String?
    let icon: String?
    let onClose: (() -> Void)?
    var onInsertNow: (() -> Void)? = nil
    var actionButtonTitle: String = "Do it"
    var actionButtonIcon: String = "sparkles"

    @Binding var isVisible: Bool

    @State private var isHovering = false
    @State private var animationProgress: CGFloat = 0.0
    @State private var contentOpacity: CGFloat = 0.0

    // Dimensions
    private let expandedWidth: CGFloat = 380
    private let expandedHeight: CGFloat = 80
    private let collapsedWidth: CGFloat = 180  // MacBook notch width approx
    private let collapsedHeight: CGFloat = 32  // MacBook notch height approx
    private let cornerRadius: CGFloat = 28

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
            // Background with inverted top corners and rounded bottom corners
            DynamicIslandShape(
                bottomCornerRadius: currentCornerRadius,
                topInvertedRadius: currentTopInvertedRadius
            )
            .fill(.black)
            .shadow(color: .black.opacity(0.4 * animationProgress), radius: 16, x: 0, y: 8)
            .frame(width: currentWidth + (currentTopInvertedRadius * 2), height: currentHeight)

            // Content
            expandedContent
                .frame(width: expandedWidth, height: expandedHeight)
                .opacity(contentOpacity)
        }
        .frame(width: expandedWidth + (cornerRadius * 2), height: expandedHeight, alignment: .top)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            // First animate island
            withAnimation(.timingCurve(0.76, 0, 0.24, 1, duration: 0.4)) {
                animationProgress = 1.0
            }
            // Then fade in content after island is fully visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.2)) {
                    contentOpacity = 1.0
                }
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                // First fade out content
                withAnimation(.easeIn(duration: 0.15)) {
                    contentOpacity = 0.0
                }
                // Then hide island after content is hidden
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
        HStack(spacing: 12) {
            // Icon
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
            }

            // Single clean title text
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            // Action buttons
            HStack(spacing: 8) {
                // Primary action button
                if onInsertNow != nil {
                    Button {
                        onInsertNow?()
                        onClose?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: actionButtonIcon)
                                .font(.system(size: 10, weight: .medium))
                            Text(actionButtonTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Close/Dismiss button
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            DynamicIslandView(
                title: "New message from John",
                message: nil,
                icon: "message.fill",
                onClose: {},
                isVisible: $isVisible
            )

            Spacer()
        }
    }
}

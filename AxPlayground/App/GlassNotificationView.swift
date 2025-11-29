import SwiftUI

struct GlassNotificationView: View {
    let title: String
    let message: String?
    let icon: String?
    let onClose: (() -> Void)?
    var onAddToQueue: (() -> Void)? = nil
    var onInsertNow: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    
    @State private var isHovering = false
    @State private var appearAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with icon and title
            HStack(spacing: 12) {
                // Animated icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.3),
                                    Color.purple.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse, options: .repeating, value: appearAnimation)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if let message {
                        Text(message)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.6)
            }

            // Action buttons
            HStack(spacing: 10) {
                // Add to Queue button
                Button {
                    onAddToQueue?()
                    onClose?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("Queue")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.primary.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                
                // Insert Now button (primary action)
                Button {
                    onInsertNow?()
                    onClose?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                        Text("Insert Now")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue,
                                        Color.purple.opacity(0.9)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 300)
        .liquidGlass()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                appearAnimation = true
            }
        }
    }
}

// MARK: - Liquid Glass Modifier

extension View {
    @ViewBuilder
    func liquidGlass() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        } else {
            self
                .background {
                    ZStack {
                        // Base blur material
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                        
                        // Subtle color tint
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Top specular highlight - the "liquid" shine
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.6), location: 0),
                                        .init(color: .white.opacity(0.3), location: 0.03),
                                        .init(color: .white.opacity(0.1), location: 0.1),
                                        .init(color: .clear, location: 0.4)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner glow border
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.7), location: 0),
                                        .init(color: .white.opacity(0.3), location: 0.2),
                                        .init(color: .white.opacity(0.1), location: 0.5),
                                        .init(color: .white.opacity(0.2), location: 0.8),
                                        .init(color: .white.opacity(0.4), location: 1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                // Layered shadows for depth
                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
        }
    }
}

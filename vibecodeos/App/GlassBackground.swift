import SwiftUI

// MARK: - Glass Effect View Modifier

extension View {
    @ViewBuilder
    func glassedEffect(in shape: some Shape = RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background {
                shape.glassed()
            }
        }
    }
}

extension Shape {
    @ViewBuilder
    func glassed() -> some View {
        self
            .fill(.ultraThinMaterial)
        
        self
            .fill(
                .linearGradient(
                    colors: [
                        .primary.opacity(0.08),
                        .primary.opacity(0.05),
                        .primary.opacity(0.01),
                        .clear,
                        .clear,
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        
        self
            .stroke(.primary.opacity(0.2), lineWidth: 0.7)
    }
}

// MARK: - Glass Background View

struct GlassBackground: View {
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassed()
        }
    }
}

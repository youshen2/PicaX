import SwiftUI

extension View {
    @ViewBuilder
    func glassProminentIfAvailable(tint: Color = .blue) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassCardIfAvailable(
        tint: Color,
        cornerRadius: CGFloat,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                self.glassEffect(
                    .regular.tint(tint.opacity(0.14)),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                self.background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                }
            }
        } else {
            self
        }
    }
}

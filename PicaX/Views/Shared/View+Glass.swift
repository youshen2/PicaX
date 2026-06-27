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
}

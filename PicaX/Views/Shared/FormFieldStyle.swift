import SwiftUI

private struct FormFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

extension View {
    func formFieldStyle() -> some View {
        modifier(FormFieldStyle())
    }
}

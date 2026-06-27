import SwiftUI

extension View {
    @ViewBuilder
    func picaxPageTabViewStyle() -> some View {
        #if os(iOS)
        tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }
}

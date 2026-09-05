import SwiftUI

extension View {
    @ViewBuilder
    func picaxTabBarRoot() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            background(PicaxTabBarVisibilityBridge(hidden: false))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

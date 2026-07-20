import SwiftUI

extension View {
    @ViewBuilder
    func picaxReaderChrome(hidesNavigationBar: Bool, hidesStatusBar: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
                .statusBarHidden(hidesStatusBar)
                .persistentSystemOverlays(hidesStatusBar ? .automatic : .visible)
        } else {
            self
                .navigationBarHidden(hidesNavigationBar)
                .statusBarHidden(hidesStatusBar)
        }
        #else
        self
        #endif
    }
}

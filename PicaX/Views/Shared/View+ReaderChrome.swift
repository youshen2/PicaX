import SwiftUI

extension View {
    @ViewBuilder
    func picaxReaderChrome(hidesNavigationBar: Bool, hidesStatusBar: Bool) -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
            .statusBar(hidden: hidesStatusBar)
        #else
        self
        #endif
    }
}

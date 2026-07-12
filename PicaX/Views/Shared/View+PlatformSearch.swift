import SwiftUI

extension SearchFieldPlacement {
    static var picaxNavigationSearch: SearchFieldPlacement {
        #if os(macOS)
        .automatic
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

extension View {
    @ViewBuilder
    func picaxSearchFocused(_ binding: FocusState<Bool>.Binding) -> some View {
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            searchFocused(binding)
        } else {
            self
        }
    }
}

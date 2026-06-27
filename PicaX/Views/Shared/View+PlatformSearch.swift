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

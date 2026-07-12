import SwiftUI

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WatchHomePage()
                WatchFavoritesPage()
                WatchDiscoveryPage()
                WatchTagsPage()
            }
            .watchRootTabStyle()
        }
    }
}

private extension View {
    @ViewBuilder
    func watchRootTabStyle() -> some View {
        if #available(watchOS 10.0, *) {
            tabViewStyle(.verticalPage)
        } else {
            tabViewStyle(.page)
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchAccountSyncStore.preview)
}

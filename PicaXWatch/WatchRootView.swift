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
            .tabViewStyle(.verticalPage)
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchAccountSyncStore.preview)
}

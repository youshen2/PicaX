import SwiftUI

@main
struct PicaXWatchApp: App {
    @StateObject private var accountSyncStore = WatchAccountSyncStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(accountSyncStore)
                .task {
                    accountSyncStore.activate()
                }
        }
    }
}

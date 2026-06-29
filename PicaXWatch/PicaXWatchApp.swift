import SwiftUI

@main
struct PicaXWatchApp: App {
    @StateObject private var accountSyncStore = WatchAccountSyncStore()
    @StateObject private var downloadService = WatchDownloadService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(accountSyncStore)
                .environmentObject(downloadService)
                .task {
                    accountSyncStore.activate()
                    WatchImageCacheService.configure()
                    WatchComicDetailCacheService.configure()
                    downloadService.configure { platform in
                        accountSyncStore.snapshot.account(for: platform)
                    }
                }
        }
    }
}

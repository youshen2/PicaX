//
//  PicaXApp.swift
//  PicaX
//
//  Created by 洛汐聚合体 on 2026/6/26.
//

import SwiftUI

@main
struct PicaXApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var accountService = AccountService()
    @StateObject private var platformAccountService = PlatformAccountService()
    @StateObject private var readingHistoryService = ReadingHistoryService()
    @StateObject private var readingDurationService = ReadingDurationService()
    @StateObject private var downloadService = DownloadService()
    @StateObject private var blockingKeywordService = BlockingKeywordService()
    @StateObject private var searchHistoryService = SearchHistoryService()
    #if os(iOS)
    @StateObject private var phoneWatchAccountSyncService = PhoneWatchAccountSyncService()
    #endif

    var body: some Scene {
        WindowGroup {
            rootContent
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        let baseContent = ContentView()
                .environmentObject(appSettings)
                .environmentObject(accountService)
                .environmentObject(platformAccountService)
                .environmentObject(readingHistoryService)
                .environmentObject(readingDurationService)
                .environmentObject(downloadService)
                .environmentObject(blockingKeywordService)
                .environmentObject(searchHistoryService)
                .task {
                    ImageCacheService.configure()
                    ComicDetailCacheService.configure()
                    downloadService.configure { platform in
                        platformAccountService.account(for: platform)
                    }
                }

        #if os(iOS)
        baseContent
            .onAppear(perform: syncAccountsToWatch)
            .onChange(of: platformAccountService.accounts) { _, _ in
                syncAccountsToWatch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .picaxLocalFavoritesDidChange)) { _ in
                syncAccountsToWatch()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                syncAccountsToWatch()
            }
        #else
        baseContent
        #endif
    }

    #if os(iOS)
    private func syncAccountsToWatch() {
        phoneWatchAccountSyncService.sync(
            platformAccountService: platformAccountService,
            syncsLocalFavorites: WatchConnectivitySettings.syncsLocalFavorites()
        )
    }
    #endif
}

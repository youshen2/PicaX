//
//  PicaXApp.swift
//  PicaX
//
//  Created by 洛汐聚合体 on 2026/6/26.
//

import SwiftUI

@main
struct PicaXApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appSettings = AppSettings()
    @StateObject private var accountService = AccountService()
    @StateObject private var platformAccountService = PlatformAccountService()
    @StateObject private var readingHistoryService = ReadingHistoryService()
    @StateObject private var readLaterService = ReadLaterService()
    @StateObject private var readingDurationService = ReadingDurationService()
    @StateObject private var downloadService = DownloadService()
    @StateObject private var blockingKeywordService = BlockingKeywordService()
    @StateObject private var searchHistoryService = SearchHistoryService()
    @StateObject private var followUpdatesService = FollowUpdatesService()
    @StateObject private var webDAVSyncService = WebDAVSyncService()
    #if os(iOS)
    @StateObject private var phoneWatchAccountSyncService = PhoneWatchAccountSyncService()
    @AppStorage(WatchConnectivitySettingsKey.syncsLocalFavorites) private var syncsLocalFavorites = true
    @AppStorage(WatchConnectivitySettingsKey.syncsReadLater) private var syncsReadLater = true
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
                .environmentObject(readLaterService)
                .environmentObject(readingDurationService)
                .environmentObject(downloadService)
                .environmentObject(blockingKeywordService)
                .environmentObject(searchHistoryService)
                .environmentObject(followUpdatesService)
                .environmentObject(webDAVSyncService)
                .task {
                    Task.detached(priority: .utility) {
                        EhTagTranslationService.prepare()
                        NhentaiTagSuggestionService.prepare()
                    }
                    ImageCacheService.configure()
                    ComicDetailCacheService.configure()
                    downloadService.configure { platform in
                        platformAccountService.account(for: platform)
                    }
                    followUpdatesService.configure { platform in
                        platformAccountService.account(for: platform)
                    }
                    followUpdatesService.checkAutomaticallyIfNeeded()
                    await webDAVSyncService.synchronizeAutomaticallyIfNeeded()
                }
                .onChange(of: scenePhase) { newValue in
                    switch newValue {
                    case .active:
                        downloadService.applicationDidBecomeActive()
                        followUpdatesService.checkAutomaticallyIfNeeded()
                        Task {
                            await webDAVSyncService.synchronizeAutomaticallyIfNeeded()
                        }
                    case .background:
                        downloadService.applicationDidEnterBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .picaxLocalFavoritesDidChange)) { _ in
                    followUpdatesService.reload()
                }
                .onReceive(NotificationCenter.default.publisher(for: .picaxPlatformAccountsDidChange)) { _ in
                    platformAccountService.reloadFromDefaults()
                }
                .onReceive(NotificationCenter.default.publisher(for: .picaxBackupDidImport)) { _ in
                    reloadServicesAfterBackupImport()
                }

        #if os(iOS)
        baseContent
            .onAppear(perform: syncAccountsToWatch)
            .onChange(of: platformAccountService.accounts) { _ in
                syncAccountsToWatch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .picaxLocalFavoritesDidChange)) { _ in
                syncAccountsToWatch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .picaxReadLaterDidChange)) { _ in
                readLaterService.reloadFromDefaults()
                syncAccountsToWatch()
            }
            .onChange(of: syncsLocalFavorites) { _ in
                syncAccountsToWatch()
            }
            .onChange(of: syncsReadLater) { _ in
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
            syncsLocalFavorites: syncsLocalFavorites,
            syncsReadLater: syncsReadLater
        )
    }
    #endif

    private func reloadServicesAfterBackupImport() {
        appSettings.reloadFromDefaults()
        accountService.reloadFromStore()
        platformAccountService.reloadFromDefaults()
        readingHistoryService.reloadFromDefaults()
        readLaterService.reloadFromDefaults()
        readingDurationService.reloadFromDefaults()
        downloadService.reloadFromDefaults()
        blockingKeywordService.reloadFromDefaults()
        searchHistoryService.reloadFromDefaults()
        followUpdatesService.reload()
        ImageCacheService.configure()
        ComicDetailCacheService.configure()
    }
}

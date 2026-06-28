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

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                    downloadService.configure { platform in
                        platformAccountService.account(for: platform)
                    }
                }
        }
    }
}

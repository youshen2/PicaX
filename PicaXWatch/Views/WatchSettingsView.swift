import SwiftUI
import WatchConnectivity

struct WatchSettingsView: View {
    var body: some View {
        List {
            Section("账号") {
                NavigationLink {
                    WatchPlatformAccountsPage()
                } label: {
                    Label("账号管理", systemImage: "person.crop.circle")
                }
            }

            Section("页面") {
                NavigationLink {
                    WatchReaderSettingsPage()
                } label: {
                    Label("阅读", systemImage: "book.pages")
                }

                NavigationLink {
                    WatchSearchSettingsPage()
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }

                NavigationLink {
                    WatchDiscoverySettingsPage()
                } label: {
                    Label("发现", systemImage: "safari")
                }

                NavigationLink {
                    WatchTagsSettingsPage()
                } label: {
                    Label("标签", systemImage: "tag")
                }

                NavigationLink {
                    WatchListSettingsPage()
                } label: {
                    Label("列表", systemImage: "list.number")
                }
            }

            Section("离线与缓存") {
                NavigationLink {
                    WatchStorageManagementPage()
                } label: {
                    Label("存储管理", systemImage: "internaldrive")
                }

                NavigationLink {
                    WatchCacheSettingsPage()
                } label: {
                    Label("缓存", systemImage: "externaldrive")
                }

                NavigationLink {
                    WatchDownloadSettingsPage()
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
            }

            Section("应用") {
                NavigationLink {
                    WatchAboutPage()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("设置")
    }
}

struct WatchSearchSettingsPage: View {
    @AppStorage(WatchSettingsKey.defaultSearchTargetMode) private var defaultTargetModeRawValue = WatchSearchDefaultTargetMode.platform.rawValue
    @AppStorage(WatchSettingsKey.defaultSearchPlatform) private var defaultSearchPlatformID = WatchComicPlatform.picacg.rawValue
    @AppStorage(WatchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = WatchComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(WatchSettingsKey.savesSearchHistory) private var savesSearchHistory = true
    @AppStorage(WatchSettingsKey.maxSearchHistoryRecords) private var maxSearchHistoryRecords = 30

    var body: some View {
        List {
            Section("默认搜索源") {
                Picker("模式", selection: defaultTargetMode) {
                    ForEach(WatchSearchDefaultTargetMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }

                if selectedDefaultTargetMode == .platform {
                    Picker("默认平台", selection: defaultSearchPlatform) {
                        ForEach(WatchComicPlatform.allCases) { platform in
                            Text(platform.title)
                                .tag(platform)
                        }
                    }
                }
            }

            if selectedDefaultTargetMode == .aggregate {
                Section("聚合平台") {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Toggle(isOn: aggregatePlatformBinding(platform)) {
                            Label(platform.title, systemImage: platform.systemImage)
                        }
                    }
                }
            }

            Section("搜索历史") {
                Toggle("保存搜索历史", isOn: $savesSearchHistory)
                if savesSearchHistory {
                    WatchIntegerSettingLink(
                        title: "最多保留",
                        value: maxSearchHistoryRecordsBinding,
                        unit: "条",
                        range: 1...100,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                Button(role: .destructive) {
                    WatchSearchHistoryStore().clear()
                } label: {
                    Label("清空搜索历史", systemImage: "trash")
                }
            }
        }
        .navigationTitle("搜索")
        .onChange(of: maxSearchHistoryRecords) { _, _ in
            WatchSearchHistoryStore().trimToSettingsLimit()
        }
    }

    private var selectedDefaultTargetMode: WatchSearchDefaultTargetMode {
        WatchSearchDefaultTargetMode(rawValue: defaultTargetModeRawValue) ?? .platform
    }

    private var defaultTargetMode: Binding<WatchSearchDefaultTargetMode> {
        Binding(
            get: { selectedDefaultTargetMode },
            set: { defaultTargetModeRawValue = $0.rawValue }
        )
    }

    private var defaultSearchPlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: defaultSearchPlatformID) ?? .picacg },
            set: { defaultSearchPlatformID = $0.rawValue }
        )
    }

    private var selectedAggregatePlatforms: Set<WatchComicPlatform> {
        let platforms = defaultAggregatePlatformIDs
            .split(separator: ",")
            .compactMap { WatchComicPlatform(rawValue: String($0)) }
        return Set(platforms.isEmpty ? WatchComicPlatform.allCases : platforms)
    }

    private var maxSearchHistoryRecordsBinding: Binding<Int> {
        Binding(
            get: { min(max(maxSearchHistoryRecords, 1), 100) },
            set: { maxSearchHistoryRecords = min(max($0, 1), 100) }
        )
    }

    private func aggregatePlatformBinding(_ platform: WatchComicPlatform) -> Binding<Bool> {
        Binding(
            get: { selectedAggregatePlatforms.contains(platform) },
            set: { isOn in
                var nextPlatforms = selectedAggregatePlatforms
                if isOn {
                    nextPlatforms.insert(platform)
                } else {
                    guard nextPlatforms.count > 1 else { return }
                    nextPlatforms.remove(platform)
                }
                defaultAggregatePlatformIDs = WatchComicPlatform.allCases
                    .filter { nextPlatforms.contains($0) }
                    .map(\.rawValue)
                    .joined(separator: ",")
            }
        )
    }
}

struct WatchPlatformAccountsPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore

    var body: some View {
        List {
            Section("同步") {
                Button {
                    accountSyncStore.requestRefresh()
                } label: {
                    Label("从 iPhone 同步", systemImage: "arrow.clockwise")
                }

                Button {
                    accountSyncStore.syncLocalFavorites()
                } label: {
                    Label("同步本地收藏", systemImage: "heart")
                }

                Button {
                    accountSyncStore.syncReadLater()
                } label: {
                    Label("同步稍后再读", systemImage: "bookmark")
                }

                WatchValueRow(title: "连接状态", subtitle: syncStateText, systemImage: "iphone.gen3.radiowaves.left.and.right")

                if accountSyncStore.snapshot.updatedAt > .distantPast {
                    WatchValueRow(
                        title: "同步时间",
                        subtitle: accountSyncStore.snapshot.updatedAt.formatted(date: .numeric, time: .shortened),
                        systemImage: "clock"
                    )
                }
            }

            Section("已同步账号") {
                if accountSyncStore.snapshot.platformAccounts.isEmpty {
                    WatchEmptyRow(title: "暂无已同步账号", systemImage: "person.crop.circle.badge.exclamationmark")
                } else {
                    ForEach(accountSyncStore.snapshot.platformAccounts) { account in
                        WatchValueRow(
                            title: account.title,
                            subtitle: "\(account.displayName) · \(account.credentialState)",
                            systemImage: WatchComicPlatform(rawValue: account.platformID)?.systemImage
                        )
                    }
                }
            }

            Section("未登录账号") {
                let platforms = missingPlatforms
                if platforms.isEmpty {
                    WatchEmptyRow(title: "全部平台已同步", systemImage: "checkmark.circle")
                } else {
                    ForEach(platforms) { platform in
                        WatchValueRow(
                            title: platform.title,
                            subtitle: platform.subtitle,
                            systemImage: platform.systemImage,
                            tint: .secondary
                        )
                    }
                }
            }
        }
        .navigationTitle("账号管理")
    }

    private var missingPlatforms: [WatchComicPlatform] {
        let synced = Set(accountSyncStore.snapshot.platformAccounts.map(\.platformID))
        return WatchComicPlatform.allCases.filter { !synced.contains($0.id) }
    }

    private var syncStateText: String {
        if accountSyncStore.isReachable {
            return "iPhone 可达"
        }
        switch accountSyncStore.activationState {
        case .activated:
            return "等待 iPhone 推送"
        case .inactive:
            return "连接未激活"
        case .notActivated:
            return "尚未连接"
        @unknown default:
            return "未知"
        }
    }
}

struct WatchDiscoverySettingsPage: View {
    @AppStorage(WatchSettingsKey.defaultExplorePlatform) private var defaultExplorePlatformID = WatchComicPlatform.picacg.rawValue
    @AppStorage(WatchSettingsKey.showsAllExplorePlatforms) private var showsAllExplorePlatforms = false

    var body: some View {
        List {
            Section("发现") {
                Picker("默认平台", selection: defaultExplorePlatform) {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
                Toggle("显示全部平台", isOn: $showsAllExplorePlatforms)
            }
        }
        .navigationTitle("发现")
    }

    private var defaultExplorePlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: defaultExplorePlatformID) ?? .picacg },
            set: { defaultExplorePlatformID = $0.rawValue }
        )
    }
}

struct WatchTagsSettingsPage: View {
    @AppStorage(WatchSettingsKey.defaultTagsPlatform) private var defaultTagsPlatformID = WatchComicPlatform.picacg.rawValue

    var body: some View {
        List {
            Section("标签") {
                Picker("默认平台", selection: defaultTagsPlatform) {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
            }
        }
        .navigationTitle("标签")
    }

    private var defaultTagsPlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: defaultTagsPlatformID) ?? .picacg },
            set: { defaultTagsPlatformID = $0.rawValue }
        )
    }
}

struct WatchListSettingsPage: View {
    @AppStorage(WatchSettingsKey.maxVisibleComics) private var maxVisibleComics = 24

    var body: some View {
        List {
            Section("列表") {
                WatchIntegerSettingLink(
                    title: "显示数量",
                    value: maxVisibleComicsBinding,
                    unit: "部",
                    range: 6...60,
                    systemImage: "list.number"
                )
            }
        }
        .navigationTitle("列表")
    }

    private var validatedMaxVisibleComics: Int {
        min(max(maxVisibleComics, 6), 60)
    }

    private var maxVisibleComicsBinding: Binding<Int> {
        Binding(
            get: { validatedMaxVisibleComics },
            set: { maxVisibleComics = min(max($0, 6), 60) }
        )
    }
}

struct WatchReaderSettingsPage: View {
    @AppStorage(WatchSettingsKey.readerReadingMode) private var readingModeRawValue = WatchReaderReadingMode.continuousVertical.rawValue
    @AppStorage(WatchSettingsKey.readerImageSpacing) private var imageSpacing = 0
    @AppStorage(WatchSettingsKey.readerFirstImageTopPadding) private var firstImageTopPadding = 24
    @AppStorage(WatchSettingsKey.readerLastImageBottomPadding) private var lastImageBottomPadding = 24
    @AppStorage(WatchSettingsKey.readerPrefetchCount) private var readerPrefetchCount = 2
    @AppStorage(WatchSettingsKey.readerRetryCount) private var retryCount = 2
    @AppStorage(WatchSettingsKey.readerRetryIntervalSeconds) private var retryIntervalSeconds = 1
    @AppStorage(WatchSettingsKey.readerShowsProgress) private var showsProgress = true
    @AppStorage(WatchSettingsKey.readerProgressPosition) private var progressPositionRawValue = WatchReaderOverlayPosition.bottomLeading.rawValue
    @AppStorage(WatchSettingsKey.readerProgressEdgeInset) private var progressEdgeInset = 8
    @AppStorage(WatchSettingsKey.readerProgressBottomInset) private var progressBottomInset = 3
    @AppStorage(WatchSettingsKey.readerUsesProgressGlassBackground) private var usesProgressGlassBackground = true
    @AppStorage(WatchSettingsKey.readerShowsSystemStatus) private var showsSystemStatus = true
    @AppStorage(WatchSettingsKey.readerSystemStatusPosition) private var systemStatusPositionRawValue = WatchReaderOverlayPosition.bottomTrailing.rawValue
    @AppStorage(WatchSettingsKey.readerSystemStatusEdgeInset) private var systemStatusEdgeInset = 8
    @AppStorage(WatchSettingsKey.readerSystemStatusBottomInset) private var systemStatusBottomInset = 3
    @AppStorage(WatchSettingsKey.readerUsesSystemStatusGlassBackground) private var usesSystemStatusGlassBackground = true
    @AppStorage(WatchSettingsKey.readerKeepsScreenAwake) private var readerKeepsScreenAwake = false

    var body: some View {
        List {
            Section("阅读") {
                Picker("阅读方式", selection: readingMode) {
                    ForEach(WatchReaderReadingMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                Toggle("阅读时保持亮屏", isOn: $readerKeepsScreenAwake)
            }

            Section("边距") {
                WatchIntegerSettingLink(
                    title: "图片间距",
                    value: imageSpacingBinding,
                    unit: "pt",
                    range: 0...24,
                    systemImage: "arrow.up.and.down"
                )
                WatchIntegerSettingLink(
                    title: "首图顶部留白",
                    value: firstImageTopPaddingBinding,
                    unit: "pt",
                    range: 0...160,
                    systemImage: "arrow.up.to.line"
                )
                WatchIntegerSettingLink(
                    title: "末图底部留白",
                    value: lastImageBottomPaddingBinding,
                    unit: "pt",
                    range: 0...160,
                    systemImage: "arrow.down.to.line"
                )
            }

            Section("阅读进度") {
                Toggle("显示胶囊", isOn: $showsProgress)
                if showsProgress {
                    Picker("显示位置", selection: progressPosition) {
                        ForEach(WatchReaderOverlayPosition.allCases) { position in
                            Text(position.title)
                                .tag(position)
                        }
                    }
                    Toggle("液态玻璃背景", isOn: $usesProgressGlassBackground)
                    WatchIntegerSettingLink(
                        title: "边缘距离",
                        value: progressEdgeInsetBinding,
                        unit: "pt",
                        range: 0...60,
                        systemImage: "arrow.left.and.right"
                    )
                    WatchIntegerSettingLink(
                        title: "底部距离",
                        value: progressBottomInsetBinding,
                        unit: "pt",
                        range: 0...80,
                        systemImage: "arrow.down.to.line"
                    )
                }
            }

            Section("时间电量") {
                Toggle("显示胶囊", isOn: $showsSystemStatus)
                if showsSystemStatus {
                    Picker("显示位置", selection: systemStatusPosition) {
                        ForEach(availableSystemStatusPositions) { position in
                            Text(position.title)
                                .tag(position)
                        }
                    }
                    Toggle("液态玻璃背景", isOn: $usesSystemStatusGlassBackground)
                    WatchIntegerSettingLink(
                        title: "边缘距离",
                        value: systemStatusEdgeInsetBinding,
                        unit: "pt",
                        range: 0...60,
                        systemImage: "arrow.left.and.right"
                    )
                    WatchIntegerSettingLink(
                        title: "底部距离",
                        value: systemStatusBottomInsetBinding,
                        unit: "pt",
                        range: 0...80,
                        systemImage: "arrow.down.to.line"
                    )
                }
            }

            Section("加载") {
                WatchIntegerSettingLink(
                    title: "预加载页数",
                    value: prefetchBinding,
                    unit: "页",
                    range: 0...12,
                    systemImage: "square.stack"
                )
                WatchIntegerSettingLink(
                    title: "图片重试",
                    value: retryBinding,
                    unit: "次",
                    range: 0...8,
                    systemImage: "arrow.clockwise"
                )
                WatchIntegerSettingLink(
                    title: "重试间隔",
                    value: retryIntervalBinding,
                    unit: "秒",
                    range: 0...10,
                    systemImage: "timer"
                )
            }
        }
        .navigationTitle("阅读")
    }

    private var validatedPrefetchCount: Int {
        min(max(readerPrefetchCount, 0), 8)
    }

    private var prefetchBinding: Binding<Int> {
        Binding(
            get: { min(max(readerPrefetchCount, 0), 12) },
            set: { readerPrefetchCount = min(max($0, 0), 12) }
        )
    }

    private var retryBinding: Binding<Int> {
        Binding(
            get: { min(max(retryCount, 0), 8) },
            set: { retryCount = min(max($0, 0), 8) }
        )
    }

    private var retryIntervalBinding: Binding<Int> {
        Binding(
            get: { min(max(retryIntervalSeconds, 0), 10) },
            set: { retryIntervalSeconds = min(max($0, 0), 10) }
        )
    }

    private var progressEdgeInsetBinding: Binding<Int> {
        Binding(
            get: { min(max(progressEdgeInset, 0), 60) },
            set: { progressEdgeInset = min(max($0, 0), 60) }
        )
    }

    private var progressBottomInsetBinding: Binding<Int> {
        Binding(
            get: { min(max(progressBottomInset, 0), 80) },
            set: { progressBottomInset = min(max($0, 0), 80) }
        )
    }

    private var systemStatusEdgeInsetBinding: Binding<Int> {
        Binding(
            get: { min(max(systemStatusEdgeInset, 0), 60) },
            set: { systemStatusEdgeInset = min(max($0, 0), 60) }
        )
    }

    private var systemStatusBottomInsetBinding: Binding<Int> {
        Binding(
            get: { min(max(systemStatusBottomInset, 0), 80) },
            set: { systemStatusBottomInset = min(max($0, 0), 80) }
        )
    }

    private var imageSpacingBinding: Binding<Int> {
        Binding(
            get: { min(max(imageSpacing, 0), 24) },
            set: { imageSpacing = min(max($0, 0), 24) }
        )
    }

    private var firstImageTopPaddingBinding: Binding<Int> {
        Binding(
            get: { min(max(firstImageTopPadding, 0), 160) },
            set: { firstImageTopPadding = min(max($0, 0), 160) }
        )
    }

    private var lastImageBottomPaddingBinding: Binding<Int> {
        Binding(
            get: { min(max(lastImageBottomPadding, 0), 160) },
            set: { lastImageBottomPadding = min(max($0, 0), 160) }
        )
    }

    private var readingMode: Binding<WatchReaderReadingMode> {
        Binding(
            get: { selectedReadingMode },
            set: { readingModeRawValue = $0.rawValue }
        )
    }

    private var selectedReadingMode: WatchReaderReadingMode {
        WatchReaderReadingMode(rawValue: readingModeRawValue) ?? .continuousVertical
    }

    private var selectedProgressPosition: WatchReaderOverlayPosition {
        WatchReaderOverlayPosition(rawValue: progressPositionRawValue) ?? .bottomLeading
    }

    private var selectedSystemStatusPosition: WatchReaderOverlayPosition {
        let value = WatchReaderOverlayPosition(rawValue: systemStatusPositionRawValue) ?? .bottomTrailing
        return showsProgress && value == selectedProgressPosition ? fallbackSystemStatusPosition(for: selectedProgressPosition) : value
    }

    private var availableSystemStatusPositions: [WatchReaderOverlayPosition] {
        guard showsProgress else { return WatchReaderOverlayPosition.allCases }
        return WatchReaderOverlayPosition.allCases.filter { $0 != selectedProgressPosition }
    }

    private var progressPosition: Binding<WatchReaderOverlayPosition> {
        Binding(
            get: { selectedProgressPosition },
            set: { newValue in
                progressPositionRawValue = newValue.rawValue
                if selectedSystemStatusPosition == newValue {
                    systemStatusPositionRawValue = fallbackSystemStatusPosition(for: newValue).rawValue
                }
            }
        )
    }

    private var systemStatusPosition: Binding<WatchReaderOverlayPosition> {
        Binding(
            get: { selectedSystemStatusPosition },
            set: { newValue in
                systemStatusPositionRawValue = (showsProgress && newValue == selectedProgressPosition
                    ? fallbackSystemStatusPosition(for: selectedProgressPosition)
                    : newValue).rawValue
            }
        )
    }

    private func fallbackSystemStatusPosition(for progressPosition: WatchReaderOverlayPosition) -> WatchReaderOverlayPosition {
        switch progressPosition {
        case .topLeading:
            .topTrailing
        case .topTrailing:
            .topLeading
        case .bottomLeading:
            .bottomTrailing
        case .bottomTrailing:
            .bottomLeading
        }
    }
}

struct WatchStorageManagementPage: View {
    @EnvironmentObject private var downloadService: WatchDownloadService
    @State private var imageUsage = WatchCacheUsage(diskBytes: 0)
    @State private var detailUsage = WatchDetailCacheUsage(diskBytes: 0)
    @State private var downloadUsage = WatchDownloadStorageUsage(filesBytes: 0, metadataBytes: 0)

    var body: some View {
        List {
            Section("总览") {
                WatchValueRow(title: "总占用", subtitle: WatchStorageFormatter.formattedSize(totalBytes), systemImage: "internaldrive")
            }

            Section("缓存") {
                WatchValueRow(title: "图片缓存", subtitle: imageUsage.formatted, systemImage: "photo")
                WatchValueRow(title: "详情缓存", subtitle: detailUsage.formatted, systemImage: "doc.text")
            }

            Section("下载") {
                WatchValueRow(title: "下载文件", subtitle: WatchStorageFormatter.formattedSize(downloadUsage.filesBytes), systemImage: "folder")
                WatchValueRow(title: "下载记录", subtitle: WatchStorageFormatter.formattedSize(Int64(downloadUsage.metadataBytes)), systemImage: "doc.text")
            }

            Section("操作") {
                Button {
                    refreshUsage()
                } label: {
                    Label("刷新占用", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    WatchImageCacheService.clear()
                    refreshUsage()
                } label: {
                    Label("清空图片缓存", systemImage: "trash")
                }

                Button(role: .destructive) {
                    WatchComicDetailCacheService.clear()
                    refreshUsage()
                } label: {
                    Label("清空详情缓存", systemImage: "trash")
                }

                Button(role: .destructive) {
                    downloadService.clearAllDownloads()
                    refreshUsage()
                } label: {
                    Label("清空下载", systemImage: "trash")
                }
            }
        }
        .navigationTitle("存储管理")
        .task {
            refreshUsage()
        }
    }

    private var totalBytes: Int64 {
        imageUsage.diskBytes + detailUsage.diskBytes + downloadUsage.filesBytes + Int64(downloadUsage.metadataBytes)
    }

    private func refreshUsage() {
        imageUsage = WatchImageCacheService.usage
        detailUsage = WatchComicDetailCacheService.usage
        Task {
            downloadUsage = await downloadService.storageUsage()
        }
    }
}

struct WatchCacheSettingsPage: View {
    @AppStorage(WatchSettingsKey.imageCacheEnabled) private var imageCacheEnabled = true
    @AppStorage(WatchSettingsKey.detailCacheEnabled) private var detailCacheEnabled = true
    @AppStorage(WatchSettingsKey.imageCacheMaxDiskSizeMB) private var maxDiskSizeMB = WatchImageCacheService.defaultMaxDiskSizeMB
    @AppStorage(WatchSettingsKey.detailCacheMaxDiskSizeMB) private var maxDetailDiskSizeMB = WatchComicDetailCacheService.defaultMaxDiskSizeMB

    var body: some View {
        List {
            Section("开关") {
                Toggle("图片缓存", isOn: $imageCacheEnabled)
                Toggle("详情缓存", isOn: $detailCacheEnabled)
            }

            Section("容量") {
                WatchIntegerSettingLink(
                    title: "图片上限",
                    value: maxDiskSizeBinding,
                    unit: "MB",
                    range: 20...500,
                    systemImage: "gauge"
                )
                WatchIntegerSettingLink(
                    title: "详情上限",
                    value: maxDetailDiskSizeBinding,
                    unit: "MB",
                    range: 5...100,
                    systemImage: "doc.text"
                )
            }

            Section("操作") {
                Button(role: .destructive) {
                    WatchImageCacheService.clear()
                } label: {
                    Label("清空图片缓存", systemImage: "trash")
                }

                Button(role: .destructive) {
                    WatchComicDetailCacheService.clear()
                } label: {
                    Label("清空详情缓存", systemImage: "trash")
                }
            }
        }
        .navigationTitle("缓存")
        .task {
            WatchImageCacheService.configure()
            WatchComicDetailCacheService.configure()
        }
        .onChange(of: maxDiskSizeMB) { _, _ in
            WatchImageCacheService.configure()
        }
        .onChange(of: maxDetailDiskSizeMB) { _, _ in
            WatchComicDetailCacheService.configure()
        }
    }

    private var validatedMaxDiskSizeMB: Int {
        min(max(maxDiskSizeMB, 20), 500)
    }

    private var maxDiskSizeBinding: Binding<Int> {
        Binding(
            get: { validatedMaxDiskSizeMB },
            set: { maxDiskSizeMB = min(max($0, 20), 500) }
        )
    }

    private var validatedMaxDetailDiskSizeMB: Int {
        min(max(maxDetailDiskSizeMB, 5), 100)
    }

    private var maxDetailDiskSizeBinding: Binding<Int> {
        Binding(
            get: { validatedMaxDetailDiskSizeMB },
            set: { maxDetailDiskSizeMB = min(max($0, 5), 100) }
        )
    }
}

struct WatchDownloadSettingsPage: View {
    @AppStorage(WatchSettingsKey.downloadRetryCount) private var retryCount = 2
    @AppStorage(WatchSettingsKey.downloadReadsImagesFromCache) private var readsImagesFromCache = true

    var body: some View {
        List {
            Section("下载") {
                Toggle("复用图片缓存", isOn: $readsImagesFromCache)
                WatchIntegerSettingLink(
                    title: "失败重试",
                    value: retryBinding,
                    unit: "次",
                    range: 0...6,
                    systemImage: "arrow.clockwise"
                )
            }
        }
        .navigationTitle("下载")
    }

    private var validatedRetryCount: Int {
        min(max(retryCount, 0), 6)
    }

    private var retryBinding: Binding<Int> {
        Binding(
            get: { validatedRetryCount },
            set: { retryCount = min(max($0, 0), 6) }
        )
    }
}

struct WatchAboutPage: View {
    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PicaX"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        List {
            Section("应用") {
                WatchValueRow(title: "名称", subtitle: displayName, systemImage: "applewatch")
                WatchValueRow(title: "版本", subtitle: appVersion, systemImage: "number")
                WatchValueRow(title: "构建", subtitle: buildNumber, systemImage: "hammer")
            }

            Section("平台") {
                WatchValueRow(title: "支持漫画源", subtitle: "\(WatchComicPlatform.allCases.count) 个", systemImage: "square.grid.2x2")
                ForEach(WatchComicPlatform.allCases) { platform in
                    Label(platform.title, systemImage: platform.systemImage)
                }
            }

            Section("开源") {
                Link(destination: URL(string: "https://github.com/youshen2/PicaX")!) {
                    Label("开源地址", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!) {
                    Label("MPL-2.0 开源协议", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("关于")
    }
}

private struct WatchIntegerSettingLink: View {
    let title: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let systemImage: String

    var body: some View {
        NavigationLink {
            WatchIntegerInputPage(
                title: title,
                value: $value,
                unit: unit,
                range: range
            )
        } label: {
            WatchValueRow(
                title: title,
                subtitle: "\(clampedValue) \(unit)",
                systemImage: systemImage
            )
        }
    }

    private var clampedValue: Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct WatchIntegerInputPage: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    @State private var draft: String
    @State private var errorMessage: String?

    init(title: String, value: Binding<Int>, unit: String, range: ClosedRange<Int>) {
        self.title = title
        self._value = value
        self.unit = unit
        self.range = range
        self._draft = State(initialValue: "\(min(max(value.wrappedValue, range.lowerBound), range.upperBound))")
    }

    var body: some View {
        List {
            Section(title) {
                TextField(unit, text: $draft)

                WatchValueRow(
                    title: "允许范围",
                    subtitle: "\(range.lowerBound)-\(range.upperBound) \(unit)",
                    systemImage: "number"
                )
            }

            if let errorMessage {
                Section {
                    WatchValueRow(title: "输入无效", subtitle: errorMessage, systemImage: "exclamationmark.triangle", tint: .orange)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
            }
        }
        .navigationTitle(title)
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmed) else {
            errorMessage = "请输入整数。"
            return
        }
        guard range.contains(number) else {
            errorMessage = "请输入 \(range.lowerBound)-\(range.upperBound) 之间的数值。"
            return
        }
        value = number
        dismiss()
    }
}

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct SettingsPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @State private var searchText = ""

    var body: some View {
        List {
            if showsAny(.platformAccounts) {
                Section("账号") {
                    if shows(.platformAccounts) {
                        NavigationLink {
                            PlatformAccountsSettingsView()
                        } label: {
                            SettingsActionRow(
                                title: SettingsSearchItem.platformAccounts.title,
                                subtitle: "已登录 \(platformAccounts.loggedInAccounts.count)/\(ComicPlatform.allCases.count) 个平台",
                                systemImage: "person.2"
                            )
                        }
                    }
                }
            }

            if showsAny(.home, .explore, .search, .comicList, .detail, .reader) {
                Section("浏览与阅读") {
                    if shows(.home) {
                        SettingsNavigationLink(item: .home, systemImage: "house") {
                            HomeSettingsView()
                        }
                    }
                    if shows(.explore) {
                        SettingsNavigationLink(item: .explore, systemImage: "safari") {
                            ExploreSettingsView()
                        }
                    }
                    if shows(.search) {
                        SettingsNavigationLink(item: .search, systemImage: "magnifyingglass") {
                            SearchSettingsView()
                        }
                    }
                    if shows(.comicList) {
                        SettingsNavigationLink(item: .comicList, systemImage: "list.bullet.rectangle") {
                            ComicListSettingsView()
                        }
                    }
                    if shows(.detail) {
                        SettingsNavigationLink(item: .detail, systemImage: "info.square") {
                            ComicDetailSettingsView()
                        }
                    }
                    if shows(.reader) {
                        SettingsNavigationLink(item: .reader, systemImage: "book.pages") {
                            ReaderSettingsView()
                        }
                    }
                }
            }

            if showsAny(.downloads, .history, .readingDuration, .blockingKeywords, .storage, .backup) {
                Section("内容与数据") {
                    if shows(.downloads) {
                        SettingsNavigationLink(item: .downloads, systemImage: "arrow.down.circle") {
                            DownloadSettingsView()
                        }
                    }
                    if shows(.history) {
                        SettingsNavigationLink(item: .history, systemImage: "clock.arrow.circlepath") {
                            HistorySettingsView()
                        }
                    }
                    if shows(.readingDuration) {
                        SettingsNavigationLink(item: .readingDuration, systemImage: "timer") {
                            ReadingDurationSettingsView()
                        }
                    }
                    if shows(.blockingKeywords) {
                        SettingsNavigationLink(item: .blockingKeywords, systemImage: "eye.slash") {
                            BlockingKeywordSettingsView()
                        }
                    }
                    if shows(.storage) {
                        SettingsNavigationLink(item: .storage, systemImage: "internaldrive") {
                            StorageManagementView()
                        }
                    }
                    if shows(.backup) {
                        SettingsNavigationLink(item: .backup, systemImage: "tray.full") {
                            BackupSettingsView()
                        }
                    }
                }
            }

            if showsAny(.appDisplay, .appBehavior, .watchConnectivity, .network, .about) {
                Section("网络与应用") {
                    if shows(.appDisplay) {
                        SettingsNavigationLink(item: .appDisplay, systemImage: "paintbrush") {
                            AppDisplaySettingsView()
                        }
                    }
                    if shows(.appBehavior) {
                        SettingsNavigationLink(item: .appBehavior, systemImage: "gearshape") {
                            AppBehaviorSettingsView()
                        }
                    }
                    if shows(.watchConnectivity) {
                        SettingsNavigationLink(item: .watchConnectivity, systemImage: "applewatch") {
                            WatchConnectivitySettingsView()
                        }
                    }
                    if shows(.network) {
                        SettingsNavigationLink(item: .network, systemImage: "network") {
                            NetworkSettingsView()
                        }
                    }
                    if shows(.about) {
                        SettingsNavigationLink(item: .about, systemImage: "info.circle") {
                            AboutSettingsView()
                        }
                    }
                }
            }

            if isSearchingSettings, !hasSettingsSearchResults {
                Section {
                    ContentUnavailableView("没有找到设置", systemImage: "magnifyingglass", description: Text("换个关键词再试。"))
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("设置")
        .searchable(text: $searchText, placement: .picaxNavigationSearch, prompt: "搜索设置")
        .picaxHidesTabBar()
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearchingSettings: Bool {
        !normalizedSearchText.isEmpty
    }

    private var hasSettingsSearchResults: Bool {
        SettingsSearchItem.allCases.contains { shows($0) }
    }

    private func shows(_ item: SettingsSearchItem) -> Bool {
        item.matches(normalizedSearchText)
    }

    private func showsAny(_ items: SettingsSearchItem...) -> Bool {
        items.contains { shows($0) }
    }
}

private enum SettingsSearchItem: CaseIterable {
    case platformAccounts
    case home
    case explore
    case search
    case comicList
    case detail
    case reader
    case downloads
    case history
    case readingDuration
    case blockingKeywords
    case storage
    case backup
    case appDisplay
    case appBehavior
    case watchConnectivity
    case network
    case about

    var title: String {
        switch self {
        case .platformAccounts:
            "平台账号"
        case .home:
            "首页"
        case .explore:
            "发现页"
        case .search:
            "搜索"
        case .comicList:
            "漫画列表"
        case .detail:
            "漫画详情"
        case .reader:
            "阅读器"
        case .downloads:
            "下载"
        case .history:
            "历史记录"
        case .readingDuration:
            "阅读时长"
        case .blockingKeywords:
            "关键词屏蔽"
        case .storage:
            "存储管理"
        case .backup:
            "备份与恢复"
        case .appDisplay:
            "显示"
        case .appBehavior:
            "App行为"
        case .watchConnectivity:
            "Watch互联"
        case .network:
            "网络与代理"
        case .about:
            "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .platformAccounts:
            "平台登录与账号管理"
        case .home:
            "入口折叠与卡片数量"
        case .explore:
            "默认平台与平台选择记忆"
        case .search:
            "搜索源、历史与键盘行为"
        case .comicList:
            "显示内容与已读隐藏"
        case .detail:
            "按钮颜色与详情显示"
        case .reader:
            "翻页、进度、缩放与图片显示"
        case .downloads:
            "并发、限速与默认内容"
        case .history:
            "历史记录与阅读进度"
        case .readingDuration:
            "统计、趋势与清理"
        case .blockingKeywords:
            "通用与 JMComic 专用关键词"
        case .storage:
            "空间占用、图片缓存与详情缓存"
        case .backup:
            "导出或导入本地数据"
        case .appDisplay:
            "显示模式"
        case .appBehavior:
            "剪贴板检测与启动检查"
        case .watchConnectivity:
            "阅读记录、本地收藏与稍后再读同步"
        case .network:
            "连接与重试"
        case .about:
            "版本、平台与声明"
        }
    }

    var keywords: [String] {
        switch self {
        case .platformAccounts:
            ComicPlatform.allCases.map(\.title) + ["登录", "账号", "cookie"]
        case .reader:
            ["自动翻页", "点按翻页", "两指缩放", "双击缩放", "长按缩放", "预加载", "状态栏", "页码", "亮度", "深色模式"]
        case .home:
            ["阅读时长", "阅读历史", "稍后再读", "下载", "折叠", "首页卡片"]
        case .storage:
            ["缓存", "图片缓存", "详情缓存", "空间", "清空缓存"]
        case .blockingKeywords:
            ["屏蔽", "黑名单", "关键词", "标签"]
        case .search:
            ["默认搜索源", "搜索历史", "聚合搜索", "搜索补全", "标签建议", "填入", "直接搜索"]
        case .comicList:
            ["已读隐藏", "阅读进度", "收藏状态", "标签"]
        case .downloads:
            ["下载评论", "同时下载", "限速", "队列", "ZIP", "导出", "文件名"]
        case .appDisplay:
            ["深色", "浅色"]
        case .appBehavior:
            ["剪贴板", "启动", "更新"]
        case .watchConnectivity:
            ["Watch", "Apple Watch", "手表", "互联", "同步", "阅读记录", "本地收藏", "稍后再读"]
        case .history:
            ["阅读进度", "清空", "记录"]
        case .readingDuration:
            ["阅读时长", "统计", "趋势", "清空", "记录", "单次", "低于"]
        default:
            []
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = ([title, subtitle] + keywords).joined(separator: " ").lowercased()
        return query.split(separator: " ").allSatisfy { haystack.contains($0.lowercased()) }
    }
}

private struct AppDisplaySettingsView: View {
    @AppStorage(AppAppearanceSettingsKey.colorScheme) private var colorScheme = AppAppearanceMode.system.rawValue

    var body: some View {
        List {
            Section {
                Picker("显示模式", selection: $colorScheme) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("选择后会应用到整个应用。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("显示")
        .picaxHidesTabBar()
    }
}

private struct AppBehaviorSettingsView: View {
    @AppStorage(AppBehaviorSettingsKey.checksClipboardForComicLinks) private var checksClipboardForComicLinks = false
    @AppStorage(AppBehaviorSettingsKey.checksClipboardOnlyOnLaunch) private var checksClipboardOnlyOnLaunch = false
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true

    var body: some View {
        List {
            Section {
                Toggle("检查剪贴板链接", isOn: $checksClipboardForComicLinks)
                if checksClipboardForComicLinks {
                    Toggle("仅启动应用时检查", isOn: $checksClipboardOnlyOnLaunch)
                }
                Toggle("启动时检查更新", isOn: $checksUpdatesOnLaunch)
            } footer: {
                Text("剪贴板检查会提示打开支持链接或 JM 车牌号。启动更新检查只会在发现新版本时提示，检查失败不会打断启动。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("App行为")
        .picaxHidesTabBar()
    }
}

private struct WatchConnectivitySettingsView: View {
    @AppStorage(WatchConnectivitySettingsKey.syncsReadingHistory) private var syncsReadingHistory = true
    @AppStorage(WatchConnectivitySettingsKey.syncsLocalFavorites) private var syncsLocalFavorites = true
    @AppStorage(WatchConnectivitySettingsKey.syncsReadLater) private var syncsReadLater = true

    var body: some View {
        List {
            Section {
                Toggle("阅读记录同步", isOn: $syncsReadingHistory)
                Toggle("本地收藏同步", isOn: $syncsLocalFavorites)
                Toggle("稍后再读同步", isOn: $syncsReadLater)
            } header: {
                Text("同步内容")
            } footer: {
                Text("平台账号始终由 iPhone 同步给手表；漫画列表和平台内容仍由手表端独立请求。关闭某项后，该内容不会继续推送给手表。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("Watch互联")
        .picaxHidesTabBar()
    }
}

struct PlatformAccountsSettingsView: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    var body: some View {
        List {
            Section("平台") {
                ForEach(ComicPlatform.allCases) { platform in
                    NavigationLink {
                        PlatformLoginView(platform: platform)
                    } label: {
                        PlatformAccountRow(
                            platform: platform,
                            account: platformAccounts.account(for: platform)
                        )
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("平台账号")
        .picaxHidesTabBar()
    }
}

struct PlatformLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    let platform: ComicPlatform
    private let service = ComicContentService()

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoggingIn = false

    var body: some View {
        List {
            if supportsPasswordLogin {
                Section {
                    TextField(platform.loginHint, text: $username)
                        .textContentType(.username)
                        .disabled(isLoggingIn)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .disabled(isLoggingIn)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("登录信息")
                } footer: {
                    Text("应用会保存必要的登录信息，用来下次继续使用。")
                }
            }

            if let account = platformAccounts.account(for: platform) {
                Section("当前状态") {
                    SettingsValueRow(title: "账号", value: account.displayName)
                    SettingsValueRow(title: "登录状态", value: account.credential.summaryText)
                    SettingsValueRow(title: "登录时间", value: account.loggedInAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section {
                if supportsPasswordLogin {
                    Button {
                        Task {
                            await login()
                        }
                    } label: {
                        if isLoggingIn {
                            HStack {
                                ProgressView()
                                Text("正在验证")
                            }
                        } else {
                            Label(platformAccounts.isLoggedIn(platform) ? "重新登录" : "登录", systemImage: "arrow.right.circle")
                        }
                    }
                    .disabled(isLoggingIn)
                }

                if platform.loginWebsite != nil {
                    NavigationLink {
                        PlatformWebLoginPage(platform: platform)
                    } label: {
                        Label("通过网页登录", systemImage: "safari")
                    }
                }

                if platformAccounts.isLoggedIn(platform) {
                    Button("退出登录", role: .destructive) {
                        platformAccounts.logout(platform: platform)
                        username = ""
                        password = ""
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle(platform.title)
        .picaxHidesTabBar()
        .onAppear {
            if let account = platformAccounts.account(for: platform) {
                username = account.username
            }
        }
    }

    private var supportsPasswordLogin: Bool {
        switch platform {
        case .picacg, .jmComic, .htManga:
            true
        case .nhentai, .eHentai, .hitomi:
            false
        }
    }

    @MainActor
    private func login() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        do {
            let account = try await service.validateLogin(platform: platform, username: username, password: password)
            platformAccounts.saveValidatedAccount(account)
            password = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoggingIn = false
    }
}

private struct HomeSettingsView: View {
    @AppStorage(ReadingHistoryService.Key.homeLimit) private var homeLimit = 10
    @AppStorage(ReadLaterService.Key.homeLimit) private var readLaterHomeLimit = 10
    @AppStorage(ReadingDurationService.Key.homeLimit) private var readingDurationHomeLimit = 6
    @AppStorage(DownloadSettingsKey.homeLimit) private var downloadHomeLimit = 8
    @AppStorage(HomeSettingsKey.showsHistorySection) private var showsHistorySection = true
    @AppStorage(HomeSettingsKey.showsReadLaterSection) private var showsReadLaterSection = true
    @AppStorage(HomeSettingsKey.showsReadingDurationSection) private var showsReadingDurationSection = true
    @AppStorage(HomeSettingsKey.showsDownloadSection) private var showsDownloadSection = true
    @AppStorage(HomeSettingsKey.showsAccountManagementEntry) private var showsAccountManagementEntry = true
    @AppStorage(HomeSettingsKey.sectionOrder) private var sectionOrderRaw = HomeSectionKind.defaultRawValue
    @State private var sectionOrder = HomeSectionKind.defaultOrder

    var body: some View {
        List {
            Section {
                Toggle("账号管理入口", isOn: $showsAccountManagementEntry)
                Toggle("阅读历史", isOn: $showsHistorySection)
                Toggle("稍后再读", isOn: $showsReadLaterSection)
                Toggle("阅读时长", isOn: $showsReadingDurationSection)
                Toggle("下载", isOn: $showsDownloadSection)
            } header: {
                Text("详细内容")
            } footer: {
                Text("关闭阅读历史、阅读时长或下载后，首页仍保留入口，只折叠横向卡片等详细内容。")
            }

            Section {
                if showsHistorySection {
                    IntegerSettingsInputRow(title: "阅读历史显示", value: $homeLimit, unit: "条", lowerBound: 1, upperBound: 30)
                }

                if showsReadLaterSection {
                    IntegerSettingsInputRow(title: "稍后再读显示", value: $readLaterHomeLimit, unit: "条", lowerBound: 1, upperBound: 30)
                }

                if showsReadingDurationSection {
                    IntegerSettingsInputRow(title: "阅读时长显示", value: $readingDurationHomeLimit, unit: "部", lowerBound: 1, upperBound: 30)
                }

                if showsDownloadSection {
                    IntegerSettingsInputRow(title: "下载显示", value: $downloadHomeLimit, unit: "条", lowerBound: 1, upperBound: 30)
                }
            } footer: {
                Text("只影响首页详细卡片数量，不影响完整列表和本地数据。")
            }

            Section {
                ForEach(sectionOrder) { section in
                    Label(section.title, systemImage: section.systemImage)
                }
                .onMove(perform: moveSections)

                Button("恢复默认排序") {
                    sectionOrder = HomeSectionKind.defaultOrder
                    saveSectionOrder()
                }
            } header: {
                Text("排序")
            } footer: {
                Text("点按编辑后拖动项目调整首页显示顺序。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("首页")
        .picaxHidesTabBar()
        #if os(iOS)
        .toolbar {
            EditButton()
        }
        #endif
        .onAppear {
            sectionOrder = HomeSectionKind.normalizedOrder(from: sectionOrderRaw)
            saveSectionOrder()
        }
        .onChange(of: sectionOrderRaw) { _, newValue in
            sectionOrder = HomeSectionKind.normalizedOrder(from: newValue)
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
        saveSectionOrder()
    }

    private func saveSectionOrder() {
        sectionOrderRaw = HomeSectionKind.rawValue(for: sectionOrder)
    }
}

private struct DownloadSettingsView: View {
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(DownloadSettingsKey.imageRetryCount) private var imageRetryCount = 2
    @AppStorage(DownloadSettingsKey.concurrentDownloadCount) private var concurrentDownloadCount = 1
    @AppStorage(DownloadSettingsKey.speedLimitEnabled) private var speedLimitEnabled = false
    @AppStorage(DownloadSettingsKey.speedLimitKBPerSecond) private var speedLimitKBPerSecond = 1024
    @AppStorage(DownloadSettingsKey.readsImagesFromCache) private var readsImagesFromCache = true
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false
    @AppStorage(DownloadSettingsKey.archiveFileNameTemplate) private var archiveFileNameTemplate = DownloadSettingsKey.defaultArchiveFileNameTemplate
    @AppStorage(DownloadSettingsKey.showsProgressNotifications) private var showsProgressNotifications = true
    @AppStorage(DownloadSettingsKey.showsProgressLiveActivity) private var showsProgressLiveActivity = true
    @AppStorage(DownloadSettingsKey.progressNotificationUpdateIntervalSeconds) private var progressNotificationUpdateIntervalSeconds = DownloadSettingsKey.defaultProgressNotificationUpdateIntervalSeconds

    var body: some View {
        List {
            Section {
                Toggle("默认保存评论区", isOn: $downloadsCommentsByDefault)
            } header: {
                Text("下载内容")
            } footer: {
                Text("开启后，支持评论区的漫画在打开下载面板时会默认一并保存详情评论和章节评论。")
            }

            Section {
                Toggle("读取图片缓存", isOn: $readsImagesFromCache)
            } header: {
                Text("图片")
            } footer: {
                Text("开启后，下载会优先使用已缓存的图片数据。关闭后，每次下载都绕过图片缓存并从网络重新获取。")
            }

            #if os(iOS)
            Section {
                Toggle("常驻进度通知", isOn: $showsProgressNotifications)

                if showsProgressNotifications {
                    IntegerSettingsInputRow(
                        title: "通知更新间隔",
                        value: $progressNotificationUpdateIntervalSeconds,
                        unit: "秒",
                        lowerBound: 1,
                        upperBound: 60
                    )
                }

                Toggle("灵动岛下载进度", isOn: $showsProgressLiveActivity)
            } header: {
                Text("进度显示")
            } footer: {
                Text("常驻通知会按设定间隔合并更新队列进度；灵动岛开关会启用实时活动，支持的 iPhone 会在灵动岛显示。")
            }
            #endif

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ZIP 文件名格式")
                        .font(.subheadline)

                    TextField(DownloadSettingsKey.defaultArchiveFileNameTemplate, text: $archiveFileNameTemplate)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                }

                Button {
                    archiveFileNameTemplate = DownloadSettingsKey.defaultArchiveFileNameTemplate
                } label: {
                    Label("恢复默认格式", systemImage: "arrow.counterclockwise")
                }
                .disabled(archiveFileNameTemplate == DownloadSettingsKey.defaultArchiveFileNameTemplate)
            } header: {
                Text("导出")
            } footer: {
                Text("留空时使用漫画标题。可用：{title}、{id}、{platform}、{date}。")
            }

            Section {
                IntegerSettingsInputRow(title: "同时下载数", value: $concurrentDownloadCount, lowerBound: 1, upperBound: 6)
                IntegerSettingsInputRow(title: "图片重试", value: $imageRetryCount, unit: "次", lowerBound: 0, upperBound: 8)
            } header: {
                Text("任务")
            } footer: {
                Text("同时下载数会保存为下载队列的并发配置。")
            }

            Section {
                Toggle("启用限速", isOn: $speedLimitEnabled)

                if speedLimitEnabled {
                    IntegerSettingsInputRow(title: "速度上限", value: $speedLimitKBPerSecond, unit: "KB/s", lowerBound: 64, upperBound: 10240)
                }
            } header: {
                Text("限速")
            } footer: {
                Text("限速会应用到之后的图片下载。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("下载")
        .picaxHidesTabBar()
        #if os(iOS)
        .onChange(of: showsProgressNotifications) { _, _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: showsProgressLiveActivity) { _, _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: progressNotificationUpdateIntervalSeconds) { _, _ in
            downloadService.refreshProgressPresentation()
        }
        #endif
    }
}

private struct StorageManagementView: View {
    @EnvironmentObject private var downloadService: DownloadService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @AppStorage(ImageCacheSettingsKey.maxDiskSizeMB) private var maxDiskSizeMB = ImageCacheService.defaultMaxDiskSizeMB
    @AppStorage(DetailCacheSettingsKey.isEnabled) private var detailCacheEnabled = true
    @AppStorage(DetailCacheSettingsKey.maxDiskSizeMB) private var maxDetailCacheDiskSizeMB = ComicDetailCacheService.defaultMaxDiskSizeMB
    @State private var showsClearCacheConfirmation = false
    @State private var showsClearDetailCacheConfirmation = false
    @State private var showsClearDownloadsConfirmation = false
    @State private var usage = ImageCacheUsage(memoryBytes: 0, diskBytes: 0)
    @State private var detailCacheUsage = ComicDetailCacheUsage(diskBytes: 0)
    @State private var downloadUsage = DownloadStorageUsage(filesBytes: 0, recordsBytes: 0, tasksBytes: 0)

    var body: some View {
        List {
            Section("总览") {
                SettingsValueRow(title: "总占用", value: ImageCacheService.formattedSize(totalDiskUsage))
                SettingsValueRow(title: "图片缓存", value: ImageCacheService.formattedSize(usage.diskBytes))
                SettingsValueRow(title: "详情缓存", value: ImageCacheService.formattedSize(detailCacheUsage.diskBytes))
                SettingsValueRow(title: "下载文件", value: ImageCacheService.formattedSize(downloadUsage.filesBytes))
                SettingsValueRow(title: "本地数据", value: ImageCacheService.formattedSize(localDataBytes))
            }

            Section {
                SettingsValueRow(title: "当前占用", value: ImageCacheService.formattedSize(usage.diskBytes))

                IntegerSettingsInputRow(
                    title: "最大缓存",
                    value: $maxDiskSizeMB,
                    unit: "MB",
                    lowerBound: 50
                )
            } header: {
                Text("图片缓存")
            } footer: {
                Text("封面、分类图和阅读图片会优先使用已缓存的数据。调整容量后会应用到之后的图片请求。")
            }

            Section {
                Toggle("启用详情缓存", isOn: $detailCacheEnabled)
                SettingsValueRow(title: "当前占用", value: ImageCacheService.formattedSize(detailCacheUsage.diskBytes))

                IntegerSettingsInputRow(
                    title: "最大缓存",
                    value: $maxDetailCacheDiskSizeMB,
                    unit: "MB",
                    lowerBound: 5
                )
            } header: {
                Text("详情缓存")
            } footer: {
                Text("开启后，第二次打开同一漫画会先显示已缓存的基础详情，再从网络补齐章节和相关推荐。章节、相关推荐和 PicACG 上传者信息不会保存到详情缓存。")
            }

            Section("下载") {
                SettingsValueRow(title: "已下载漫画", value: "\(downloadService.records.count) 部")
                SettingsValueRow(title: "下载队列", value: "\(downloadService.tasks.count) 个任务")
                SettingsValueRow(title: "文件占用", value: ImageCacheService.formattedSize(downloadUsage.filesBytes))
                SettingsValueRow(title: "记录占用", value: ImageCacheService.formattedSize(downloadUsage.recordsBytes))
                SettingsValueRow(title: "队列占用", value: ImageCacheService.formattedSize(downloadUsage.tasksBytes))
            }

            Section("阅读历史") {
                SettingsValueRow(title: "记录数量", value: "\(readingHistory.records.count) 条")
                SettingsValueRow(title: "记录占用", value: ImageCacheService.formattedSize(historyBytes))
                SettingsValueRow(title: "阅读时长", value: ImageCacheService.formattedSize(durationBytes))
            }

            Section("清理") {
                Button(role: .destructive) {
                    showsClearCacheConfirmation = true
                } label: {
                    Label("清空图片缓存", systemImage: "trash")
                }

                Button(role: .destructive) {
                    showsClearDetailCacheConfirmation = true
                } label: {
                    Label("清空详情缓存", systemImage: "trash")
                }

                Button(role: .destructive) {
                    showsClearDownloadsConfirmation = true
                } label: {
                    Label("删除已下载文件", systemImage: "trash")
                }
                .disabled(downloadService.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("存储管理")
        .picaxHidesTabBar()
        .onAppear {
            if maxDiskSizeMB <= 0 {
                maxDiskSizeMB = ImageCacheService.defaultMaxDiskSizeMB
            }
            if maxDetailCacheDiskSizeMB <= 0 {
                maxDetailCacheDiskSizeMB = ComicDetailCacheService.defaultMaxDiskSizeMB
            }
            ImageCacheService.configure()
            ComicDetailCacheService.configure()
            Task {
                await refreshStorageUsage()
            }
        }
        .onChange(of: maxDiskSizeMB) { _, _ in
            ImageCacheService.configure()
            Task {
                await refreshStorageUsage()
            }
        }
        .onChange(of: detailCacheEnabled) { _, _ in
            ComicDetailCacheService.configure()
            Task {
                await refreshStorageUsage()
            }
        }
        .onChange(of: maxDetailCacheDiskSizeMB) { _, _ in
            ComicDetailCacheService.configure()
            Task {
                await refreshStorageUsage()
            }
        }
        .alert("清空图片缓存？", isPresented: $showsClearCacheConfirmation) {
            Button("清空缓存", role: .destructive) {
                ImageCacheService.clear()
                Task {
                    await refreshStorageUsage()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地缓存的封面、分类图和阅读图片，不会影响下载、收藏或历史记录。")
        }
        .alert("清空详情缓存？", isPresented: $showsClearDetailCacheConfirmation) {
            Button("清空缓存", role: .destructive) {
                ComicDetailCacheService.clear()
                Task {
                    await refreshStorageUsage()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地缓存的漫画基础详情，不会影响下载、收藏或历史记录。")
        }
        .alert("删除所有已下载文件？", isPresented: $showsClearDownloadsConfirmation) {
            Button("删除已下载文件", role: .destructive) {
                downloadService.clearFinishedDownloads()
                Task {
                    await refreshStorageUsage()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地下载的图片和下载完成记录，不会影响历史记录、收藏和平台账号。")
        }
    }

    private var historyBytes: Int {
        PicaXSQLiteStore.bytes(for: .readingHistory)
    }

    private var durationBytes: Int {
        PicaXSQLiteStore.bytes(for: .readingDuration)
    }

    private var localDataBytes: Int64 {
        Int64(historyBytes + durationBytes + downloadUsage.metadataBytes)
    }

    private var totalDiskUsage: Int64 {
        Int64(usage.diskBytes + detailCacheUsage.diskBytes) + downloadUsage.filesBytes + localDataBytes
    }

    @MainActor
    private func refreshStorageUsage() async {
        usage = ImageCacheService.usage
        detailCacheUsage = ComicDetailCacheService.usage
        downloadUsage = await downloadService.storageUsage()
    }
}

private struct BackupSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var accountService: AccountService
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var readLater: ReadLaterService
    @EnvironmentObject private var readingDuration: ReadingDurationService
    @EnvironmentObject private var downloadService: DownloadService
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    @EnvironmentObject private var searchHistory: SearchHistoryService

    @State private var selectedBackupContent = BackupContentKind.defaultSelection
    @State private var isPreparingExport = false
    @State private var isPreparingImport = false
    @State private var isImporting = false
    @State private var exportDocument = PicaXBackupDocument()
    @State private var exportFileName = "PicaX-Backup"
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var activeImportSource = BackupImportSource.picax
    @State private var pendingImport: BackupImportPreview?
    @State private var operationResult: BackupOperationResult?

    var body: some View {
        List {
            Section {
                ForEach(BackupContentKind.allCases) { content in
                    Toggle(isOn: backupContentBinding(for: content)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(content.title)
                            Text(content.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("导出内容")
            } footer: {
                Text("选择要放进备份的内容。未选择的内容不会导出，也不会在覆盖导入时被清空。")
            }

            Section {
                Button {
                    Task {
                        await prepareExport()
                    }
                } label: {
                    if isPreparingExport {
                        HStack {
                            ProgressView()
                            Text("正在准备备份")
                        }
                    } else {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting || selectedBackupContent.isEmpty)
            } footer: {
                Text(selectedBackupContent.isEmpty ? "至少选择一项内容后才能导出。" : "备份文件会保存为 .picax。")
            }

            Section {
                Button {
                    activeImportSource = .picaComic
                    showsImporter = true
                } label: {
                    if isPreparingImport, activeImportSource == .picaComic {
                        HStack {
                            ProgressView()
                            Text("正在读取 PicaComic 备份")
                        }
                    } else {
                        Label("从 PicaComic 备份导入", systemImage: "tray.and.arrow.down")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting)

                Button {
                    activeImportSource = .picax
                    showsImporter = true
                } label: {
                    if isPreparingImport, activeImportSource == .picax {
                        HStack {
                            ProgressView()
                            Text("正在读取备份")
                        }
                    } else if isImporting {
                        HStack {
                            ProgressView()
                            Text("正在导入")
                        }
                    } else {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isPreparingExport || isPreparingImport || isImporting)
            } footer: {
                Text("导入时可以选择完全覆盖或合并本地数据。合并会保留本地已有设置，并合并历史、收藏、账号、屏蔽词和下载记录。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("备份与恢复")
        .picaxHidesTabBar()
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .picaxBackup,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                operationResult = BackupOperationResult(title: "导出完成", message: "备份文件已保存。")
            case .failure(let error):
                operationResult = BackupOperationResult(title: "导出失败", message: error.localizedDescription)
            }
        }
        .backupDocumentImporter(
            isPresented: $showsImporter,
            allowedContentTypes: activeImportSource.allowedContentTypes
        ) { result in
            handleImporterResult(result)
        }
        .sheet(item: $pendingImport) { preview in
            BackupImportPreviewSheet(
                preview: preview,
                isImporting: isImporting,
                onCancel: {
                    pendingImport = nil
                },
                onOverwrite: { includedContent in
                    Task {
                        await importBackup(preview, mode: .overwrite, includedContent: includedContent)
                    }
                },
                onMerge: { includedContent in
                    Task {
                        await importBackup(preview, mode: .merge, includedContent: includedContent)
                    }
                }
            )
        }
        .alert(item: $operationResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func backupContentBinding(for content: BackupContentKind) -> Binding<Bool> {
        Binding {
            selectedBackupContent.contains(content)
        } set: { isSelected in
            if isSelected {
                selectedBackupContent.insert(content)
            } else {
                selectedBackupContent.remove(content)
            }
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            exportDocument = try await BackupService.makeDocument(includedContent: selectedBackupContent)
            exportFileName = "PicaX-Backup-\(Self.fileNameFormatter.string(from: Date())).picax"
            showsExporter = true
        } catch {
            operationResult = BackupOperationResult(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        let source = activeImportSource

        do {
            guard let url = try result.get().first else { return }
            guard source.accepts(url) else {
                operationResult = BackupOperationResult(title: source.failureTitle, message: source.invalidFileMessage)
                return
            }
            Task {
                await loadBackupPreview(from: url, source: source)
            }
        } catch {
            operationResult = BackupOperationResult(title: source.failureTitle, message: error.localizedDescription)
        }
    }

    @MainActor
    private func loadBackupPreview(from url: URL, source: BackupImportSource) async {
        guard !isPreparingImport else { return }
        isPreparingImport = true
        defer { isPreparingImport = false }

        do {
            let data = try await Self.readSecurityScopedData(from: url)
            pendingImport = try source.preview(from: data)
        } catch {
            operationResult = BackupOperationResult(title: source.failureTitle, message: error.localizedDescription)
        }
    }

    private static func readSecurityScopedData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try Data(contentsOf: url)
        }.value
    }

    @MainActor
    private func importBackup(_ preview: BackupImportPreview, mode: BackupImportMode, includedContent: Set<BackupContentKind>) async {
        guard !isImporting else { return }
        isImporting = true
        defer {
            isImporting = false
            self.pendingImport = nil
        }

        do {
            let backup = BackupService.filteredBackup(preview.backup, includedContent: includedContent)
            try await BackupService.importBackup(backup, mode: mode)
            reloadServicesAfterImport()
            operationResult = BackupOperationResult(title: "导入完成", message: mode == .overwrite ? "备份已覆盖本地数据。" : "备份已与本地数据合并。")
        } catch {
            operationResult = BackupOperationResult(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func reloadServicesAfterImport() {
        appSettings.reloadFromDefaults()
        accountService.reloadFromStore()
        platformAccounts.reloadFromDefaults()
        readingHistory.reloadFromDefaults()
        readLater.reloadFromDefaults()
        readingDuration.reloadFromDefaults()
        downloadService.reloadFromDefaults()
        blockingKeywords.reloadFromDefaults()
        searchHistory.reloadFromDefaults()
        ImageCacheService.configure()
        ComicDetailCacheService.configure()
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum BackupImportSource {
    case picax
    case picaComic

    var allowedContentTypes: [UTType] {
        switch self {
        case .picax:
            [.picaxBackup]
        case .picaComic:
            [.picaComicBackup]
        }
    }

    var expectedFileExtension: String {
        switch self {
        case .picax:
            "picax"
        case .picaComic:
            "picadata"
        }
    }

    var invalidFileMessage: String {
        switch self {
        case .picax:
            "请选择 .picax 备份文件。"
        case .picaComic:
            "请选择 .picadata 备份文件。"
        }
    }

    var failureTitle: String {
        switch self {
        case .picax:
            "读取备份失败"
        case .picaComic:
            "读取 PicaComic 备份失败"
        }
    }

    func accepts(_ url: URL) -> Bool {
        url.pathExtension.compare(expectedFileExtension, options: [.caseInsensitive]) == .orderedSame
    }

    func preview(from data: Data) throws -> BackupImportPreview {
        switch self {
        case .picax:
            try BackupService.preview(from: data)
        case .picaComic:
            try PicaComicBackupImporter.preview(from: data)
        }
    }
}

private extension View {
    @ViewBuilder
    func backupDocumentImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
#if os(iOS)
        sheet(isPresented: isPresented) {
            BackupDocumentPicker(allowedContentTypes: allowedContentTypes) { result in
                isPresented.wrappedValue = false
                onCompletion(result)
            }
        }
#else
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: onCompletion
        )
#endif
    }
}

#if os(iOS)
private struct BackupDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<[URL], Error>) -> Void

        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.success([]))
        }
    }
}
#endif

private struct BackupImportPreviewSheet: View {
    let preview: BackupImportPreview
    let isImporting: Bool
    let onCancel: () -> Void
    let onOverwrite: (Set<BackupContentKind>) -> Void
    let onMerge: (Set<BackupContentKind>) -> Void
    @State private var selectedContent: Set<BackupContentKind>

    init(
        preview: BackupImportPreview,
        isImporting: Bool,
        onCancel: @escaping () -> Void,
        onOverwrite: @escaping (Set<BackupContentKind>) -> Void,
        onMerge: @escaping (Set<BackupContentKind>) -> Void
    ) {
        self.preview = preview
        self.isImporting = isImporting
        self.onCancel = onCancel
        self.onOverwrite = onOverwrite
        self.onMerge = onMerge
        _selectedContent = State(initialValue: preview.backup.contentSelection)
    }

    private var includedContent: [BackupContentKind] {
        BackupContentKind.allCases.filter { preview.backup.contentSelection.contains($0) }
    }

    private var canImport: Bool {
        !isImporting && !selectedContent.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("来源", value: preview.title)
                    LabeledContent("创建时间", value: Self.dateFormatter.string(from: preview.backup.createdAt))
                    LabeledContent("本地数据", value: "\(preview.backup.defaults.count) 项")
                    LabeledContent("漫画文件", value: "\(preview.backup.downloadFiles.count) 个")
                }

                Section {
                    HStack {
                        Button("全选") {
                            selectedContent = Set(includedContent)
                        }
                        .disabled(isImporting || selectedContent.count == includedContent.count)

                        Spacer()

                        Button("清空") {
                            selectedContent.removeAll()
                        }
                        .disabled(isImporting || selectedContent.isEmpty)
                    }

                    ForEach(includedContent) { content in
                        Toggle(isOn: importContentBinding(for: content)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(content.title)
                                Text(content.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isImporting)
                    }
                } header: {
                    Text("导入内容")
                } footer: {
                    Text(selectedContent.isEmpty ? "至少选择一项内容后才能导入。" : "默认全选；关闭的内容不会被导入，覆盖本地时也不会清空对应本地数据。")
                }

                Section {
                    Button {
                        onMerge(selectedContent)
                    } label: {
                        if isImporting {
                            HStack {
                                ProgressView()
                                Text("正在导入")
                            }
                        } else {
                            Label("合并导入", systemImage: "plus.circle")
                        }
                    }
                    .disabled(!canImport)

                    Button(role: .destructive) {
                        onOverwrite(selectedContent)
                    } label: {
                        Label("覆盖本地", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!canImport)
                } footer: {
                    Text("合并会保留本地已有内容；覆盖只会替换所选内容。")
                }
            }
            .navigationTitle(preview.title)
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                    .disabled(isImporting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func importContentBinding(for content: BackupContentKind) -> Binding<Bool> {
        Binding {
            selectedContent.contains(content)
        } set: { isSelected in
            if isSelected {
                selectedContent.insert(content)
            } else {
                selectedContent.remove(content)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ExploreSettingsView: View {
    @AppStorage("settings.explore.defaultPlatform") private var defaultPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage("settings.explore.rememberSelectedPlatform") private var rememberSelectedPlatform = true
    @AppStorage("settings.explore.lastSelectedPlatform") private var lastSelectedPlatformID = ComicPlatform.picacg.rawValue

    var body: some View {
        List {
            Section("平台") {
                Picker("默认选中平台", selection: $defaultPlatformID) {
                    ForEach(ComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform.rawValue)
                    }
                }

                Toggle("记住选中平台", isOn: $rememberSelectedPlatform)
                    .onChange(of: rememberSelectedPlatform) { _, newValue in
                        if !newValue {
                            lastSelectedPlatformID = defaultPlatformID
                        }
                    }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("发现页")
        .picaxHidesTabBar()
    }
}

private struct SearchSettingsView: View {
    @EnvironmentObject private var searchHistory: SearchHistoryService
    @AppStorage(SearchSettingsKey.focusesSearchFieldOnOpen) private var focusesSearchFieldOnOpen = false
    @AppStorage(SearchSettingsKey.enablesSearchSuggestions) private var enablesSearchSuggestions = true
    @AppStorage(SearchSettingsKey.suggestionSelectionBehavior) private var suggestionSelectionBehavior = SearchSuggestionSelectionBehavior.fill.rawValue
    @AppStorage(SearchSettingsKey.defaultTargetMode) private var defaultTargetMode = SearchDefaultTargetMode.platform.rawValue
    @AppStorage(SearchSettingsKey.defaultPlatform) private var defaultSearchPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage(SearchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = ComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(SearchHistorySettingsKey.isEnabled) private var savesSearchHistory = true
    @AppStorage(SearchHistorySettingsKey.maxRecords) private var maxSearchHistoryRecords = 50
    @State private var showsClearSearchHistoryConfirmation = false

    var body: some View {
        List {
            Section {
                Picker("默认搜索源", selection: $defaultTargetMode) {
                    ForEach(SearchDefaultTargetMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }

                if selectedDefaultTargetMode == .platform {
                    Picker("默认平台", selection: $defaultSearchPlatformID) {
                        ForEach(ComicPlatform.allCases) { platform in
                            Text(platform.title)
                                .tag(platform.rawValue)
                        }
                    }
                } else {
                    ForEach(ComicPlatform.allCases) { platform in
                        Button {
                            toggleDefaultAggregatePlatform(platform)
                        } label: {
                            Label(
                                platform.title,
                                systemImage: defaultAggregatePlatforms.contains(platform) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("从底部标签栏进入搜索页时使用这里的默认源；从标签、分类或详情进入时仍会使用来源平台。")
            }

            Section {
                Toggle("进入搜索页自动聚焦", isOn: $focusesSearchFieldOnOpen)
            } footer: {
                Text("关闭后，打开搜索页不会自动弹出键盘；从标签或已下载详情进入并带有关键词时仍会自动搜索。")
            }

            Section {
                Toggle("搜索补全", isOn: $enablesSearchSuggestions)

                if enablesSearchSuggestions {
                    Picker("点击补全后", selection: $suggestionSelectionBehavior) {
                        ForEach(SearchSuggestionSelectionBehavior.allCases) { behavior in
                            Text(behavior.title)
                                .tag(behavior.rawValue)
                        }
                    }
                }
            } footer: {
                Text("开启后，E-Hentai 和 NHentai 搜索会根据本地标签数据提供补全建议；填入模式会在关键词末尾自动加空格。")
            }

            Section {
                Toggle("保存搜索历史", isOn: $savesSearchHistory)

                if savesSearchHistory {
                    IntegerSettingsInputRow(title: "最多保留", value: $maxSearchHistoryRecords, unit: "条", lowerBound: 1, upperBound: 200)
                }
            } footer: {
                Text("搜索历史会记录关键词和平台选择，用于在搜索页快速重新搜索。")
            }

            Section {
                Button(role: .destructive) {
                    showsClearSearchHistoryConfirmation = true
                } label: {
                    Label("清空搜索历史", systemImage: "trash")
                }
                .disabled(searchHistory.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("搜索")
        .picaxHidesTabBar()
        .onChange(of: maxSearchHistoryRecords) { _, _ in
            searchHistory.trimToCurrentLimit()
        }
        .alert("清空搜索历史？", isPresented: $showsClearSearchHistoryConfirmation) {
            Button("清空", role: .destructive) {
                searchHistory.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本地保存的搜索历史，不会影响收藏、阅读历史或下载。")
        }
    }

    private var selectedDefaultTargetMode: SearchDefaultTargetMode {
        SearchDefaultTargetMode(rawValue: defaultTargetMode) ?? .platform
    }

    private var defaultAggregatePlatforms: Set<ComicPlatform> {
        let platforms = Set(defaultAggregatePlatformIDs.split(separator: ",").compactMap { ComicPlatform(rawValue: String($0)) })
        return platforms.isEmpty ? Set(ComicPlatform.allCases) : platforms
    }

    private func toggleDefaultAggregatePlatform(_ platform: ComicPlatform) {
        var platforms = defaultAggregatePlatforms
        if platforms.contains(platform) {
            guard platforms.count > 1 else { return }
            platforms.remove(platform)
        } else {
            platforms.insert(platform)
        }
        defaultAggregatePlatformIDs = ComicPlatform.allCases
            .filter { platforms.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

private struct ComicListSettingsView: View {
    @AppStorage(ComicListSettingsKey.showsReadingProgress) private var showsReadingProgress = true
    @AppStorage(ComicListSettingsKey.showsFavoriteState) private var showsFavoriteState = true
    @AppStorage(ComicListSettingsKey.showsTags) private var showsTags = true
    @AppStorage(ComicListSettingsKey.maxVisibleTags) private var maxVisibleTags = 5
    @AppStorage(ComicListSettingsKey.showsPopularity) private var showsPopularity = true
    @AppStorage(ReadFilterSettingsKey.hidesReadComicsInLists) private var hidesReadComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hiddenProgressThreshold) private var hiddenProgressThreshold = 100

    var body: some View {
        List {
            Section {
                Toggle("显示阅读进度", isOn: $showsReadingProgress)
                Toggle("显示收藏状态", isOn: $showsFavoriteState)
                Toggle("显示标签", isOn: $showsTags)

                if showsTags {
                    IntegerSettingsInputRow(title: "最多显示", value: $maxVisibleTags, unit: "个标签", lowerBound: 1, upperBound: 10)
                }

                Toggle("显示热度", isOn: $showsPopularity)
            } header: {
                Text("显示内容")
            } footer: {
                Text("这些开关只影响漫画列表条目上的附加内容，不会影响阅读记录、收藏数据或详情页。")
            }

            Section {
                Toggle("隐藏已读内容", isOn: $hidesReadComicsInLists)

                if hidesReadComicsInLists {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("隐藏阈值")
                            Spacer()
                            Text("\(hiddenProgressThreshold)%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: hiddenProgressThresholdBinding, in: 0...100, step: 5)
                    }
                }
            } header: {
                Text("已读隐藏")
            } footer: {
                Text("开启后，普通漫画列表会隐藏阅读进度达到阈值的漫画；收藏夹、历史记录和已下载页面不受影响。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("漫画列表")
        .picaxHidesTabBar()
    }

    private var hiddenProgressThresholdBinding: Binding<Double> {
        Binding {
            Double(hiddenProgressThreshold)
        } set: { value in
            hiddenProgressThreshold = min(max(Int(value.rounded()), 0), 100)
        }
    }
}

private struct ComicDetailSettingsView: View {
    @AppStorage(DetailSettingsKey.usesCoverAccent) private var usesCoverAccent = true
    @AppStorage(DetailSettingsKey.chapterSortOrder) private var chapterSortOrder = ComicDetailChapterSortOrder.ascending.rawValue
    @AppStorage(DetailSettingsKey.showsChaptersAsSection) private var showsChaptersAsSection = false
    @AppStorage(DetailSettingsKey.contentOrder) private var contentOrderRaw = ComicDetailContentSectionKind.defaultRawValue
    @State private var contentOrder = ComicDetailContentSectionKind.defaultOrder

    var body: some View {
        List {
            Section {
                Toggle("阅读按钮使用封面颜色", isOn: $usesCoverAccent)
            } footer: {
                Text("开启后，详情页会根据封面提取颜色，用于阅读按钮和章节按钮。关闭后使用漫画来源的固定颜色。")
            }

            Section {
                Picker("章节排序", selection: $chapterSortOrder) {
                    ForEach(ComicDetailChapterSortOrder.allCases) { order in
                        Text(order.title)
                            .tag(order.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("单独分区显示章节", isOn: $showsChaptersAsSection)
            } footer: {
                Text("开启后，章节会作为详情页里的独立分区显示，封面旁不再显示章节按钮。")
            }

            Section {
                ForEach(contentOrder) { section in
                    Label(section.title, systemImage: section.systemImage)
                }
                .onMove(perform: moveContentSections)

                Button("恢复默认排序") {
                    contentOrder = ComicDetailContentSectionKind.defaultOrder
                    saveContentOrder()
                }
            } header: {
                Text("内容顺序")
            } footer: {
                Text("点按编辑后拖动项目调整详情页内容显示顺序。章节需要开启单独分区后才会显示在此顺序中。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("漫画详情")
        .picaxHidesTabBar()
        #if os(iOS)
        .toolbar {
            EditButton()
        }
        #endif
        .onAppear {
            contentOrder = ComicDetailContentSectionKind.normalizedOrder(from: contentOrderRaw)
            saveContentOrder()
        }
        .onChange(of: contentOrderRaw) { _, newValue in
            contentOrder = ComicDetailContentSectionKind.normalizedOrder(from: newValue)
        }
    }

    private func moveContentSections(from source: IndexSet, to destination: Int) {
        contentOrder.move(fromOffsets: source, toOffset: destination)
        saveContentOrder()
    }

    private func saveContentOrder() {
        contentOrderRaw = ComicDetailContentSectionKind.rawValue(for: contentOrder)
    }
}

private struct BlockingKeywordSettingsView: View {
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    @State private var selectedScope: BlockingKeywordScope = .common
    @State private var showsDescendingOrder = true
    @State private var addScope: BlockingKeywordScope?

    var body: some View {
        List {
            Section {
                Picker("分区", selection: $selectedScope) {
                    ForEach(BlockingKeywordScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(scopeFooter)
            }

            Section(selectedScope.title) {
                if displayedKeywords.isEmpty {
                    ContentUnavailableView("暂无屏蔽词", systemImage: "eye.slash")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedKeywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .onDelete { offsets in
                        blockingKeywords.remove(at: offsets, displayedKeywords: displayedKeywords, scope: selectedScope)
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("关键词屏蔽")
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    showsDescendingOrder.toggle()
                } label: {
                    Image(systemName: showsDescendingOrder ? "arrow.down" : "arrow.up")
                }
                .accessibilityLabel("切换显示顺序")

                Button {
                    addScope = selectedScope
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加屏蔽词")
            }
        }
        .sheet(item: $addScope) { scope in
            BlockingKeywordAddSheet(scope: scope)
        }
    }

    private var displayedKeywords: [String] {
        let keywords = blockingKeywords.keywords(for: selectedScope)
        return showsDescendingOrder ? Array(keywords.reversed()) : keywords
    }

    private var scopeFooter: String {
        switch selectedScope {
        case .common:
            "通用屏蔽词会在漫画列表加载后生效，支持 title:、uploader:、tag: 前缀；未带前缀时匹配标题、作者和标签。"
        case .jmComic:
            "JMComic 专用屏蔽词会在 JM 搜索时自动追加为排除关键词。"
        }
    }
}

private struct BlockingKeywordAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    let scope: BlockingKeywordScope
    @State private var keyword = ""
    @State private var feedback: BlockingKeywordFeedback?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("屏蔽关键词", text: $keyword)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                } footer: {
                    Text(helpText)
                }
            }
            .navigationTitle("添加屏蔽词")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addKeyword()
                    }
                }
            }
            .alert(item: $feedback) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var helpText: String {
        switch scope {
        case .common:
            "可直接输入关键词，也可使用 title:关键词、uploader:关键词、tag:关键词 限定匹配字段。"
        case .jmComic:
            "这里输入原始标签或关键词，JMComic 搜索时会自动使用 -关键词 排除。"
        }
    }

    private func addKeyword() {
        let result = blockingKeywords.add(keyword, scope: scope)
        if result.isSuccess {
            dismiss()
        } else {
            feedback = result
        }
    }
}

private struct ReaderSettingsView: View {
    @AppStorage(ReaderSettingsKey.progressStyle) private var progressStyle = ReaderProgressStyle.circular.rawValue
    @AppStorage(ReaderSettingsKey.progressPosition) private var progressPosition = ReaderProgressPosition.trailing.rawValue
    @AppStorage(ReaderSettingsKey.showsPageLabel) private var showsPageLabel = true
    @AppStorage(ReaderSettingsKey.progressFollowsUIVisibility) private var progressFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.progressTapSelectionEnabled) private var progressTapSelectionEnabled = false
    @AppStorage(ReaderSettingsKey.progressBackgroundOpacity) private var progressBackgroundOpacity = 0.78
    @AppStorage(ReaderSettingsKey.progressBottomInset) private var progressBottomInset = 0.0
    @AppStorage(ReaderSettingsKey.readingMode) private var readingMode = ReaderReadingMode.topToBottomContinuous.rawValue
    @AppStorage(ReaderSettingsKey.imageSpacing) private var imageSpacing = 0.0
    @AppStorage(ReaderSettingsKey.firstImageTopPadding) private var firstImageTopPadding = 115.0
    @AppStorage(ReaderSettingsKey.lastImageBottomPadding) private var lastImageBottomPadding = 0.0
    @AppStorage(ReaderSettingsKey.preloadImageCount) private var preloadImageCount = 3
    @AppStorage(ReaderSettingsKey.pagedPreloadDelay) private var pagedPreloadDelay = 1.2
    @AppStorage(ReaderSettingsKey.imageRetryCount) private var imageRetryCount = 2
    @AppStorage(ReaderSettingsKey.imageRetryInterval) private var imageRetryInterval = 1.0
    @AppStorage(ReaderSettingsKey.reducesImageBrightnessInDarkMode) private var reducesImageBrightnessInDarkMode = false
    @AppStorage(ReaderSettingsKey.hidesStatusBar) private var hidesStatusBar = false
    @AppStorage(ReaderSettingsKey.uiToggleMode) private var uiToggleMode = ReaderUIToggleMode.single.rawValue
    @AppStorage(ReaderSettingsKey.tapPagingEnabled) private var tapPagingEnabled = false
    @AppStorage(ReaderSettingsKey.tapPagingInverted) private var tapPagingInverted = false
    @AppStorage(ReaderSettingsKey.tapPagingEdgePercent) private var tapPagingEdgePercent = 28
    @AppStorage(ReaderSettingsKey.tapPagingDistancePercent) private var tapPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.pinchZoomEnabled) private var pinchZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomEnabled) private var doubleTapZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomScale) private var doubleTapZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.longPressZoomEnabled) private var longPressZoomEnabled = true
    @AppStorage(ReaderSettingsKey.longPressZoomScale) private var longPressZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.autoPagingInterval) private var autoPagingInterval = 6.0
    @AppStorage(ReaderSettingsKey.autoPagingDistancePercent) private var autoPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.autoPagingTurnsChapter) private var autoPagingTurnsChapter = true
    @AppStorage(ReaderSettingsKey.showsChapterCommentsAtEnd) private var showsChapterCommentsAtEnd = false
    @AppStorage(ReaderSettingsKey.showsSystemStatus) private var showsSystemStatus = false
    @AppStorage(ReaderSettingsKey.systemStatusFollowsUIVisibility) private var systemStatusFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.systemStatusStyle) private var systemStatusStyle = ReaderSystemStatusStyle.compact.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusPosition) private var systemStatusPosition = ReaderOverlayPosition.bottomLeading.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusBottomInset) private var systemStatusBottomInset = 0.0
    @AppStorage(ReaderSettingsKey.usesProgressGlassBackground) private var usesProgressGlassBackground = false
    @AppStorage(ReaderSettingsKey.usesSystemStatusGlassBackground) private var usesSystemStatusGlassBackground = false
    @AppStorage(ReaderSettingsKey.showsReadingListBookToast) private var showsReadingListBookToast = true
    @AppStorage(ReaderSettingsKey.showsReadingListLoadingToast) private var showsReadingListLoadingToast = true
    @AppStorage(ReaderSettingsKey.readingListAutoAdvancesAtBoundary) private var readingListAutoAdvancesAtBoundary = true
    @AppStorage(ReaderSettingsKey.visibilityDefaultsVersion) private var visibilityDefaultsVersion = 0

    var body: some View {
        List {
            Section("预览") {
                ReaderSettingsPreview(
                    style: selectedStyle,
                    position: selectedPosition,
                    showsPageLabel: showsPageLabel,
                    backgroundOpacity: progressBackgroundOpacity,
                    progressBottomInset: progressBottomInset,
                    imageSpacing: imageSpacing,
                    firstImageTopPadding: firstImageTopPadding,
                    lastImageBottomPadding: lastImageBottomPadding,
                    showsSystemStatus: showsSystemStatus,
                    systemStatusStyle: selectedSystemStatusStyle,
                    systemStatusPosition: selectedSystemStatusPosition,
                    systemStatusBottomInset: systemStatusBottomInset,
                    usesProgressGlassBackground: usesProgressGlassBackground,
                    usesSystemStatusGlassBackground: usesSystemStatusGlassBackground
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            Section("状态栏") {
                Toggle("隐藏状态栏", isOn: $hidesStatusBar)
            }

            Section("阅读") {
                Picker("阅读方式", selection: $readingMode) {
                    ForEach(ReaderReadingMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }

                Text(selectedReadingMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("预加载延迟 \(pagedPreloadDelay, specifier: "%.1f") 秒")
                    Slider(value: $pagedPreloadDelay, in: 0...5, step: 0.1)
                }

                Toggle("深色模式下降低图片亮度", isOn: $reducesImageBrightnessInDarkMode)
            }

            Section("自动翻页") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("翻页间隔 \(autoPagingInterval, specifier: "%.0f") 秒")
                    Slider(value: $autoPagingInterval, in: 1...30, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("翻页距离 \(autoPagingDistancePercent)% 屏幕高度")
                    Slider(value: autoPagingDistancePercentBinding, in: 10...120, step: 5)
                }
                .disabled(selectedReadingMode != .topToBottomContinuous)

                if selectedReadingMode != .topToBottomContinuous {
                    Text("当前阅读方式会按页切换，自动翻页距离只在连续滚动中生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("自动进入下一章", isOn: $autoPagingTurnsChapter)
            }

            Section {
                Toggle("章节末尾显示评论", isOn: $showsChapterCommentsAtEnd)
            } footer: {
                Text("支持的来源会在每章最后显示评论。已下载漫画会优先使用下载时保存的章节评论。")
            }

            Section {
                Picker("切换控制栏", selection: $uiToggleMode) {
                    ForEach(ReaderUIToggleMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("点按翻页", isOn: $tapPagingEnabled)

                if tapPagingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("点按识别范围 \(tapPagingEdgePercent)%")
                        Slider(value: tapPagingEdgePercentBinding, in: 5...45, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻页距离 \(tapPagingDistancePercent)% 屏幕高度")
                        Slider(value: tapPagingDistancePercentBinding, in: 10...120, step: 5)
                    }
                    .disabled(selectedReadingMode != .topToBottomContinuous)

                    if selectedReadingMode != .topToBottomContinuous {
                        Text("当前阅读方式会直接切页，点按翻页距离只在连续滚动中生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("反转点按翻页", isOn: $tapPagingInverted)
                }

                Toggle("阅读进度跟随控制栏隐藏", isOn: $progressFollowsUIVisibility)

                Toggle("时间电量跟随控制栏隐藏", isOn: $systemStatusFollowsUIVisibility)
                    .disabled(!showsSystemStatus)
            } header: {
                Text("交互")
            } footer: {
                Text("点按翻页开启后，边缘区域翻页，中间区域按“切换控制栏”设置显示或隐藏顶部控制栏。关闭跟随后，对应浮层会在控制栏隐藏时继续显示。")
            }

            Section {
                Toggle("切换时显示加载提示", isOn: $showsReadingListLoadingToast)

                Toggle("切换完成后显示书名", isOn: $showsReadingListBookToast)

                Toggle("章节边界自动切换书籍", isOn: $readingListAutoAdvancesAtBoundary)
            } header: {
                Text("批量阅读")
            } footer: {
                Text("批量阅读切换书籍时会保留当前阅读器并显示加载提示，加载完成后再切换内容。关闭自动切换后，底栏上一章/下一章按钮仍可在书籍边界手动切换。")
            }

            Section {
                Toggle("两指缩放", isOn: $pinchZoomEnabled)

                Toggle("双击缩放", isOn: $doubleTapZoomEnabled)
                    .disabled(selectedUIToggleMode == .double)

                if selectedUIToggleMode == .double {
                    Text("切换控制栏使用双击时，双击缩放会暂停，避免同一手势同时承担两个动作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if doubleTapZoomEnabled && selectedUIToggleMode != .double {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("双击放大 \(doubleTapZoomScale, specifier: "%.1f")x")
                        Slider(value: $doubleTapZoomScale, in: 1.2...5, step: 0.1)
                    }
                }

                Toggle("长按缩放", isOn: $longPressZoomEnabled)

                if longPressZoomEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("长按放大 \(longPressZoomScale, specifier: "%.1f")x")
                        Slider(value: $longPressZoomScale, in: 1.2...5, step: 0.1)
                    }
                }
            } header: {
                Text("缩放")
            } footer: {
                Text("长按缩放为按住临时放大，松开恢复。双击缩放与双击切换控制栏互斥。")
            }

            Section("时间与电量") {
                Toggle("显示时间与电量", isOn: $showsSystemStatus)

                if showsSystemStatus {
                    Picker("状态样式", selection: $systemStatusStyle) {
                        ForEach(ReaderSystemStatusStyle.allCases) { style in
                            Text(style.title)
                                .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("状态位置", selection: $systemStatusPosition) {
                        ForEach(ReaderOverlayPosition.allCases) { position in
                            Text(position.title)
                                .tag(position.rawValue)
                        }
                    }

                    if selectedSystemStatusStyle != .text {
                        Toggle("液体玻璃背景", isOn: $usesSystemStatusGlassBackground)
                    }

                    if selectedSystemStatusPosition.isBottom {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("底部距离 \(Int(systemStatusBottomInset))")
                            Slider(value: $systemStatusBottomInset, in: 0...96, step: 2)
                        }
                    }
                }
            }

            Section("进度") {
                Picker("样式", selection: $progressStyle) {
                    ForEach(ReaderProgressStyle.allCases) { style in
                        Text(style.title)
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("显示位置", selection: $progressPosition) {
                    ForEach(ReaderProgressPosition.allCases) { position in
                        Text(position.title)
                            .tag(position.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("显示页码", isOn: $showsPageLabel)

                Toggle("点击进度选择页码", isOn: $progressTapSelectionEnabled)

                Toggle("液体玻璃背景", isOn: $usesProgressGlassBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Text("底部距离 \(Int(progressBottomInset))")
                    Slider(value: $progressBottomInset, in: 0...120, step: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("浮层透明度 \(Int(progressBackgroundOpacity * 100))%")
                    Slider(value: $progressBackgroundOpacity, in: 0.45...0.95, step: 0.05)
                }
            }

            Section("图片") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("图片间距 \(Int(imageSpacing))")
                    Slider(value: $imageSpacing, in: 0...24, step: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("首图顶部留白 \(Int(firstImageTopPadding))")
                    Slider(value: $firstImageTopPadding, in: 0...160, step: 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("末图底部留白 \(Int(lastImageBottomPadding))")
                    Slider(value: $lastImageBottomPadding, in: 0...160, step: 4)
                }

                IntegerSettingsInputRow(
                    title: "预加载图片",
                    value: $preloadImageCount,
                    unit: "张",
                    lowerBound: 0,
                    upperBound: 15,
                    detail: preloadImageCount == 0 ? "关闭" : nil
                )

                IntegerSettingsInputRow(title: "图片重试次数", value: $imageRetryCount, unit: "次", lowerBound: 0, upperBound: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("重试间隔 \(imageRetryInterval, specifier: "%.1f") 秒")
                    Slider(value: $imageRetryInterval, in: 0.2...10, step: 0.2)
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("阅读器")
        .picaxHidesTabBar()
        .onAppear {
            migrateReaderVisibilityDefaultsIfNeeded()
        }
    }

    private var selectedStyle: ReaderProgressStyle {
        ReaderProgressStyle(rawValue: progressStyle) ?? .circular
    }

    private var selectedPosition: ReaderProgressPosition {
        ReaderProgressPosition(rawValue: progressPosition) ?? .trailing
    }

    private var selectedReadingMode: ReaderReadingMode {
        ReaderReadingMode(rawValue: readingMode) ?? .topToBottomContinuous
    }

    private var selectedUIToggleMode: ReaderUIToggleMode {
        ReaderUIToggleMode(rawValue: uiToggleMode) ?? .single
    }

    private var selectedSystemStatusStyle: ReaderSystemStatusStyle {
        ReaderSystemStatusStyle(rawValue: systemStatusStyle) ?? .compact
    }

    private var selectedSystemStatusPosition: ReaderOverlayPosition {
        ReaderOverlayPosition(rawValue: systemStatusPosition) ?? .bottomLeading
    }

    private var tapPagingEdgePercentBinding: Binding<Double> {
        Binding {
            Double(tapPagingEdgePercent)
        } set: { value in
            tapPagingEdgePercent = min(max(Int(value.rounded()), 5), 45)
        }
    }

    private var autoPagingDistancePercentBinding: Binding<Double> {
        Binding {
            Double(autoPagingDistancePercent)
        } set: { value in
            autoPagingDistancePercent = min(max(Int(value.rounded()), 10), 120)
        }
    }

    private var tapPagingDistancePercentBinding: Binding<Double> {
        Binding {
            Double(tapPagingDistancePercent)
        } set: { value in
            tapPagingDistancePercent = min(max(Int(value.rounded()), 10), 120)
        }
    }

    private func migrateReaderVisibilityDefaultsIfNeeded() {
        if visibilityDefaultsVersion < 1 {
            progressFollowsUIVisibility = false
            systemStatusFollowsUIVisibility = false
            visibilityDefaultsVersion = 1
        }

        if visibilityDefaultsVersion < 2 {
            if progressBottomInset == 16 {
                progressBottomInset = 0
            }
            if systemStatusBottomInset == 16 {
                systemStatusBottomInset = 0
            }
            visibilityDefaultsVersion = 2
        }
    }
}

private struct ReaderSettingsPreview: View {
    let style: ReaderProgressStyle
    let position: ReaderProgressPosition
    let showsPageLabel: Bool
    let backgroundOpacity: Double
    let progressBottomInset: Double
    let imageSpacing: Double
    let firstImageTopPadding: Double
    let lastImageBottomPadding: Double
    let showsSystemStatus: Bool
    let systemStatusStyle: ReaderSystemStatusStyle
    let systemStatusPosition: ReaderOverlayPosition
    let systemStatusBottomInset: Double
    let usesProgressGlassBackground: Bool
    let usesSystemStatusGlassBackground: Bool

    var body: some View {
        ZStack(alignment: position.alignment) {
            VStack(spacing: CGFloat(imageSpacing)) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(height: 118)
                    .padding(.top, CGFloat(firstImageTopPadding * 0.22))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: 86)
                    .padding(.bottom, CGFloat(lastImageBottomPadding * 0.22))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 22, height: 22)
                Spacer()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .frame(width: 86, height: 14)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .frame(maxHeight: .infinity, alignment: .top)

            ReaderProgressOverlay(
                title: "E1/3 · P12/28",
                progress: 0.42,
                style: style,
                showsPageLabel: showsPageLabel,
                backgroundOpacity: backgroundOpacity,
                usesGlassBackground: usesProgressGlassBackground
            )
            .padding(.horizontal, 16)
            .padding(.bottom, progressBottomPadding)

            if showsSystemStatus {
                ReaderSystemStatusOverlay(
                    style: systemStatusStyle,
                    backgroundOpacity: backgroundOpacity,
                    usesGlassBackground: usesSystemStatusGlassBackground
                )
                    .padding(systemStatusInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: systemStatusPosition.alignment)
                    .allowsHitTesting(false)
            }
        }
    }

    private var progressBottomPadding: CGFloat {
        let baseInset = CGFloat(progressBottomInset)
        guard showsSystemStatus else { return baseInset }
        switch (position, systemStatusPosition) {
        case (.leading, .bottomLeading), (.trailing, .bottomTrailing):
            return max(baseInset, CGFloat(systemStatusBottomInset) + systemStatusStyle.bottomClearance)
        default:
            return baseInset
        }
    }

    private var systemStatusInsets: EdgeInsets {
        var insets = systemStatusPosition.edgeInsets
        switch systemStatusPosition {
        case .topLeading, .topTrailing:
            insets.top = 58
        case .bottomLeading, .bottomTrailing:
            break
        }
        switch systemStatusPosition {
        case .topLeading, .topTrailing:
            break
        case .bottomLeading, .bottomTrailing:
            insets.bottom = CGFloat(systemStatusBottomInset)
        }
        return insets
    }
}

private struct NetworkSettingsView: View {
    @AppStorage("settings.network.useProxy") private var useProxy = false
    @AppStorage("settings.network.proxyHost") private var proxyHost = ""
    @AppStorage("settings.network.proxyPort") private var proxyPort = 7890
    @AppStorage("settings.network.retryCount") private var retryCount = 2
    @State private var proxyPortText = ""

    var body: some View {
        List {
            Section {
                Toggle("启用代理", isOn: $useProxy)

                if useProxy {
                    TextField("代理地址", text: $proxyHost)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                        .picaxKeyboardType(.url)
                        .onSubmit {
                            proxyHost = normalizedProxyHost
                        }

                    TextField("端口", text: $proxyPortText)
                        .picaxKeyboardType(.numberPad)
                        .onChange(of: proxyPortText) { _, newValue in
                            updateProxyPort(from: newValue)
                        }

                    if !isProxyPortValid {
                        Text("端口范围为 1-65535")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("代理")
            } footer: {
                Text(proxyFooter)
            }

            Section("连接") {
                IntegerSettingsInputRow(title: "失败重试", value: $retryCount, unit: "次", lowerBound: 0, upperBound: 5)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("网络与代理")
        .picaxHidesTabBar()
        .onAppear {
            proxyPortText = "\(proxyPort)"
        }
        .onDisappear {
            proxyHost = normalizedProxyHost
            if !isProxyPortValid {
                proxyPortText = "\(proxyPort)"
            }
        }
        .onChange(of: useProxy) { _, newValue in
            if newValue, proxyPortText.isEmpty {
                proxyPortText = "\(proxyPort)"
            }
        }
        .onChange(of: proxyPort) { _, newValue in
            proxyPort = min(max(newValue, 1), 65535)
            let text = "\(proxyPort)"
            if proxyPortText != text {
                proxyPortText = text
            }
        }
    }

    private var normalizedProxyHost: String {
        proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isProxyPortValid: Bool {
        guard let value = Int(proxyPortText) else { return false }
        return (1...65535).contains(value)
    }

    private var proxyFooter: String {
        guard useProxy else {
            return "启用后可填写网络代理地址和端口。"
        }
        return normalizedProxyHost.isEmpty ? "请输入代理主机和端口。" : "代理设置会应用到之后创建的网络请求。"
    }

    private func updateProxyPort(from value: String) {
        let filtered = String(value.filter(\.isNumber).prefix(5))
        if filtered != value {
            proxyPortText = filtered
            return
        }
        guard let port = Int(filtered), (1...65535).contains(port) else {
            return
        }
        proxyPort = port
    }
}

private struct HistorySettingsView: View {
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @AppStorage(ReadingHistoryService.Key.isEnabled) private var isEnabled = true
    @AppStorage(ReadingHistoryService.Key.maxRecords) private var maxRecords = 200
    @State private var showsClearConfirmation = false
    @State private var showsClearProgressConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("记录历史记录", isOn: $isEnabled)
                IntegerSettingsInputRow(title: "最多保存", value: $maxRecords, unit: "条", lowerBound: 20, upperBound: 500)
            } header: {
                Text("记录")
            } footer: {
                Text("历史记录保存在本地，包含平台、漫画编号、标题、封面和查看时间。")
            }

            Section {
                Button(role: .destructive) {
                    showsClearProgressConfirmation = true
                } label: {
                    Label("清空阅读进度", systemImage: "bookmark.slash")
                }
                .disabled(!readingHistory.hasAnyReadingProgress)

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label("清空历史记录", systemImage: "trash")
                }
                .disabled(readingHistory.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("历史记录")
        .picaxHidesTabBar()
        .onChange(of: maxRecords) { _, _ in
            readingHistory.trimToCurrentLimit()
        }
        .alert("清空历史记录？", isPresented: $showsClearConfirmation) {
            Button("清空历史记录", role: .destructive) {
                readingHistory.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本地历史记录，不会影响收藏和平台账号。")
        }
        .alert("清空阅读进度？", isPresented: $showsClearProgressConfirmation) {
            Button("清空阅读进度", role: .destructive) {
                readingHistory.clearReadingProgress()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("历史条目会保留，但会移除章节和页码进度。")
        }
    }
}

private struct ReadingDurationSettingsView: View {
    @EnvironmentObject private var readingDuration: ReadingDurationService
    @AppStorage(ReadingDurationService.Key.isEnabled) private var recordsReadingDuration = true
    @AppStorage(ReadingDurationService.Key.maxRecords) private var maxReadingDurationRecords = 300
    @AppStorage(ReadingDurationService.Key.minimumSessionSeconds) private var minimumReadingDurationSessionSeconds = 1
    @State private var showsClearDurationConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("记录阅读时长", isOn: $recordsReadingDuration)
                IntegerSettingsInputRow(
                    title: "低于不记录",
                    value: $minimumReadingDurationSessionSeconds,
                    unit: "秒",
                    lowerBound: 1,
                    upperBound: 600,
                    detail: "单次进入阅读器后停留时间低于这个值时，不写入阅读时长统计。"
                )
                IntegerSettingsInputRow(title: "最多保存", value: $maxReadingDurationRecords, unit: "部", lowerBound: 20, upperBound: 1000)
            } footer: {
                Text("阅读时长会在阅读器打开期间累计，应用进入后台或离开阅读器时保存。")
            }

            Section {
                Button(role: .destructive) {
                    showsClearDurationConfirmation = true
                } label: {
                    Label("清空阅读时长", systemImage: "timer")
                }
                .disabled(readingDuration.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("阅读时长")
        .picaxHidesTabBar()
        .onChange(of: maxReadingDurationRecords) { _, _ in
            readingDuration.trimToCurrentLimit()
        }
        .alert("清空阅读时长？", isPresented: $showsClearDurationConfirmation) {
            Button("清空阅读时长", role: .destructive) {
                readingDuration.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除阅读时长统计，不会影响历史记录和阅读进度。")
        }
    }
}

private struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var isCheckingUpdate = false
    @State private var updateAlert: AppUpdateAlert?

    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PicaX"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static let buildEnvironment: [String: String] = {
        guard let url = Bundle.main.url(forResource: "PicaXBuildEnvironment", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return [:]
        }

        return plist as? [String: String] ?? [:]
    }()

    private var buildInfoRows: [(title: String, value: String)] {
        let environment = Self.buildEnvironment
        return [
            ("构建时间", buildEnvironmentValue("BuildTime", in: environment)),
            ("主机名", buildEnvironmentValue("BuildHostName", in: environment)),
            ("编译用户", buildEnvironmentValue("BuildUser", in: environment)),
            ("主机系统", buildEnvironmentValue("BuildHostOS", in: environment)),
            ("主机架构", buildEnvironmentValue("BuildHostArchitecture", in: environment)),
            ("Xcode 版本", buildEnvironmentValue("BuildXcode", in: environment))
        ]
    }

    private func buildEnvironmentValue(_ key: String, in environment: [String: String], fallback: String = "未知") -> String {
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    var body: some View {
        List {
            Section("应用") {
                SettingsValueRow(title: "名称", value: displayName)
                SettingsValueRow(title: "版本", value: appVersion)
                SettingsValueRow(title: "构建", value: buildNumber)
            }

            Section("编译信息") {
                ForEach(buildInfoRows, id: \.title) { row in
                    SettingsValueRow(title: row.title, value: row.value)
                }
            }

            Section("更新") {
                Button {
                    Task {
                        await checkForUpdates()
                    }
                } label: {
                    HStack {
                        Label(isCheckingUpdate ? "正在检查更新" : "检查更新", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isCheckingUpdate {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCheckingUpdate)
            }

            Section("开源") {
                Link(destination: AppUpdateService.repositoryURL) {
                    Label("开源地址", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Link(destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!) {
                    Label("MPL-2.0 开源协议", systemImage: "doc.text")
                }
            }

            Section("社区") {
                Link(destination: URL(string: "https://t.me/pica_x")!) {
                    Label("Telegram 群组", systemImage: "paperplane")
                }
            }

            Section("鸣谢") {
                Link(destination: URL(string: "https://github.com/ccbkv/PicaComic")!) {
                    SettingsActionRow(
                        title: "ccbkv/PicaComic",
                        subtitle: "项目功能与交互参考",
                        systemImage: "heart"
                    )
                }

                Link(destination: URL(string: "https://github.com/Pacalini/PicaComic")!) {
                    SettingsActionRow(
                        title: "Pacalini/PicaComic",
                        subtitle: "ccbkv/PicaComic fork 自该项目",
                        systemImage: "arrow.triangle.branch"
                    )
                }
            }

            Section("平台") {
                SettingsValueRow(title: "支持漫画源", value: "\(ComicPlatform.allCases.count)")
                ForEach(ComicPlatform.allCases) { platform in
                    Label(platform.title, systemImage: platform.systemImage)
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("关于")
        .picaxHidesTabBar()
        .alert(item: $updateAlert) { alert in
            if let releaseURL = alert.releaseURL {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("打开发布页")) {
                        openURL(releaseURL)
                    },
                    secondaryButton: .cancel(Text("好"))
                )
            } else {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    @MainActor
    private func checkForUpdates() async {
        guard !isCheckingUpdate else { return }

        isCheckingUpdate = true
        defer {
            isCheckingUpdate = false
        }

        do {
            let result = try await AppUpdateService.checkLatestRelease(currentVersion: appVersion)
            if result.hasUpdate {
                updateAlert = AppUpdateAlert(
                    title: "发现新版本",
                    message: "当前版本 \(result.currentVersion)，最新版本 \(result.latestVersion)。可以前往发布页查看更新内容。",
                    releaseURL: result.releaseURL
                )
            } else {
                updateAlert = AppUpdateAlert(
                    title: "已是最新版本",
                    message: "当前版本 \(result.currentVersion) 已是最新版本。",
                    releaseURL: nil
                )
            }
        } catch {
            updateAlert = AppUpdateAlert(
                title: "检查更新失败",
                message: error.localizedDescription,
                releaseURL: nil
            )
        }
    }

    private struct AppUpdateAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let releaseURL: URL?
    }
}

private struct SettingsNavigationLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder var destination: () -> Destination

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination
    }

    init(
        item: SettingsSearchItem,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = item.title
        self.subtitle = item.subtitle
        self.systemImage = systemImage
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsActionRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
        }
    }
}

private struct IntegerSettingsInputRow: View {
    let title: String
    @Binding var value: Int
    var unit: String?
    var lowerBound: Int?
    var upperBound: Int?
    var detail: String?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("", text: $text)
                        .multilineTextAlignment(.trailing)
                        .picaxKeyboardType(.numberPad)
                        .focused($isFocused)
                        .frame(width: 92)
                        .onChange(of: text) { _, newValue in
                            updateValue(from: newValue)
                        }

                    if let unit {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text(title)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            text = "\(value)"
        }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            text = "\(bounded(newValue))"
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                let nextValue = bounded(value)
                if nextValue != value {
                    value = nextValue
                }
                text = "\(nextValue)"
            }
        }
    }

    private func updateValue(from newValue: String) {
        let filtered = String(newValue.filter(\.isNumber))
        if filtered != newValue {
            text = filtered
            return
        }

        guard let rawValue = Int(filtered) else {
            return
        }
        let nextValue = upperBound.map { min(rawValue, $0) } ?? rawValue
        if nextValue != value {
            value = nextValue
        }
        if nextValue != rawValue {
            text = "\(nextValue)"
        }
    }

    private func bounded(_ rawValue: Int) -> Int {
        var result = rawValue
        if let lowerBound {
            result = max(result, lowerBound)
        }
        if let upperBound {
            result = min(result, upperBound)
        }
        return result
    }
}

private struct PlatformAccountRow: View {
    let platform: ComicPlatform
    let account: PlatformAccount?

    var body: some View {
        Label {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.title)
                        .foregroundStyle(.primary)
                    Text(account.map { "已登录：\($0.displayName)" } ?? platform.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(account == nil ? "登录" : "已登录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(account == nil ? Color.secondary : platform.accentColor)
            }
        } icon: {
            Image(systemName: platform.systemImage)
                .foregroundStyle(platform.accentColor)
        }
    }
}

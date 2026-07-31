import SwiftUI

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
                        SettingsNavigationLink(item: .reader, systemImage: "book") {
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
            "搜索源、标签翻译、历史与键盘行为"
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
            "本地文件与 WebDAV 备份、同步和恢复"
        case .appDisplay:
            "显示模式与页面过渡"
        case .appBehavior:
            "剪贴板检测与启动检查"
        case .watchConnectivity:
            "阅读记录、本地收藏与稍后再读同步"
        case .network:
            "连接与重试"
        case .about:
            "版本、协议与声明"
        }
    }

    var keywords: [String] {
        switch self {
        case .platformAccounts:
            ComicPlatform.allCases.map(\.title) + ["登录", "账号", "cookie"]
        case .reader:
            ["自动翻页", "平滑持续滚动", "点按翻页", "两指缩放", "双击缩放", "长按缩放", "触发时间", "预加载", "章节末尾", "下一章", "浮动按钮", "按钮位置", "边距", "批量阅读", "切换书籍", "状态栏", "页码", "亮度", "深色模式"]
        case .home:
            ["阅读时长", "阅读历史", "稍后再读", "下载", "折叠", "首页卡片"]
        case .storage:
            ["缓存", "图片缓存", "详情缓存", "空间", "清空缓存"]
        case .blockingKeywords:
            ["屏蔽", "黑名单", "关键词", "标签"]
        case .search:
            ["默认搜索源", "搜索历史", "聚合搜索", "搜索补全", "标签建议", "标签数据库", "E-Hentai", "下载更新", "中文", "英文", "翻译", "填入", "直接搜索"]
        case .comicList:
            ["已读隐藏", "稍后再读", "阅读进度", "收藏状态", "标签"]
        case .downloads:
            ["下载评论", "同时下载", "限速", "队列", "ZIP", "导出", "文件名", "章节屏蔽", "章节名"]
        case .appDisplay:
            ["深色", "浅色", "动画", "平滑过渡", "页面过渡", "缩放"]
        case .appBehavior:
            ["剪贴板", "启动", "更新", "敏感", "隐私", "截图", "录屏", "封面"]
        case .watchConnectivity:
            ["Watch", "Apple Watch", "手表", "互联", "同步", "阅读记录", "本地收藏", "稍后再读"]
        case .history:
            ["阅读进度", "清空", "记录"]
        case .readingDuration:
            ["阅读时长", "统计", "趋势", "清空", "记录", "单次", "低于"]
        case .about:
            ["用户协议", "隐私政策", "免责声明", "开源许可", "版本", "声明"]
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
    @AppStorage(AppAppearanceSettingsKey.usesSmoothComicDetailTransitions) private var usesSmoothComicDetailTransitions = true

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

            #if os(iOS)
            Section {
                Toggle("漫画详情平滑过渡", isOn: $usesSmoothComicDetailTransitions)
                    .disabled(!supportsSmoothComicDetailTransitions)
            } header: {
                Text("页面过渡")
            } footer: {
                Text("开启后，打开漫画详情时会从所选内容平滑缩放。此设置仅影响漫画详情，且需要 iOS 18 或更高版本。")
            }
            #endif
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("显示")
        .picaxHidesTabBar()
    }

    #if os(iOS)
    private var supportsSmoothComicDetailTransitions: Bool {
        if #available(iOS 18.0, *) {
            true
        } else {
            false
        }
    }
    #endif
}

private struct AppBehaviorSettingsView: View {
    @AppStorage(AppBehaviorSettingsKey.checksClipboardForComicLinks) private var checksClipboardForComicLinks = false
    @AppStorage(AppBehaviorSettingsKey.checksClipboardOnlyOnLaunch) private var checksClipboardOnlyOnLaunch = false
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true
    @AppStorage(AppBehaviorSettingsKey.marksImageContentAsSensitive) private var marksImageContentAsSensitive = false

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

            Section {
                Toggle("图片页面标记为敏感内容", isOn: $marksImageContentAsSensitive)
            } footer: {
                Text("开启后，包含漫画封面或章节图片的页面会标记为敏感内容，被标记为敏感的内容会在进入后台后自动以占位符的方式和谐；没有这些图片的页面不会标记。")
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
                        do {
                            try platformAccounts.logout(platform: platform)
                            username = ""
                            password = ""
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
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
            try platformAccounts.saveValidatedAccount(account)
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
        .onChange(of: sectionOrderRaw) { newValue in
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
    @AppStorage(DownloadSettingsKey.concurrentImageDownloadCount) private var concurrentImageDownloadCount = 3
    @AppStorage(DownloadSettingsKey.chapterTitleBlockingKeywords) private var chapterTitleBlockingKeywords = ""
    @AppStorage(DownloadSettingsKey.speedLimitEnabled) private var speedLimitEnabled = false
    @AppStorage(DownloadSettingsKey.speedLimitKBPerSecond) private var speedLimitKBPerSecond = 1024
    @AppStorage(DownloadSettingsKey.readsImagesFromCache) private var readsImagesFromCache = true
    @AppStorage(DownloadSettingsKey.recordsDownloadedReadingHistory) private var recordsDownloadedReadingHistory = true
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false
    @AppStorage(DownloadSettingsKey.archiveFileNameTemplate) private var archiveFileNameTemplate = DownloadSettingsKey.defaultArchiveFileNameTemplate
    @AppStorage(DownloadSettingsKey.showsProgressNotifications) private var showsProgressNotifications = true
    @AppStorage(DownloadSettingsKey.showsProgressLiveActivity) private var showsProgressLiveActivity = true
    @AppStorage(DownloadSettingsKey.progressNotificationUpdateIntervalSeconds) private var progressNotificationUpdateIntervalSeconds = DownloadSettingsKey.defaultProgressNotificationUpdateIntervalSeconds

    var body: some View {
        List {
            Section {
                Toggle("默认保存评论区", isOn: $downloadsCommentsByDefault)
                Toggle("已下载阅读计入历史", isOn: $recordsDownloadedReadingHistory)
            } header: {
                Text("下载内容")
            } footer: {
                Text("评论开关会让支持评论区的漫画在打开下载面板时默认一并保存评论；历史开关会让本地已下载漫画的阅读进度写入阅读历史。")
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

                if #available(iOS 16.1, *) {
                    Toggle("灵动岛下载进度", isOn: $showsProgressLiveActivity)
                } else {
                    LabeledContent("灵动岛下载进度", value: "需要 iOS 16.1")
                }
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
                IntegerSettingsInputRow(title: "同时任务数", value: $concurrentDownloadCount, lowerBound: 1, upperBound: 20)
                IntegerSettingsInputRow(title: "图片线程数", value: $concurrentImageDownloadCount, lowerBound: 1, upperBound: 20)
                IntegerSettingsInputRow(title: "图片重试", value: $imageRetryCount, unit: "次", lowerBound: 0, upperBound: 8)
            } header: {
                Text("任务")
            } footer: {
                Text("同时任务数控制队列里可并行下载的漫画数量；图片线程数控制单个章节内可同时下载的图片数量。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("章节名屏蔽词")
                        .font(.subheadline)

                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("每行一个关键词", text: $chapterTitleBlockingKeywords, axis: .vertical)
                            .lineLimit(3...8)
                            .picaxDisablesTextAutocapitalization()
                            .autocorrectionDisabled()
                    } else {
                        TextEditor(text: $chapterTitleBlockingKeywords)
                            .frame(minHeight: 72, maxHeight: 180)
                            .picaxDisablesTextAutocapitalization()
                            .autocorrectionDisabled()
                    }
                }

                if !chapterTitleBlockingKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        chapterTitleBlockingKeywords = ""
                    } label: {
                        Label("清空章节名屏蔽词", systemImage: "trash")
                    }
                }
            } header: {
                Text("章节过滤")
            } footer: {
                Text("批量下载或选章下载时，章节名包含任一关键词的章节不会加入下载。")
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
        .onChange(of: showsProgressNotifications) { _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: showsProgressLiveActivity) { _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: progressNotificationUpdateIntervalSeconds) { _ in
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
    @State private var historyBytes = 0
    @State private var durationBytes = 0

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
            let imageTrimTask = ImageCacheService.configure()
            let detailTrimTask = ComicDetailCacheService.configure()
            Task {
                await imageTrimTask.value
                await detailTrimTask.value
                await refreshStorageUsage()
            }
        }
        .onChange(of: maxDiskSizeMB) { _ in
            let trimTask = ImageCacheService.configure()
            Task {
                await trimTask.value
                await refreshStorageUsage()
            }
        }
        .onChange(of: detailCacheEnabled) { _ in
            Task {
                await refreshStorageUsage()
            }
        }
        .onChange(of: maxDetailCacheDiskSizeMB) { _ in
            let trimTask = ComicDetailCacheService.configure()
            Task {
                await trimTask.value
                await refreshStorageUsage()
            }
        }
        .alert("清空图片缓存？", isPresented: $showsClearCacheConfirmation) {
            Button("清空缓存", role: .destructive) {
                Task {
                    await ImageCacheService.clear()
                    await refreshStorageUsage()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地缓存的封面、分类图和阅读图片，不会影响下载、收藏或历史记录。")
        }
        .alert("清空详情缓存？", isPresented: $showsClearDetailCacheConfirmation) {
            Button("清空缓存", role: .destructive) {
                Task {
                    await ComicDetailCacheService.clear()
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

    private var localDataBytes: Int64 {
        Int64(historyBytes + durationBytes + downloadUsage.metadataBytes)
    }

    private var totalDiskUsage: Int64 {
        Int64(usage.diskBytes + detailCacheUsage.diskBytes) + downloadUsage.filesBytes + localDataBytes
    }

    @MainActor
    private func refreshStorageUsage() async {
        async let nextUsage = ImageCacheService.usage()
        async let nextDetailCacheUsage = ComicDetailCacheService.usage()
        async let nextDownloadUsage = downloadService.storageUsage()
        async let nextLocalDatabaseBytes = Self.localDatabaseBytes()

        let values = await (nextUsage, nextDetailCacheUsage, nextDownloadUsage, nextLocalDatabaseBytes)
        usage = values.0
        detailCacheUsage = values.1
        downloadUsage = values.2
        historyBytes = values.3.history
        durationBytes = values.3.duration
    }

    private nonisolated static func localDatabaseBytes() async -> (history: Int, duration: Int) {
        await Task.detached(priority: .utility) {
            (
                history: PicaXSQLiteStore.bytes(for: .readingHistory),
                duration: PicaXSQLiteStore.bytes(for: .readingDuration)
            )
        }.value
    }
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
                    .onChange(of: rememberSelectedPlatform) { newValue in
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
    @StateObject private var ehTagTranslationUpdates = EhTagTranslationUpdateService()
    @AppStorage(SearchSettingsKey.focusesSearchFieldOnOpen) private var focusesSearchFieldOnOpen = false
    @AppStorage(SearchSettingsKey.enablesSearchSuggestions) private var enablesSearchSuggestions = true
    @AppStorage(SearchSettingsKey.translatesChineseSearchTerms) private var translatesChineseSearchTerms = true
    @AppStorage(SearchSettingsKey.suggestionSelectionBehavior) private var suggestionSelectionBehavior = SearchSuggestionSelectionBehavior.fill.rawValue
    @AppStorage(SearchSettingsKey.defaultTargetMode) private var defaultTargetMode = SearchDefaultTargetMode.platform.rawValue
    @AppStorage(SearchSettingsKey.defaultPlatform) private var defaultSearchPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage(SearchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = ComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(SearchHistorySettingsKey.isEnabled) private var savesSearchHistory = true
    @AppStorage(SearchHistorySettingsKey.maxRecords) private var maxSearchHistoryRecords = 50
    @State private var showsClearSearchHistoryConfirmation = false
    @State private var showsRestoreEhTagsConfirmation = false

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
                Toggle("中文标签词自动转英文", isOn: $translatesChineseSearchTerms)
            } footer: {
                Text("开启后，搜索时会为 E-Hentai 和 NHentai 把能匹配本地标签字段的中文词转为英文词；搜索框和搜索历史仍保留原文，聚合搜索里的其他平台不受影响。")
            }

            Section {
                LabeledContent("当前数据", value: ehTagTranslationUpdates.info.usesDownloadedDatabase ? "已下载" : "内置")
                LabeledContent("数据库版本", value: ehTagTranslationUpdates.info.version ?? "内置版本")

                if let updatedAt = ehTagTranslationUpdates.info.updatedAt {
                    LabeledContent("更新时间", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Button {
                    Task { await ehTagTranslationUpdates.update() }
                } label: {
                    if ehTagTranslationUpdates.isUpdating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在下载标签翻译库")
                        }
                    } else {
                        Label("下载更新", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(ehTagTranslationUpdates.isUpdating)

                if ehTagTranslationUpdates.info.usesDownloadedDatabase {
                    Button(role: .destructive) {
                        showsRestoreEhTagsConfirmation = true
                    } label: {
                        Label("恢复内置版本", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(ehTagTranslationUpdates.isUpdating)
                }

                if let statusMessage = ehTagTranslationUpdates.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("E-Hentai 标签翻译库")
            } footer: {
                Text("从 EhTagTranslation/Database 下载公开标签对应并保存在本机；下载或校验失败时继续使用当前数据，内置版本始终可恢复。")
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
        .onChange(of: maxSearchHistoryRecords) { _ in
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
        .confirmationDialog("恢复内置标签翻译库？", isPresented: $showsRestoreEhTagsConfirmation) {
            Button("恢复内置版本", role: .destructive) {
                ehTagTranslationUpdates.restoreBundled()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已下载的标签对应会从本机删除，之后仍可重新下载。")
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
    @AppStorage(ComicListSettingsKey.layoutMode) private var layoutMode = ComicListLayoutMode.list.rawValue
    @AppStorage(ComicListSettingsKey.showsReadingProgress) private var showsReadingProgress = true
    @AppStorage(ComicListSettingsKey.showsFavoriteState) private var showsFavoriteState = true
    @AppStorage(ComicListSettingsKey.showsTags) private var showsTags = true
    @AppStorage(ComicListSettingsKey.maxVisibleTags) private var maxVisibleTags = 5
    @AppStorage(ComicListSettingsKey.showsPopularity) private var showsPopularity = true
    @AppStorage(ReadFilterSettingsKey.hidesReadComicsInLists) private var hidesReadComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hidesReadLaterComicsInLists) private var hidesReadLaterComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hiddenProgressThreshold) private var hiddenProgressThreshold = 100

    var body: some View {
        List {
            Section {
                Picker("布局", selection: $layoutMode) {
                    ForEach(ComicListLayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("布局")
            } footer: {
                Text("瀑布流会根据可用宽度自动调整每行漫画数量；辅助功能大字号下会使用更宽的卡片。")
            }

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
                            Text("已读隐藏阈值")
                            Spacer()
                            Text("\(hiddenProgressThreshold)%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: hiddenProgressThresholdBinding, in: 0...100, step: 5)
                    }
                }

                Toggle("隐藏稍后再读内容", isOn: $hidesReadLaterComicsInLists)
            } header: {
                Text("列表隐藏")
            } footer: {
                Text("已读隐藏阈值只对“隐藏已读内容”生效。开启后，普通漫画列表会隐藏符合条件的漫画；收藏夹、历史记录、已下载页面和稍后再读不受影响。")
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
        .onChange(of: contentOrderRaw) { newValue in
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
        PicaxNavigationContainer {
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
                        .onChange(of: proxyPortText) { newValue in
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
        .onChange(of: useProxy) { newValue in
            if newValue, proxyPortText.isEmpty {
                proxyPortText = "\(proxyPort)"
            }
        }
        .onChange(of: proxyPort) { newValue in
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
        .onChange(of: maxRecords) { _ in
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
        .onChange(of: maxReadingDurationRecords) { _ in
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
            ("编译 Commit", buildEnvironmentValue("BuildCommit", in: environment)),
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

            Section("协议与声明") {
                ForEach(LegalDocument.all) { document in
                    NavigationLink {
                        LegalDocumentView(document: document)
                    } label: {
                        SettingsActionRow(
                            title: document.title,
                            subtitle: document.summary,
                            systemImage: document.systemImage
                        )
                    }
                }

                Link(destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!) {
                    SettingsActionRow(
                        title: "MPL-2.0 开源许可",
                        subtitle: "查看 PicaX 使用的开源许可证",
                        systemImage: "doc.text"
                    )
                }
            }

            Section("开源") {
                Link(destination: AppUpdateService.repositoryURL) {
                    Label("开源地址", systemImage: "chevron.left.forwardslash.chevron.right")
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

struct SettingsActionRow: View {
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

struct IntegerSettingsInputRow: View {
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
                        .onChange(of: text) { newValue in
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
        .onChange(of: value) { newValue in
            guard !isFocused else { return }
            text = "\(bounded(newValue))"
        }
        .onChange(of: isFocused) { focused in
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

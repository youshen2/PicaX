import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HomePage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var readingDuration: ReadingDurationService
    @EnvironmentObject private var downloadService: DownloadService
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReadingHistoryService.Key.homeLimit) private var historyHomeLimit = 10
    @AppStorage(ReadingDurationService.Key.homeLimit) private var readingDurationHomeLimit = 6
    @AppStorage(DownloadSettingsKey.homeLimit) private var downloadHomeLimit = 8
    @AppStorage(HomeSettingsKey.showsHistorySection) private var showsHistorySection = true
    @AppStorage(HomeSettingsKey.showsReadingDurationSection) private var showsReadingDurationSection = true
    @AppStorage(HomeSettingsKey.showsDownloadSection) private var showsDownloadSection = true
    @AppStorage(HomeSettingsKey.showsAccountManagementEntry) private var showsAccountManagementEntry = true
    @AppStorage(HomeSettingsKey.sectionOrder) private var homeSectionOrderRaw = HomeSectionKind.defaultRawValue
    @AppStorage(AppBehaviorSettingsKey.checksClipboardForComicLinks) private var checksClipboardForComicLinks = true
    @AppStorage(AppBehaviorSettingsKey.checksClipboardOnlyOnLaunch) private var checksClipboardOnlyOnLaunch = false

    private let contentService = ComicContentService()
    @State private var downloadedReaderRequest: DownloadedComicReaderRequest?
    @State private var downloadedSearchRequest: DownloadedComicSearchRequest?
    @State private var toolDetailRequest: HomeToolDetailRequest?
    @State private var toolInputTarget: HomeToolInputTarget?
    @State private var toolInputText = ""
    @State private var toolErrorMessage: String?
    @State private var clipboardCandidate: HomeClipboardCandidate?
    @State private var hasCheckedClipboardOnLaunch = false
    @State private var lastCheckedClipboardValue = ""

    var body: some View {
        Group {
            homeList
        }
        .navigationDestination(item: $downloadedReaderRequest) { request in
            ComicReaderPage(
                detail: request.detail,
                initialChapterIndex: request.initialChapterIndex,
                initialPageIndex: request.initialPageIndex,
                ignoresHistoryProgress: request.ignoresHistoryProgress,
                service: contentService,
                localChapterImageProvider: { _, chapterIndex in
                    await downloadService.localChapterImages(for: request.record, chapterIndex: chapterIndex)
                },
                localChapterCommentsProvider: { _, chapterIndex in
                    await downloadService.localChapterComments(for: request.record, chapterIndex: chapterIndex)
                }
            )
        }
        .navigationDestination(item: $downloadedSearchRequest) { request in
            ComicSearchPage(initialQuery: request.tag.query, platform: request.tag.platform, service: contentService)
        }
        .navigationDestination(item: $toolDetailRequest) { request in
            ComicDetailPage(item: request.item, service: contentService)
                .picaxHidesTabBar()
        }
        .alert(toolInputTarget?.title ?? "", isPresented: toolInputDialogBinding) {
            if let target = toolInputTarget {
                TextField(target.placeholder, text: $toolInputText)
                    .picaxKeyboardType(target.keyboard)
                    .picaxDisablesTextAutocapitalization()
                    .autocorrectionDisabled()

                Button("打开") {
                    submitToolInput(target: target)
                }
                .disabled(toolInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("取消", role: .cancel) {
                    resetToolInput()
                }
            }
        } message: {
            if let target = toolInputTarget {
                Text(target.prompt)
            }
        }
        .alert("打开失败", isPresented: toolErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(toolErrorMessage ?? "")
        }
        .confirmationDialog("检测到剪贴板内容", isPresented: clipboardCandidateBinding, titleVisibility: .visible) {
            if let candidate = clipboardCandidate {
                Button("打开 \(candidate.item.platformTitle)") {
                    toolDetailRequest = HomeToolDetailRequest(item: candidate.item)
                    clipboardCandidate = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let candidate = clipboardCandidate {
                Text(candidate.displayText)
            }
        }
        .onAppear {
            checkClipboardOnAppearIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active, !checksClipboardOnlyOnLaunch {
                checkClipboardIfNeeded()
            }
        }
    }

    private var homeList: some View {
        List {
            ForEach(homeSections) { section in
                homeSection(section)
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
    }

    private var homeSections: [HomeSectionKind] {
        HomeSectionKind.normalizedOrder(from: homeSectionOrderRaw)
    }

    @ViewBuilder
    private func homeSection(_ section: HomeSectionKind) -> some View {
        switch section {
        case .history:
            if showsHistorySection {
                Section {
                    HomeHistoryCard(
                        records: readingHistory.latest(limit: historyHomeLimit),
                        service: contentService
                    )
                } header: {
                    HomeHistoryHeader(service: contentService)
                }
            } else {
                Section("历史记录") {
                    HomeHistoryEntryLink(service: contentService)
                }
            }

        case .readingDuration:
            if showsReadingDurationSection {
                Section {
                    HomeReadingDurationCard(
                        records: readingDuration.latest(limit: readingDurationHomeLimit),
                        todayKey: readingDuration.todayKey,
                        todayDurationText: readingDuration.todayDurationText,
                        totalDurationText: readingDuration.totalDurationText,
                        service: contentService
                    )
                } header: {
                    HomeReadingDurationHeader(service: contentService)
                }
            } else {
                Section("阅读时长") {
                    HomeReadingDurationEntryLink(
                        todayDurationText: readingDuration.todayDurationText,
                        totalDurationText: readingDuration.totalDurationText,
                        service: contentService
                    )
                }
            }

        case .downloads:
            if showsDownloadSection {
                Section {
                    HomeDownloadsCard(
                        records: downloadService.latest(limit: downloadHomeLimit),
                        service: contentService,
                        openReader: { downloadedReaderRequest = $0 },
                        openSearch: { downloadedSearchRequest = $0 }
                    )
                } header: {
                    HomeDownloadsHeader(service: contentService)
                }
            } else {
                Section("下载") {
                    HomeDownloadsEntryLink(service: contentService)
                }
            }

        case .comicSources:
            if showsAccountManagementEntry || !platformAccounts.loggedInAccounts.isEmpty {
                Section("漫画源") {
                    if showsAccountManagementEntry {
                        NavigationLink {
                            PlatformAccountsSettingsView()
                                .picaxHidesTabBar()
                        } label: {
                            ToolRow(
                                title: "管理平台账号",
                                subtitle: "登录、更新或退出平台账号",
                                systemImage: "person.2"
                            )
                        }
                    }

                    ForEach(platformAccounts.loggedInAccounts) { account in
                        NavigationLink {
                            HomeComicSourceFeaturePage(platform: account.platform, service: contentService)
                                .picaxHidesTabBar()
                        } label: {
                            HomeComicSourceRow(
                                platform: account.platform,
                                account: account
                            )
                        }
                    }
                }
            }

        case .tools:
            HomeToolsSection(
                service: contentService,
                requestInput: presentToolInputDialog,
                showError: { toolErrorMessage = $0 }
            )
        }
    }

    private var toolErrorBinding: Binding<Bool> {
        Binding {
            toolErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                toolErrorMessage = nil
            }
        }
    }

    private var toolInputDialogBinding: Binding<Bool> {
        Binding {
            toolInputTarget != nil
        } set: { isPresented in
            if !isPresented {
                resetToolInput()
            }
        }
    }

    private var clipboardCandidateBinding: Binding<Bool> {
        Binding {
            clipboardCandidate != nil
        } set: { isPresented in
            if !isPresented {
                clipboardCandidate = nil
            }
        }
    }

    private func presentToolInputDialog(_ target: HomeToolInputTarget) {
        toolInputText = ""
        toolInputTarget = target
    }

    private func submitToolInput(target: HomeToolInputTarget) {
        let value = toolInputText
        resetToolInput()
        if let message = handleToolInput(value, target: target) {
            toolErrorMessage = message
        }
    }

    private func resetToolInput() {
        toolInputTarget = nil
        toolInputText = ""
    }

    private func handleToolInput(_ value: String, target: HomeToolInputTarget) -> String? {
        switch target {
        case .openLink:
            switch HomeToolLinkParser.item(from: value) {
            case .success(let item):
                toolDetailRequest = HomeToolDetailRequest(item: item)
                return nil
            case .failure(let error):
                return error.message
            }
        case .jmComicID:
            guard let id = HomeToolLinkParser.jmComicID(from: value) else {
                return "请输入 jm123 或纯数字车牌号"
            }
            toolDetailRequest = HomeToolDetailRequest(item: HomeToolLinkParser.jmComicItem(id: id))
            return nil
        }
    }

    private func checkClipboardOnAppearIfNeeded() {
        if checksClipboardOnlyOnLaunch {
            guard !hasCheckedClipboardOnLaunch else { return }
            hasCheckedClipboardOnLaunch = true
        }
        checkClipboardIfNeeded()
    }

    private func checkClipboardIfNeeded() {
        guard checksClipboardForComicLinks,
              let value = PlatformPasteboardReader.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != lastCheckedClipboardValue else {
            return
        }
        lastCheckedClipboardValue = value

        guard case .success(let item) = HomeToolLinkParser.item(from: value) else {
            return
        }
        clipboardCandidate = HomeClipboardCandidate(rawValue: value, item: item)
    }
}

private struct HomeClipboardCandidate: Identifiable {
    let rawValue: String
    let item: ComicListItem

    var id: String {
        "\(item.platform.id)-\(item.id)-\(rawValue)"
    }

    var displayText: String {
        rawValue
    }
}

private enum PlatformPasteboardReader {
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #elseif os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        nil
        #endif
    }
}

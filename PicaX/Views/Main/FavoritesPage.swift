import SwiftUI

struct FavoritesPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    private let service = ComicContentService()

    var body: some View {
        List {
            Section("本地收藏夹") {
                ForEach(service.localFolders) { folder in
                    NavigationLink {
                        FavoritesCollectionPage(source: .local(folder), service: service)
                    } label: {
                        FavoriteSourceRow(
                            title: folder.title,
                            subtitle: folder.subtitle,
                            systemImage: "folder",
                            accentColor: .orange
                        )
                    }
                }
            }

            Section("平台收藏") {
                if platformAccounts.loggedInAccounts.isEmpty {
                    ContentUnavailableView("暂无已登录平台", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("登录平台账号后会在这里显示对应收藏"))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(platformAccounts.loggedInAccounts.filter { service.supportsPlatformFavorite(platform: $0.platform) }) { account in
                        NavigationLink {
                            if service.supportsPlatformFavoriteFolders(platform: account.platform) {
                                FavoritePlatformFoldersPage(account: account, service: service)
                            } else {
                                FavoritesCollectionPage(source: .platform(account), service: service)
                            }
                        } label: {
                            FavoriteSourceRow(
                                title: account.platform.title,
                                subtitle: account.displayName,
                                systemImage: account.platform.systemImage,
                                accentColor: account.platform.accentColor
                            )
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
    }
}

private struct FavoriteSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 5)
    }
}

private struct FavoritePlatformFoldersPage: View {
    let account: PlatformAccount
    let service: ComicContentService
    @State private var folders: [PlatformFavoriteFolder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingFavoriteListView(accentColor: account.platform.accentColor)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task {
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if folders.isEmpty {
                ContentUnavailableView("暂无收藏夹", systemImage: "folder", description: Text("这个平台当前没有返回收藏夹"))
            } else {
                List {
                    Section("平台收藏夹") {
                        ForEach(folders) { folder in
                            NavigationLink {
                                FavoritesCollectionPage(source: .platformFolder(account, folder), service: service)
                            } label: {
                                FavoriteSourceRow(
                                    title: folder.title,
                                    subtitle: folder.subtitle,
                                    systemImage: account.platform.systemImage,
                                    accentColor: account.platform.accentColor
                                )
                            }
                        }
                    }
                }
                .picaxInsetGroupedListStyle()
                .background(AppColor.groupedBackground)
                .refreshable {
                    await load(force: true)
                }
            }
        }
        .navigationTitle(account.platform.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .picaxTopBarTrailing) {
                Button {
                    Task {
                        await load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load(force: Bool = false) async {
        if !force, !folders.isEmpty {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            folders = try await service.loadPlatformFavoriteFolders(platform: account.platform, account: account)
        } catch {
            errorMessage = error.localizedDescription
            folders = []
        }
        isLoading = false
    }
}

private struct FavoritesCollectionPage: View {
    let source: FavoriteCollectionSource
    let service: ComicContentService
    @State private var comics: [ComicListItem] = []
    @State private var filteredComics: [ComicListItem] = []
    @State private var visibleLocalComicCount = Self.localFavoriteInitialCount
    @State private var isLoading = true
    @State private var isLoadingMoreFavorites = false
    @State private var isPreparingReadAll = false
    @State private var errorMessage: String?
    @State private var downloadSheetContext: FavoriteDownloadSheetContext?
    @State private var searchText = ""
    @State private var nextFavoritePage = 2
    @State private var hasMoreRemoteFavorites = false
    @State private var loadedComicIDs = Set<String>()
    @State private var readingListRequest: ReadingListRequest?
    @State private var filterTask: Task<Void, Never>?

    private static let localFavoriteInitialCount = 48
    private static let localFavoriteBatchSize = 48

    var body: some View {
        Group {
            if isLoading {
                LoadingFavoriteListView(accentColor: source.accentColor)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task {
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if comics.isEmpty {
                ContentUnavailableView("暂无收藏", systemImage: source.systemImage, description: Text("这个收藏源当前没有返回漫画"))
            } else if filteredComics.isEmpty {
                ContentUnavailableView("没有匹配收藏", systemImage: "magnifyingglass", description: Text("换个关键词再试"))
            } else {
                ComicListSection(
                    comics: visibleComics,
                    service: service,
                    isLoadingMore: isLoadingMoreFavorites,
                    hasMore: canLoadMoreFavorites,
                    appliesBlocking: false,
                    appliesReadProgressFilter: false,
                    appliesReadLaterFilter: false,
                    showsReadAll: true,
                    readAllTitle: source.title,
                    readAllComics: filteredComics,
                    isPreparingReadAll: isPreparingReadAll,
                    readAllAction: {
                        Task {
                            await prepareReadAll()
                        }
                    },
                    loadMore: favoriteLoadMoreAction
                )
                .refreshable {
                    await load(force: true)
                }
            }
        }
        .navigationTitle(source.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .searchable(text: $searchText, placement: .picaxNavigationSearch, prompt: "搜索当前收藏夹")
        .onChange(of: searchText) { _, _ in
            queueFilteredComicsRefresh(resetVisibleCount: true)
            if !normalizedSearchText.isEmpty {
                downloadSheetContext = nil
            }
        }
        .navigationDestination(item: $readingListRequest) { request in
            ReadingListReaderPage(request: request, service: service)
        }
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                if showsDownloadAllButton {
                    Button {
                        downloadSheetContext = FavoriteDownloadSheetContext(
                            title: source.title,
                            systemImage: source.systemImage,
                            accentColor: source.accentColor,
                            loadedCount: comics.count,
                            mayLoadMoreFavorites: hasMoreRemoteFavorites
                        )
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .disabled(!canOpenDownloadSheet)
                    .accessibilityLabel("一键下载收藏夹")
                }

                Button {
                    Task {
                        await load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .sheet(item: $downloadSheetContext) { context in
            FavoriteDownloadAllSheet(
                context: context,
                loadTargets: loadCompleteFavoritesForDownload
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await load()
        }
        .onDisappear {
            filterTask?.cancel()
            filterTask = nil
        }
    }

    private var visibleComics: [ComicListItem] {
        guard source.usesLocalBatching else {
            return filteredComics
        }
        return Array(filteredComics.prefix(visibleLocalComicCount))
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLoadMoreLocalComics: Bool {
        source.usesLocalBatching && visibleLocalComicCount < filteredComics.count
    }

    private var canLoadMoreFavorites: Bool {
        if source.usesLocalBatching {
            return canLoadMoreLocalComics
        }
        return hasMoreRemoteFavorites
    }

    private var favoriteLoadMoreAction: (() -> Void)? {
        if source.usesLocalBatching {
            guard canLoadMoreLocalComics else { return nil }
            return {
                loadMoreLocalComics()
            }
        }
        guard hasMoreRemoteFavorites else { return nil }
        return {
            Task {
                await loadMoreRemoteFavorites()
            }
        }
    }

    private var canOpenDownloadSheet: Bool {
        normalizedSearchText.isEmpty && !isLoading && !isPreparingReadAll && !filteredComics.isEmpty
    }

    private var showsDownloadAllButton: Bool {
        normalizedSearchText.isEmpty
    }

    private func loadMoreLocalComics() {
        guard source.usesLocalBatching, visibleLocalComicCount < filteredComics.count else { return }
        visibleLocalComicCount = min(filteredComics.count, visibleLocalComicCount + Self.localFavoriteBatchSize)
    }

    private func queueFilteredComicsRefresh(resetVisibleCount: Bool) {
        filterTask?.cancel()
        filterTask = Task {
            await refreshFilteredComics(resetVisibleCount: resetVisibleCount)
        }
    }

    @MainActor
    private func refreshFilteredComics(resetVisibleCount: Bool) async {
        let sourceComics = comics
        let keyword = normalizedSearchText
        do {
            let filtered = try await ComicListBackgroundProcessing.filteredFavorites(from: sourceComics, keyword: keyword)
            guard !Task.isCancelled else { return }
            filteredComics = filtered
            if resetVisibleCount {
                visibleLocalComicCount = Self.localFavoriteInitialCount
            }
        } catch is CancellationError {
            return
        } catch {
            filteredComics = sourceComics
        }
    }

    @MainActor
    private func load(force: Bool = false) async {
        if !force, !comics.isEmpty {
            isLoading = false
            filterTask?.cancel()
            await refreshFilteredComics(resetVisibleCount: false)
            return
        }

        isLoading = true
        isLoadingMoreFavorites = false
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch source {
            case .local(let folder):
                comics = try await ComicListBackgroundProcessing.localFavorites(folderID: folder.id)
                hasMoreRemoteFavorites = false
                nextFavoritePage = 2
            case .platform(let account):
                let page = try await service.loadFavoritePage(account: account)
                comics = page.items
                hasMoreRemoteFavorites = page.hasMore
                nextFavoritePage = page.page + 1
            case .platformFolder(let account, let folder):
                let page = try await service.loadFavoritePage(account: account, folder: folder)
                comics = page.items
                hasMoreRemoteFavorites = page.hasMore
                nextFavoritePage = page.page + 1
            }
            loadedComicIDs = try await ComicListBackgroundProcessing.loadedIDs(from: comics, identity: .readingHistoryID)
            filterTask?.cancel()
            await refreshFilteredComics(resetVisibleCount: true)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            comics = []
            filteredComics = []
            hasMoreRemoteFavorites = false
            loadedComicIDs = []
        }
    }

    @MainActor
    private func loadMoreRemoteFavorites() async {
        guard hasMoreRemoteFavorites, !isLoadingMoreFavorites else { return }
        isLoadingMoreFavorites = true
        defer { isLoadingMoreFavorites = false }
        do {
            try await loadNextRemoteFavoritesPage()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            hasMoreRemoteFavorites = false
        }
    }

    @MainActor
    private func loadNextRemoteFavoritesPage(refreshFiltered: Bool = true) async throws {
        let page: ComicFavoritePage
        switch source {
        case .local:
            return
        case .platform(let account):
            page = try await service.loadFavoritePage(account: account, page: nextFavoritePage)
        case .platformFolder(let account, let folder):
            page = try await service.loadFavoritePage(account: account, folder: folder, page: nextFavoritePage)
        }

        let uniqueResult = try await ComicListBackgroundProcessing.uniqueItems(
            from: page.items,
            loadedIDs: loadedComicIDs,
            identity: .readingHistoryID
        )
        loadedComicIDs = uniqueResult.loadedIDs
        nextFavoritePage = page.page + 1
        hasMoreRemoteFavorites = page.hasMore && !uniqueResult.items.isEmpty
        guard !uniqueResult.items.isEmpty else { return }
        comics += uniqueResult.items
        if refreshFiltered {
            filterTask?.cancel()
            await refreshFilteredComics(resetVisibleCount: false)
        }
    }

    @MainActor
    private func prepareReadAll() async {
        guard !isPreparingReadAll else { return }
        isPreparingReadAll = true
        defer { isPreparingReadAll = false }
        do {
            try await loadCompleteFavorites()
            filterTask?.cancel()
            await refreshFilteredComics(resetVisibleCount: false)
            readingListRequest = ReadingListRequest(
                title: source.title,
                entries: filteredComics.map(ReadingListEntry.online)
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadCompleteFavorites() async throws {
        guard !source.usesLocalBatching else { return }
        while hasMoreRemoteFavorites, nextFavoritePage <= 200 {
            try await loadNextRemoteFavoritesPage(refreshFiltered: false)
        }
    }

    @MainActor
    private func loadCompleteFavoritesForDownload() async throws -> [ComicListItem] {
        guard normalizedSearchText.isEmpty else {
            throw FavoriteDownloadAllError.searchActive
        }

        try await loadCompleteFavorites()

        guard normalizedSearchText.isEmpty else {
            throw FavoriteDownloadAllError.searchActive
        }

        filterTask?.cancel()
        await refreshFilteredComics(resetVisibleCount: false)
        return comics
    }
}

private struct FavoriteDownloadSheetContext: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let accentColor: Color
    let loadedCount: Int
    let mayLoadMoreFavorites: Bool
}

private struct FavoriteDownloadAllSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false

    let context: FavoriteDownloadSheetContext
    let loadTargets: @MainActor () async throws -> [ComicListItem]
    @State private var downloadsComments = false
    @State private var didApplyDefaultOptions = false
    @State private var loadState: FavoriteDownloadAllLoadState = .idle
    @State private var feedback: FavoriteDownloadAllFeedback?

    var body: some View {
        NavigationStack {
            List {
                contentSections

                if let feedback {
                    Section(feedback.title) {
                        Text(feedback.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .picaxInsetGroupedListStyle()
            .background(AppColor.groupedBackground)
            .navigationTitle("下载收藏")
            .picaxNavigationBarTitleDisplayModeInline()
            .picaxSensitiveImageContent(containsCoverContent)
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .safeAreaInset(edge: .bottom) {
                FavoriteDownloadAllFooter(
                    message: footerMessage,
                    buttonTitle: footerButtonTitle,
                    isEnabled: footerIsEnabled,
                    action: footerAction
                )
            }
            .onAppear {
                if !didApplyDefaultOptions {
                    downloadsComments = downloadsCommentsByDefault
                    didApplyDefaultOptions = true
                }
            }
            .task {
                await loadFavoritesIfNeeded()
            }
        }
    }

    private var containsCoverContent: Bool {
        if case .loaded(let items) = loadState {
            return !items.isEmpty
        }
        return false
    }

    @ViewBuilder
    private var contentSections: some View {
        switch loadState {
        case .idle, .loading:
            Section {
                FavoriteDownloadScopeRow(
                    context: context,
                    loadedCount: context.loadedCount,
                    isLoading: true
                )

                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载完整收藏夹")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } footer: {
                Text(context.mayLoadMoreFavorites ? "会继续加载剩余收藏页面。" : "正在准备收藏列表。")
            }
        case .failed(let message):
            Section {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
                    .listRowBackground(Color.clear)
            }
        case .loaded(let items):
            Section {
                Toggle("一并下载评论区", isOn: $downloadsComments)
            } footer: {
                Text("支持评论区下载的漫画会在任务执行时同时保存详情评论和章节评论。")
            }

            Section {
                FavoriteDownloadScopeRow(
                    context: context,
                    loadedCount: items.count,
                    isLoading: false
                )
            } header: {
                Text("下载内容")
            } footer: {
                Text("每本漫画会作为独立下载任务加入队列，章节会在任务开始时解析。")
            }

            Section("收藏漫画") {
                if items.isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: context.systemImage)
                        .listRowBackground(Color.clear)
                } else {
                    LazyLocalForEach(items: items, initialCount: 32, pageSize: 32) { item in
                        FavoriteDownloadComicRow(
                            item: item,
                            statusText: statusText(for: item)
                        )
                    }
                }
            }
        }
    }

    private var footerMessage: String? {
        if let feedback {
            return feedback.title
        }
        switch loadState {
        case .failed(let message):
            return message
        case .loaded(let items):
            guard !items.isEmpty else { return "当前收藏夹没有漫画。" }
            return "\(items.count) 本漫画会分别加入下载队列。"
        case .idle, .loading:
            return nil
        }
    }

    private var footerButtonTitle: String {
        if feedback != nil {
            return "完成"
        }
        switch loadState {
        case .failed:
            return "重试"
        case .loaded:
            return "加入下载队列"
        case .idle, .loading:
            return "正在加载收藏"
        }
    }

    private var footerIsEnabled: Bool {
        if feedback != nil {
            return true
        }
        switch loadState {
        case .failed:
            return true
        case .loaded(let items):
            return !items.isEmpty
        case .idle, .loading:
            return false
        }
    }

    private func footerAction() {
        if feedback != nil {
            dismiss()
            return
        }

        switch loadState {
        case .failed:
            Task {
                await loadFavoritesIfNeeded(force: true)
            }
        case .loaded(let items):
            enqueue(items)
        case .idle, .loading:
            break
        }
    }

    @MainActor
    private func loadFavoritesIfNeeded(force: Bool = false) async {
        if !force, case .loaded = loadState {
            return
        }

        loadState = .loading
        feedback = nil
        do {
            let targets = try await loadTargets()
            guard !Task.isCancelled else { return }
            loadState = .loaded(targets)
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func enqueue(_ items: [ComicListItem]) {
        var summary = FavoriteDownloadAllSummary()
        for item in items {
            let result = downloadService.enqueue(
                item: item,
                downloadsComments: downloadsComments && item.supportsComments
            )
            summary.record(result)
        }

        let result = summary.feedback(total: items.count)
        guard summary.queuedBooks > 0 else {
            feedback = result
            return
        }

        dismiss()
    }

    private func statusText(for item: ComicListItem) -> String? {
        if downloadService.task(for: item) != nil {
            return "已在下载队列"
        }
        if let record = downloadService.record(for: item),
           record.totalChapterCount > 0,
           record.chapters.count >= record.totalChapterCount {
            return "已下载完成"
        }
        return nil
    }
}

private struct FavoriteDownloadScopeRow: View {
    let context: FavoriteDownloadSheetContext
    let loadedCount: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.systemImage)
                .font(.title3)
                .foregroundStyle(context.accentColor)
                .frame(width: 36, height: 36)
                .background(context.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 5)
    }

    private var subtitle: String {
        if isLoading {
            let countText = "已加载 \(loadedCount) 本"
            if context.mayLoadMoreFavorites {
                return "\(countText)，正在加载剩余页面"
            }
            return "\(countText)，正在准备"
        }
        return "共 \(loadedCount) 本漫画"
    }
}

private struct FavoriteDownloadComicRow: View {
    let item: ComicListItem
    let statusText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: item.coverURL, accentColor: item.accentColor, width: 46, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(item.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let statusText {
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private enum FavoriteDownloadAllLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

private struct FavoriteDownloadAllFooter: View {
    let message: String?
    let buttonTitle: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 10) {
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                button
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var button: some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.glassProminent)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        }
    }

    private var buttonLabel: some View {
        Text(buttonTitle)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
    }
}

private enum FavoriteDownloadAllError: LocalizedError {
    case searchActive

    var errorDescription: String? {
        switch self {
        case .searchActive:
            return "搜索结果不支持一键下载。请清空搜索后再试。"
        }
    }
}

private struct FavoriteDownloadAllFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct FavoriteDownloadAllSummary {
    var queuedBooks = 0
    var queuedChapters = 0
    var alreadyDownloadingBooks = 0
    var alreadyDownloadedBooks = 0
    var emptySelectionBooks = 0
    var failedBooks = 0
    var firstFailureMessage: String?

    mutating func record(_ result: DownloadEnqueueResult) {
        switch result {
        case .queued(let count):
            queuedBooks += 1
            queuedChapters += count
        case .alreadyDownloading:
            alreadyDownloadingBooks += 1
        case .alreadyDownloaded:
            alreadyDownloadedBooks += 1
        case .emptySelection:
            emptySelectionBooks += 1
        }
    }

    mutating func recordFailure(_ error: Error) {
        failedBooks += 1
        if firstFailureMessage == nil {
            firstFailureMessage = error.localizedDescription
        }
    }

    func feedback(total: Int) -> FavoriteDownloadAllFeedback {
        let title: String
        if queuedBooks > 0, failedBooks == 0 {
            title = "已加入下载队列"
        } else if queuedBooks > 0 {
            title = "已加入部分下载"
        } else if failedBooks == total {
            title = "一键下载失败"
        } else {
            title = "没有新的下载"
        }

        var parts: [String] = []
        if queuedBooks > 0 {
            if queuedChapters > 0 {
                parts.append("已加入 \(queuedBooks) 本漫画，共 \(queuedChapters) 章。")
            } else {
                parts.append("已加入 \(queuedBooks) 本漫画，章节会在任务开始时解析。")
            }
        }
        if alreadyDownloadingBooks > 0 {
            parts.append("\(alreadyDownloadingBooks) 本已有下载任务。")
        }
        if alreadyDownloadedBooks > 0 {
            parts.append("\(alreadyDownloadedBooks) 本已下载完成。")
        }
        if emptySelectionBooks > 0 {
            parts.append("\(emptySelectionBooks) 本没有可加入的章节。")
        }
        if failedBooks > 0 {
            if let firstFailureMessage {
                parts.append("\(failedBooks) 本准备失败，首个错误：\(firstFailureMessage)")
            } else {
                parts.append("\(failedBooks) 本准备失败。")
            }
        }
        if parts.isEmpty {
            parts.append("当前收藏夹没有需要下载的章节。")
        }

        return FavoriteDownloadAllFeedback(title: title, message: parts.joined(separator: "\n"))
    }
}

private struct LoadingFavoriteListView: View {
    let accentColor: Color

    var body: some View {
        LoadingStateView(title: "正在加载收藏")
    }
}

private enum FavoriteCollectionSource: Identifiable {
    case local(LocalFavoriteFolder)
    case platform(PlatformAccount)
    case platformFolder(PlatformAccount, PlatformFavoriteFolder)

    var id: String {
        switch self {
        case .local(let folder):
            return "local-\(folder.id)"
        case .platform(let account):
            return "platform-\(account.platform.id)"
        case .platformFolder(let account, let folder):
            return "platform-\(account.platform.id)-folder-\(folder.id)"
        }
    }

    var title: String {
        switch self {
        case .local(let folder):
            return folder.title
        case .platform(let account):
            return account.platform.title
        case .platformFolder(_, let folder):
            return folder.title
        }
    }

    var systemImage: String {
        switch self {
        case .local:
            return "folder"
        case .platform(let account):
            return account.platform.systemImage
        case .platformFolder(let account, _):
            return account.platform.systemImage
        }
    }

    var accentColor: Color {
        switch self {
        case .local:
            return .orange
        case .platform(let account):
            return account.platform.accentColor
        case .platformFolder(let account, _):
            return account.platform.accentColor
        }
    }

    var usesLocalBatching: Bool {
        if case .local = self {
            return true
        }
        return false
    }
}

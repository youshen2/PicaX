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
    @State private var searchText = ""
    @State private var nextFavoritePage = 2
    @State private var hasMoreRemoteFavorites = false
    @State private var loadedComicIDs = Set<String>()
    @State private var readingListRequest: ReadingListRequest?

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
            refreshFilteredComics(resetVisibleCount: true)
        }
        .navigationDestination(item: $readingListRequest) { request in
            ReadingListReaderPage(request: request, service: service)
        }
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

    private var visibleComics: [ComicListItem] {
        guard source.usesLocalBatching else {
            return filteredComics
        }
        return Array(filteredComics.prefix(visibleLocalComicCount))
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

    private func loadMoreLocalComics() {
        guard source.usesLocalBatching, visibleLocalComicCount < filteredComics.count else { return }
        visibleLocalComicCount = min(filteredComics.count, visibleLocalComicCount + Self.localFavoriteBatchSize)
    }

    private func refreshFilteredComics(resetVisibleCount: Bool) {
        filteredComics = filteredFavorites(from: comics)
        if resetVisibleCount {
            visibleLocalComicCount = Self.localFavoriteInitialCount
        }
    }

    private func filteredFavorites(from comics: [ComicListItem]) -> [ComicListItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return comics }
        return comics.filter { comicMatches($0, keyword: keyword) }
    }

    private func comicMatches(_ comic: ComicListItem, keyword: String) -> Bool {
        comic.title.localizedCaseInsensitiveContains(keyword)
            || comic.subtitle.localizedCaseInsensitiveContains(keyword)
            || comic.id.localizedCaseInsensitiveContains(keyword)
            || comic.platformTitle.localizedCaseInsensitiveContains(keyword)
            || (comic.pageText?.localizedCaseInsensitiveContains(keyword) ?? false)
            || comic.metadataText.localizedCaseInsensitiveContains(keyword)
            || comic.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
    }

    @MainActor
    private func load(force: Bool = false) async {
        if !force, !comics.isEmpty {
            isLoading = false
            refreshFilteredComics(resetVisibleCount: false)
            return
        }

        isLoading = true
        isLoadingMoreFavorites = false
        errorMessage = nil
        do {
            switch source {
            case .local(let folder):
                comics = service.loadLocalFavorites(folder: folder)
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
            loadedComicIDs = Set(comics.map(\.readingHistoryID))
            refreshFilteredComics(resetVisibleCount: true)
        } catch {
            errorMessage = error.localizedDescription
            comics = []
            filteredComics = []
            hasMoreRemoteFavorites = false
            loadedComicIDs = []
        }
        isLoading = false
    }

    @MainActor
    private func loadMoreRemoteFavorites() async {
        guard hasMoreRemoteFavorites, !isLoadingMoreFavorites else { return }
        isLoadingMoreFavorites = true
        do {
            try await loadNextRemoteFavoritesPage()
        } catch {
            errorMessage = error.localizedDescription
            hasMoreRemoteFavorites = false
        }
        isLoadingMoreFavorites = false
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

        let oldCount = comics.count
        appendUniqueFavorites(page.items)
        nextFavoritePage = page.page + 1
        hasMoreRemoteFavorites = page.hasMore && comics.count > oldCount
        if refreshFiltered {
            refreshFilteredComics(resetVisibleCount: false)
        }
    }

    private func appendUniqueFavorites(_ newItems: [ComicListItem]) {
        for item in newItems where loadedComicIDs.insert(item.readingHistoryID).inserted {
            comics.append(item)
        }
    }

    @MainActor
    private func prepareReadAll() async {
        guard !isPreparingReadAll else { return }
        isPreparingReadAll = true
        do {
            try await loadCompleteFavoritesForReading()
            refreshFilteredComics(resetVisibleCount: false)
            readingListRequest = ReadingListRequest(
                title: source.title,
                entries: filteredComics.map(ReadingListEntry.online)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparingReadAll = false
    }

    @MainActor
    private func loadCompleteFavoritesForReading() async throws {
        guard !source.usesLocalBatching else { return }
        while hasMoreRemoteFavorites, nextFavoritePage <= 200 {
            try await loadNextRemoteFavoritesPage(refreshFiltered: false)
        }
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

import Combine
import Foundation

@MainActor
final class WatchComicListViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchComicItem]> = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false

    private let client: WatchComicAPIClient
    private var currentPage = 0
    private var loadedKeys = Set<String>()

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func loadLocalFavorites(force: Bool = false) async {
        if case .loaded = state, !force { return }
        let items = WatchLocalFavoritesStore().load().map(WatchComicItem.init(localFavorite:))
        isLoadingMore = false
        hasMore = false
        currentPage = 0
        state = .loaded(items)
    }

    func loadExplore(platform: WatchComicPlatform, kind: WatchDiscoveryKind, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            replaceItems(try await client.loadExplore(platform: platform, kind: kind, account: account, page: 1))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreExplore(platform: WatchComicPlatform, kind: WatchDiscoveryKind, account: WatchPlatformAccount?) async {
        await loadMore { nextPage in
            try await client.loadExplore(platform: platform, kind: kind, account: account, page: nextPage)
        }
    }

    func loadFavorites(account: WatchPlatformAccount, folder: WatchFavoriteFolder? = nil, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            replaceItems(try await client.loadFavorites(account: account, folder: folder, page: 1))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreFavorites(account: WatchPlatformAccount, folder: WatchFavoriteFolder? = nil) async {
        await loadMore { nextPage in
            try await client.loadFavorites(account: account, folder: folder, page: nextPage)
        }
    }

    func loadCategory(_ category: WatchCategoryItem, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            replaceItems(try await client.loadCategoryComics(category, account: account, page: 1))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreCategory(_ category: WatchCategoryItem, account: WatchPlatformAccount?) async {
        await loadMore { nextPage in
            try await client.loadCategoryComics(category, account: account, page: nextPage)
        }
    }

    private func replaceItems(_ items: [WatchComicItem]) {
        loadedKeys.removeAll()
        currentPage = 1
        isLoadingMore = false
        let unique = uniqueItems(from: items)
        hasMore = !items.isEmpty
        state = .loaded(unique)
    }

    private func loadMore(_ loader: (Int) async throws -> [WatchComicItem]) async {
        guard hasMore, !isLoadingMore, case .loaded(let currentItems) = state else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let items = try await loader(nextPage)
            currentPage = nextPage
            hasMore = !items.isEmpty
            let unique = uniqueItems(from: items)
            guard !unique.isEmpty else {
                state = .loaded(currentItems)
                return
            }
            state = .loaded(currentItems + unique)
        } catch {
            hasMore = false
        }
    }

    private func uniqueItems(from items: [WatchComicItem]) -> [WatchComicItem] {
        items.filter { loadedKeys.insert("\($0.platform.id)-\($0.id)").inserted }
    }
}

@MainActor
final class WatchFavoriteFoldersViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchFavoriteFolder]> = .idle

    private let client: WatchComicAPIClient

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func load(account: WatchPlatformAccount, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            state = .loaded(try await client.loadFavoriteFolders(account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class WatchSearchViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchComicItem]> = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var hasSearched = false

    private let client: WatchComicAPIClient
    private var currentPages: [WatchComicPlatform: Int] = [:]
    private var platformHasMore: [WatchComicPlatform: Bool] = [:]
    private var loadedKeys = Set<String>()
    private var currentTarget: WatchSearchTarget?
    private var currentKeyword = ""
    private var currentOptions = WatchSearchOptions()

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func trimmedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(
        target: WatchSearchTarget,
        keyword: String,
        accounts: [WatchComicPlatform: WatchPlatformAccount],
        options: WatchSearchOptions,
        force: Bool = false
    ) async {
        let trimmed = trimmedKeyword(keyword)
        guard !trimmed.isEmpty else {
            reset()
            return
        }
        if case .loaded = state, !force, currentTarget == target, currentKeyword == trimmed, currentOptions == options {
            return
        }

        state = .loading
        hasSearched = true
        hasMore = false
        isLoadingMore = false
        currentPages.removeAll()
        platformHasMore.removeAll()
        loadedKeys.removeAll()
        currentTarget = target
        currentKeyword = trimmed
        currentOptions = options

        var groups: [[WatchComicItem]] = []
        var failures: [String] = []
        for platform in target.platforms {
            do {
                let items = try await client.search(
                    platform: platform,
                    keyword: trimmed,
                    account: accounts[platform],
                    page: 1,
                    options: options
                )
                currentPages[platform] = 1
                platformHasMore[platform] = !items.isEmpty
                groups.append(items)
            } catch {
                currentPages[platform] = 0
                platformHasMore[platform] = false
                failures.append("\(platform.title): \(error.localizedDescription)")
            }
        }

        let items = uniqueItems(from: interleaved(groups))
        hasMore = platformHasMore.values.contains(true)
        if !items.isEmpty || failures.count < target.platforms.count {
            state = .loaded(items)
        } else {
            state = .failed(failures.joined(separator: "\n"))
        }
    }

    func loadMore(accounts: [WatchComicPlatform: WatchPlatformAccount]) async {
        guard hasMore,
              !isLoadingMore,
              case .loaded(let currentItems) = state,
              let target = currentTarget,
              !currentKeyword.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        var groups: [[WatchComicItem]] = []
        for platform in target.platforms where platformHasMore[platform] == true {
            do {
                let nextPage = (currentPages[platform] ?? 1) + 1
                let items = try await client.search(
                    platform: platform,
                    keyword: currentKeyword,
                    account: accounts[platform],
                    page: nextPage,
                    options: currentOptions
                )
                currentPages[platform] = nextPage
                platformHasMore[platform] = !items.isEmpty
                groups.append(items)
            } catch {
                platformHasMore[platform] = false
            }
        }

        let newItems = uniqueItems(from: interleaved(groups))
        hasMore = platformHasMore.values.contains(true)
        guard !newItems.isEmpty else { return }
        state = .loaded(currentItems + newItems)
    }

    private func reset() {
        state = .idle
        isLoadingMore = false
        hasMore = false
        hasSearched = false
        currentPages.removeAll()
        platformHasMore.removeAll()
        loadedKeys.removeAll()
        currentTarget = nil
        currentKeyword = ""
        currentOptions = WatchSearchOptions()
    }

    private func interleaved(_ groups: [[WatchComicItem]]) -> [WatchComicItem] {
        let maxCount = groups.map(\.count).max() ?? 0
        guard maxCount > 0 else { return [] }
        var result: [WatchComicItem] = []
        for index in 0..<maxCount {
            for group in groups where group.indices.contains(index) {
                result.append(group[index])
            }
        }
        return result
    }

    private func uniqueItems(from items: [WatchComicItem]) -> [WatchComicItem] {
        items.filter { loadedKeys.insert("\($0.platform.id)-\($0.id)").inserted }
    }
}

@MainActor
final class WatchCategoriesViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchCategoryItem]> = .idle

    private let client: WatchComicAPIClient
    private var loadedPlatform: WatchComicPlatform?

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func load(platform: WatchComicPlatform, account: WatchPlatformAccount?, force: Bool = false) async {
        if loadedPlatform == platform, case .loaded = state, !force { return }
        loadedPlatform = platform
        state = .loading
        do {
            state = .loaded(try await client.loadCategories(platform: platform, account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class WatchComicDetailViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<WatchComicDetailInfo> = .idle

    private let client: WatchComicAPIClient

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func load(item: WatchComicItem, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        if !force, let cached = await WatchComicDetailCacheService.detail(for: item) {
            state = .loaded(cached)
        }
        do {
            let detail = try await client.loadDetail(item: item, account: account)
            state = .loaded(detail)
            await WatchComicDetailCacheService.store(detail)
        } catch {
            if case .loaded = state {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class WatchReaderViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchChapterImage]> = .idle

    private let client: WatchComicAPIClient
    private var loadedImages: [WatchChapterImage] = []

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func load(item: WatchComicItem, chapter: WatchChapterItem, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            let images = try await client.loadChapterImages(item: item, chapter: chapter, account: account)
            loadedImages = images
            state = .loaded(images)
            await prefetch(around: 0)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadLocalImages(_ images: [WatchChapterImage], force: Bool = false) async {
        if case .loaded = state, !force { return }
        loadedImages = images
        state = .loaded(images)
        await prefetch(around: 0)
    }

    func cachedURL(for image: WatchChapterImage) -> URL? {
        WatchImageCacheService.localCachedURL(for: image.urlString) ?? image.url
    }

    func prefetch(around pageIndex: Int) async {
        let images = loadedImages
        let count = UserDefaults.standard.object(forKey: WatchSettingsKey.readerPrefetchCount) == nil
            ? 2
            : UserDefaults.standard.integer(forKey: WatchSettingsKey.readerPrefetchCount)
        guard count > 0, !images.isEmpty else { return }
        let boundedCount = min(max(count, 0), 12)
        let start = max(pageIndex - 1, 0)
        let end = min(pageIndex + boundedCount, images.count - 1)
        for index in start...end {
            guard !Task.isCancelled else { return }
            _ = try? await WatchImageCacheService.cachedFileURL(for: images[index].urlString)
        }
    }
}

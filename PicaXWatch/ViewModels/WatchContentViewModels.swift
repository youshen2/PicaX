import Combine
import Foundation

@MainActor
final class WatchComicListViewModel: ObservableObject {
    @Published private(set) var state: WatchPageState<[WatchComicItem]> = .idle

    private let client: WatchComicAPIClient

    init(client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.client = client
    }

    func loadLocalFavorites(force: Bool = false) async {
        if case .loaded = state, !force { return }
        let items = WatchLocalFavoritesStore().load().map(WatchComicItem.init(localFavorite:))
        state = .loaded(items)
    }

    func loadExplore(platform: WatchComicPlatform, kind: WatchDiscoveryKind, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            state = .loaded(try await client.loadExplore(platform: platform, kind: kind, account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadFavorites(account: WatchPlatformAccount, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            state = .loaded(try await client.loadFavorites(account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadCategory(_ category: WatchCategoryItem, account: WatchPlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force { return }
        state = .loading
        do {
            state = .loaded(try await client.loadCategoryComics(category, account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
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
        do {
            state = .loaded(try await client.loadDetail(item: item, account: account))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

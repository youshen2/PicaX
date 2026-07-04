import SwiftUI

enum WatchComicListSource {
    case localFavorites
    case readLater
    case explore(platform: WatchComicPlatform, kind: WatchDiscoveryKind)
    case favorites(account: WatchPlatformAccount)
    case favoriteFolder(account: WatchPlatformAccount, folder: WatchFavoriteFolder)
    case category(WatchCategoryItem)

    var title: String {
        switch self {
        case .localFavorites:
            "本地收藏"
        case .readLater:
            "稍后再读"
        case .explore(let platform, let kind):
            "\(platform.title) \(kind.title)"
        case .favorites(let account):
            "\(account.title) 收藏"
        case .favoriteFolder(_, let folder):
            folder.title
        case .category(let category):
            category.title
        }
    }
}

struct WatchComicListPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @StateObject private var viewModel = WatchComicListViewModel()

    let source: WatchComicListSource

    var body: some View {
        List {
            WatchLoadStateSection(
                title: "漫画",
                state: viewModel.state,
                emptyTitle: "暂无漫画",
                emptySystemImage: "books.vertical",
                isEmpty: { $0.isEmpty }
            ) { items in
                ForEach(items) { item in
                    NavigationLink {
                        WatchComicDetailPage(item: item)
                    } label: {
                        WatchComicRow(item: item)
                    }
                        .swipeActions {
                            if source.isLocalFavorites {
                                Button(role: .destructive) {
                                    accountSyncStore.removeLocalFavorite(item)
                                    Task { await load(force: true) }
                                } label: {
                                    Label("取消收藏", systemImage: "heart.slash")
                                }
                            } else {
                                Button {
                                    accountSyncStore.addLocalFavorite(item)
                                } label: {
                                    Label("收藏", systemImage: "heart")
                                }
                            }

                            if source.isReadLater {
                                Button(role: .destructive) {
                                    accountSyncStore.removeReadLater(item)
                                    Task { await load(force: true) }
                                } label: {
                                    Label("移出稍后再读", systemImage: "bookmark.slash")
                                }
                            } else if accountSyncStore.isReadLater(item) {
                                Button(role: .destructive) {
                                    accountSyncStore.removeReadLater(item)
                                } label: {
                                    Label("移出稍后再读", systemImage: "bookmark.slash")
                                }
                            } else {
                                Button {
                                    accountSyncStore.addReadLater(item)
                                } label: {
                                    Label("稍后再读", systemImage: "bookmark")
                                }
                            }
                        }
                        .onAppear {
                            loadMoreIfNeeded(currentItem: item, items: items)
                        }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                }
            }
        }
        .navigationTitle(source.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
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

    private func load(force: Bool = false) async {
        switch source {
        case .localFavorites:
            await viewModel.loadLocalFavorites(force: force)
        case .readLater:
            await viewModel.loadReadLater(force: force)
        case .explore(let platform, let kind):
            await viewModel.loadExplore(
                platform: platform,
                kind: kind,
                account: accountSyncStore.snapshot.account(for: platform),
                force: force
            )
        case .favorites(let account):
            await viewModel.loadFavorites(account: account, force: force)
        case .favoriteFolder(let account, let folder):
            await viewModel.loadFavorites(account: account, folder: folder, force: force)
        case .category(let category):
            await viewModel.loadCategory(
                category,
                account: accountSyncStore.snapshot.account(for: category.platform),
                force: force
            )
        }
    }

    private func loadMoreIfNeeded(currentItem: WatchComicItem, items: [WatchComicItem]) {
        guard viewModel.hasMore, currentItem == items.last else { return }
        Task {
            await loadMore()
        }
    }

    private func loadMore() async {
        switch source {
        case .localFavorites, .readLater:
            return
        case .explore(let platform, let kind):
            await viewModel.loadMoreExplore(
                platform: platform,
                kind: kind,
                account: accountSyncStore.snapshot.account(for: platform)
            )
        case .favorites(let account):
            await viewModel.loadMoreFavorites(account: account)
        case .favoriteFolder(let account, let folder):
            await viewModel.loadMoreFavorites(account: account, folder: folder)
        case .category(let category):
            await viewModel.loadMoreCategory(
                category,
                account: accountSyncStore.snapshot.account(for: category.platform)
            )
        }
    }
}

private extension WatchComicListSource {
    var isLocalFavorites: Bool {
        if case .localFavorites = self {
            return true
        }
        return false
    }

    var isReadLater: Bool {
        if case .readLater = self {
            return true
        }
        return false
    }
}

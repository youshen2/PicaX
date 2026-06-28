import SwiftUI

enum WatchComicListSource {
    case localFavorites
    case explore(platform: WatchComicPlatform, kind: WatchDiscoveryKind)
    case favorites(account: WatchPlatformAccount)
    case category(WatchCategoryItem)

    var title: String {
        switch self {
        case .localFavorites:
            "本地收藏"
        case .explore(let platform, let kind):
            "\(platform.title) \(kind.title)"
        case .favorites(let account):
            "\(account.title) 收藏"
        case .category(let category):
            category.title
        }
    }
}

struct WatchComicListPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @AppStorage(WatchSettingsKey.maxVisibleComics) private var maxVisibleComics = 24
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
                ForEach(Array(items.prefix(validatedMaxVisibleComics))) { item in
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
                        }
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

    private var validatedMaxVisibleComics: Int {
        min(max(maxVisibleComics, 6), 60)
    }

    private func load(force: Bool = false) async {
        switch source {
        case .localFavorites:
            await viewModel.loadLocalFavorites(force: force)
        case .explore(let platform, let kind):
            await viewModel.loadExplore(
                platform: platform,
                kind: kind,
                account: accountSyncStore.snapshot.account(for: platform),
                force: force
            )
        case .favorites(let account):
            await viewModel.loadFavorites(account: account, force: force)
        case .category(let category):
            await viewModel.loadCategory(
                category,
                account: accountSyncStore.snapshot.account(for: category.platform),
                force: force
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
}

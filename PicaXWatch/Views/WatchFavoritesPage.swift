import SwiftUI

struct WatchFavoritesPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore

    var body: some View {
        List {
            Section("本地账号") {
                NavigationLink {
                    WatchComicListPage(source: .localFavorites)
                } label: {
                    WatchValueRow(
                        title: "本地收藏",
                        subtitle: "\(accountSyncStore.snapshot.localFavorites.count) 个收藏",
                        systemImage: "tray.full"
                    )
                }
            }

            Section("平台收藏") {
                let accounts = favoriteAccounts
                if accounts.isEmpty {
                    WatchEmptyRow(title: "暂无可用平台收藏", systemImage: "heart.slash")
                } else {
                    ForEach(accounts) { account in
                        NavigationLink {
                            if supportsFavoriteFolders(account) {
                                WatchFavoriteFoldersPage(account: account)
                            } else {
                                WatchComicListPage(source: .favorites(account: account))
                            }
                        } label: {
                            WatchValueRow(
                                title: account.title,
                                subtitle: account.displayName,
                                systemImage: WatchComicPlatform(rawValue: account.platformID)?.systemImage
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("收藏夹")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    accountSyncStore.requestRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("同步账号")
            }
        }
    }

    private var favoriteAccounts: [WatchPlatformAccount] {
        accountSyncStore.snapshot.platformAccounts.filter { account in
            WatchComicPlatform(rawValue: account.platformID)?.supportsFavorites == true
        }
    }

    private func supportsFavoriteFolders(_ account: WatchPlatformAccount) -> Bool {
        guard let platform = WatchComicPlatform(rawValue: account.platformID) else { return false }
        switch platform {
        case .eHentai, .jmComic, .htManga:
            return true
        case .picacg, .nhentai, .hitomi:
            return false
        }
    }
}

private struct WatchFavoriteFoldersPage: View {
    @StateObject private var viewModel = WatchFavoriteFoldersViewModel()

    let account: WatchPlatformAccount

    var body: some View {
        List {
            WatchLoadStateSection(
                title: "平台收藏夹",
                state: viewModel.state,
                emptyTitle: "暂无收藏夹",
                emptySystemImage: "folder",
                isEmpty: { $0.isEmpty }
            ) { folders in
                ForEach(folders) { folder in
                    NavigationLink {
                        WatchComicListPage(source: .favoriteFolder(account: account, folder: folder))
                    } label: {
                        WatchValueRow(
                            title: folder.title,
                            subtitle: folder.subtitle,
                            systemImage: WatchComicPlatform(rawValue: account.platformID)?.systemImage
                        )
                    }
                }
            }
        }
        .navigationTitle(account.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.load(account: account, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await viewModel.load(account: account)
        }
    }
}

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
                            WatchComicListPage(source: .favorites(account: account))
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
            ToolbarItem(placement: .topBarTrailing) {
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
}

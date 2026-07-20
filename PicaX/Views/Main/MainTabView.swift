import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                PicaxNavigationContainer {
                    tabContent(for: tab)
                        .navigationTitle(tab.title)
                        .toolbar {
                            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                                NavigationLink {
                                    ComicSearchPage()
                                        .picaxHidesTabBar()
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .accessibilityLabel("搜索")

                                NavigationLink {
                                    SettingsPage()
                                        .picaxHidesTabBar()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                                .accessibilityLabel("设置")
                            }
                        }
                }
                .tabItem {
                    Label(tab.title, systemImage: selectedTab == tab ? tab.selectedSystemImage : tab.systemImage)
                }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomePage()
        case .favorites:
            FavoritesPage()
        case .explore:
            ExplorePage()
        case .categories:
            CategoriesPage()
        }
    }

}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AccountService(store: AccountStore(defaults: .preview)))
            .environmentObject(PlatformAccountService())
            .environmentObject(ReadingHistoryService(defaults: .preview))
            .environmentObject(ReadLaterService(defaults: .preview))
            .environmentObject(ReadingDurationService(defaults: .preview))
            .environmentObject(DownloadService(defaults: .preview))
            .environmentObject(BlockingKeywordService(defaults: .preview))
            .environmentObject(SearchHistoryService(defaults: .preview))
            .environmentObject(FollowUpdatesService(defaults: .preview))
    }
}

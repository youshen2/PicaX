import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    @State private var isTabBarVisible = true
    @State private var tabBarHideRequests: Set<UUID> = []

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
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
                .picaxTabBarVisibilityHost(
                    isVisible: isTabBarVisible,
                    setHidden: setTabBarHidden
                )
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

    private func setTabBarHidden(_ requestID: UUID, _ hidden: Bool) {
        if hidden {
            tabBarHideRequests.insert(requestID)
        } else {
            tabBarHideRequests.remove(requestID)
        }

        let nextIsVisible = tabBarHideRequests.isEmpty
        guard nextIsVisible != isTabBarVisible else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            isTabBarVisible = nextIsVisible
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AccountService(store: AccountStore(defaults: .preview)))
            .environmentObject(PlatformAccountService(defaults: .preview))
            .environmentObject(ReadingHistoryService(defaults: .preview))
            .environmentObject(DownloadService(defaults: .preview))
            .environmentObject(BlockingKeywordService(defaults: .preview))
            .environmentObject(SearchHistoryService(defaults: .preview))
    }
}

import SwiftUI

struct MainTabView: View {
    private enum Selection: Hashable {
        case app(AppTab)
        case search
    }

    @State private var selectedTab: Selection = .app(.home)

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            searchIntegratedTabView
        } else {
            legacyTabView
        }
        #else
        legacyTabView
        #endif
    }

    #if os(iOS)
    @available(iOS 18.0, *)
    private var searchIntegratedTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(
                    tab.title,
                    systemImage: selectedTab == .app(tab) ? tab.selectedSystemImage : tab.systemImage,
                    value: Selection.app(tab)
                ) {
                    tabNavigationContainer(for: tab, includesSearchButton: false)
                }
            }

            Tab("搜索", systemImage: "magnifyingglass", value: Selection.search, role: .search) {
                PicaxNavigationContainer {
                    ComicSearchPage(hidesTabBar: false)
                }
            }
        }
    }
    #endif

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabNavigationContainer(for: tab, includesSearchButton: true)
                    .tabItem {
                        Label(
                            tab.title,
                            systemImage: selectedTab == .app(tab) ? tab.selectedSystemImage : tab.systemImage
                        )
                    }
                    .tag(Selection.app(tab))
            }
        }
    }

    private func tabNavigationContainer(for tab: AppTab, includesSearchButton: Bool) -> some View {
        PicaxNavigationContainer {
            tabContent(for: tab)
                .navigationTitle(tab.title)
                .toolbar {
                    ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                        if includesSearchButton {
                            NavigationLink {
                                ComicSearchPage()
                                    .picaxHidesTabBar()
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel("搜索")
                        }

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

import SwiftUI

struct SettingsRootContent: View {
    let routes: [SettingsRoute]

    var body: some View {
        settingsSection("账号", routes: [.platformAccounts])
        settingsSection(
            "浏览与阅读",
            routes: [.home, .explore, .search, .comicList, .comicDetail, .reader]
        )
        settingsSection(
            "内容与数据",
            routes: [.downloads, .history, .readingDuration, .blockingKeywords, .storage, .backup]
        )
        settingsSection(
            "网络与应用",
            routes: [.appDisplay, .appBehavior, .watchConnectivity, .network, .about]
        )
    }

    @ViewBuilder
    private func settingsSection(_ title: String, routes sectionRoutes: [SettingsRoute]) -> some View {
        let visibleRoutes = sectionRoutes.filter(routes.contains)

        if !visibleRoutes.isEmpty {
            Section(title) {
                ForEach(visibleRoutes) { route in
                    SettingsRouteLink(route: route)
                }
            }
        }
    }
}

struct SettingsRouteLink: View {
    let route: SettingsRoute

    var body: some View {
        NavigationLink {
            SettingsDestinationView(route: route)
        } label: {
            Label(route.title, systemImage: route.systemImage)
        }
    }
}

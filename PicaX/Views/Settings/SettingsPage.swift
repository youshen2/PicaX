import SwiftUI

struct SettingsPage: View {
    @State private var searchText = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingRoutes: [SettingsRoute] {
        SettingsRoute.allCases.filter { $0.matches(normalizedSearchText) }
    }

    init(searchText: String = "") {
        _searchText = State(initialValue: searchText)
    }

    var body: some View {
        List {
            if matchingRoutes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "没有找到设置",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词再试。")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                SettingsRootContent(routes: matchingRoutes)
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("设置")
        .searchable(
            text: $searchText,
            placement: .picaxNavigationSearch,
            prompt: "搜索设置"
        )
        .picaxHidesTabBar()
    }
}

struct SettingsPage_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PicaxNavigationContainer {
                SettingsPage()
            }
            .previewDisplayName("概览")

            PicaxNavigationContainer {
                SettingsPage(searchText: "阅读")
            }
            .previewDisplayName("搜索结果")
        }
        .environmentObject(PlatformAccountService())
    }
}

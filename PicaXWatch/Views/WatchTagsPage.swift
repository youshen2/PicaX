import SwiftUI

struct WatchTagsPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @AppStorage(WatchSettingsKey.defaultTagsPlatform) private var selectedPlatformID = WatchComicPlatform.picacg.rawValue
    @StateObject private var viewModel = WatchCategoriesViewModel()

    var body: some View {
        List {
            Section("平台") {
                Picker("平台", selection: selectedPlatform) {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
            }

            WatchLoadStateSection(
                title: "标签",
                state: viewModel.state,
                emptyTitle: "暂无标签",
                emptySystemImage: "tag.slash",
                isEmpty: { $0.isEmpty }
            ) { items in
                ForEach(groupedItems(items: items)) { group in
                    if let title = group.title {
                        WatchValueRow(title: title, subtitle: "\(group.items.count) 个标签", systemImage: "folder")
                    }
                    ForEach(group.items) { item in
                        NavigationLink {
                            WatchComicListPage(source: .category(item))
                        } label: {
                            WatchValueRow(title: item.title, subtitle: item.subtitle, systemImage: "tag")
                        }
                    }
                }
            }
        }
        .navigationTitle("标签")
        .task(id: selectedPlatform.wrappedValue) {
            await load()
        }
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
    }

    private var selectedPlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: selectedPlatformID) ?? .picacg },
            set: { selectedPlatformID = $0.rawValue }
        )
    }

    private func load(force: Bool = false) async {
        let platform = selectedPlatform.wrappedValue
        await viewModel.load(
            platform: platform,
            account: accountSyncStore.snapshot.account(for: platform),
            force: force
        )
    }

    private func groupedItems(items: [WatchCategoryItem]) -> [WatchCategoryDisplayGroup] {
        let grouped = Dictionary(grouping: items) { $0.groupTitle }
        return grouped.keys.sorted { ($0 ?? "") < ($1 ?? "") }.map { key in
            WatchCategoryDisplayGroup(title: key, items: grouped[key] ?? [])
        }
    }
}

private struct WatchCategoryDisplayGroup: Identifiable {
    let title: String?
    let items: [WatchCategoryItem]

    var id: String {
        title ?? "default"
    }
}

import SwiftUI

struct CategoriesPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @StateObject private var viewModel = CategoriesViewModel(service: ComicContentService())
    @State private var selectedPlatform: ComicPlatform = .picacg

    var body: some View {
        List {
            Section {
                Picker("平台", selection: $selectedPlatform) {
                    ForEach(ComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
                .pickerStyle(.menu)
            }

            switch viewModel.state {
            case .idle, .loading:
                CategoryLoadingSection()
            case .loaded(let items, let visibleCount):
                if items.isEmpty {
                    Section {
                        ContentUnavailableView("暂无分类", systemImage: "square.grid.2x2")
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedItems(items: Array(items.prefix(visibleCount)))) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                NavigationLink {
                                    ComicSearchPage(
                                        initialQuery: searchQuery(for: item),
                                        platform: item.platform,
                                        recordsInitialSearchInHistory: false
                                    )
                                } label: {
                                    CategoryListRow(item: item)
                                }
                            }
                        }
                    }

                    if viewModel.canLoadMore {
                        Section {
                            CategoryAutoLoadRow()
                                .onAppear {
                                    viewModel.loadMoreCategories()
                                }
                        }
                    }
                }
            case .failed(let message):
                Section {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await loadCategories(force: true) }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("分类")
        .task(id: selectedPlatform) {
            await loadCategories()
        }
    }

    private func loadCategories(force: Bool = false) async {
        await viewModel.load(
            platform: selectedPlatform,
            account: platformAccounts.account(for: selectedPlatform),
            force: force
        )
    }

    private func searchQuery(for item: ComicCategoryItem) -> String {
        let categoryPrefix = "category:"
        guard item.query.hasPrefix(categoryPrefix) else {
            return item.query
        }
        return String(item.query.dropFirst(categoryPrefix.count))
    }

    private func groupedItems(items: [ComicCategoryItem]) -> [CategoryDisplayGroup] {
        var groups = [CategoryDisplayGroup]()
        for item in items {
            let title = item.groupTitle ?? selectedPlatform.title
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index].items.append(item)
            } else {
                groups.append(CategoryDisplayGroup(title: title, items: [item]))
            }
        }
        return groups
    }
}

private struct CategoryDisplayGroup: Identifiable {
    let title: String
    var items: [ComicCategoryItem]

    var id: String { title }
}

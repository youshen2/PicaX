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
                    Section(selectedPlatform.title) {
                        ForEach(items.prefix(visibleCount)) { item in
                            NavigationLink {
                                ComicSearchPage(initialQuery: searchQuery(for: item), platform: item.platform)
                            } label: {
                                CategoryListRow(item: item)
                            }
                        }

                        if viewModel.canLoadMore {
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
}

import SwiftUI

struct WatchSearchPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @AppStorage(WatchSettingsKey.defaultSearchTargetMode) private var defaultTargetMode = WatchSearchDefaultTargetMode.platform.rawValue
    @AppStorage(WatchSettingsKey.defaultSearchPlatform) private var defaultSearchPlatformID = WatchComicPlatform.picacg.rawValue
    @AppStorage(WatchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = WatchComicPlatform.allCases.map(\.rawValue).joined(separator: ",")

    @StateObject private var viewModel = WatchSearchViewModel()
    @StateObject private var searchHistory = WatchSearchHistoryStore()
    @State private var query: String
    @State private var selectedTarget: WatchSearchTarget
    @State private var aggregatePlatforms = Set(WatchComicPlatform.allCases)
    @State private var searchOptions = WatchSearchOptions()
    @State private var hasAppliedDefaultTarget = false

    private let usesConfiguredDefaultTarget: Bool
    private let recordsInitialSearchInHistory: Bool

    init(initialQuery: String = "", platform: WatchComicPlatform? = nil, recordsInitialSearchInHistory: Bool = true) {
        self.usesConfiguredDefaultTarget = platform == nil
        self.recordsInitialSearchInHistory = recordsInitialSearchInHistory
        _query = State(initialValue: initialQuery)
        _selectedTarget = State(initialValue: platform.map(WatchSearchTarget.platform) ?? .platform(.picacg))
    }

    var body: some View {
        List {
            searchControls
            aggregatePlatformControls
            searchContent
        }
        .navigationTitle("搜索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await performSearch(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.trimmedKeyword(query).isEmpty)
                .accessibilityLabel("刷新")
            }
        }
        .task {
            applyConfiguredDefaultTargetIfNeeded()
            guard !viewModel.hasSearched, !viewModel.trimmedKeyword(query).isEmpty else { return }
            await performSearch(force: true, recordsHistory: recordsInitialSearchInHistory)
        }
    }

    private var searchControls: some View {
        Section("搜索") {
            TextField("关键词、作者、标签", text: $query)
                .submitLabel(.search)
                .onSubmit {
                    Task { await performSearch(force: true) }
                }

            Picker("搜索源", selection: $selectedTarget) {
                Text("多平台聚合")
                    .tag(WatchSearchTarget.defaultAggregate)
                ForEach(WatchComicPlatform.allCases) { platform in
                    Text(platform.title)
                        .tag(WatchSearchTarget.platform(platform))
                }
            }

            NavigationLink {
                WatchSearchOptionsPage(target: selectedTarget, options: $searchOptions)
            } label: {
                WatchValueRow(
                    title: "高级选项",
                    subtitle: searchOptionsSubtitle,
                    systemImage: "slider.horizontal.3"
                )
            }

            Button {
                Task { await performSearch(force: true) }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.trimmedKeyword(query).isEmpty)
        }
    }

    @ViewBuilder
    private var aggregatePlatformControls: some View {
        if selectedTarget.isAggregate {
            Section("聚合平台") {
                ForEach(WatchComicPlatform.allCases) { platform in
                    Toggle(isOn: aggregatePlatformBinding(platform)) {
                        Label(platform.title, systemImage: platform.systemImage)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.state {
        case .idle:
            if searchHistory.isEnabled, !searchHistory.records.isEmpty {
                Section("搜索历史") {
                    ForEach(searchHistory.records) { record in
                        Button {
                            applyHistory(record)
                        } label: {
                            WatchSearchHistoryRow(record: record)
                        }
                    }
                    .onDelete { offsets in
                        searchHistory.remove(at: offsets)
                    }
                }
            } else {
                Section {
                    WatchEmptyRow(title: "输入关键词开始搜索", systemImage: "magnifyingglass")
                }
            }
        case .loading:
            Section("结果") {
                ProgressView()
            }
        case .loaded(let items):
            Section("结果") {
                if items.isEmpty {
                    WatchEmptyRow(title: "暂无结果", systemImage: "magnifyingglass")
                } else {
                    ForEach(items, id: \.self) { item in
                        NavigationLink {
                            WatchComicDetailPage(item: item)
                        } label: {
                            WatchComicRow(item: item)
                        }
                        .swipeActions {
                            Button {
                                accountSyncStore.addLocalFavorite(item)
                            } label: {
                                Label("收藏", systemImage: "heart")
                            }

                            if accountSyncStore.isReadLater(item) {
                                Button(role: .destructive) {
                                    accountSyncStore.removeReadLater(item)
                                } label: {
                                    Label("移出稍后再读", systemImage: "bookmark.slash")
                                }
                            } else {
                                Button {
                                    accountSyncStore.addReadLater(item)
                                } label: {
                                    Label("稍后再读", systemImage: "bookmark")
                                }
                            }
                        }
                        .onAppear {
                            loadMoreIfNeeded(currentItem: item, items: items)
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                    }
                }
            }
        case .failed(let message):
            Section("搜索失败") {
                WatchValueRow(title: "加载失败", subtitle: message, systemImage: "exclamationmark.triangle", tint: .orange)
                Button {
                    Task { await performSearch(force: true, recordsHistory: false) }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var searchAccounts: [WatchComicPlatform: WatchPlatformAccount] {
        Dictionary(uniqueKeysWithValues: WatchComicPlatform.allCases.compactMap { platform in
            accountSyncStore.snapshot.account(for: platform).map { (platform, $0) }
        })
    }

    private var configuredDefaultTarget: WatchSearchTarget {
        switch WatchSearchDefaultTargetMode(rawValue: defaultTargetMode) ?? .platform {
        case .platform:
            .platform(WatchComicPlatform(rawValue: defaultSearchPlatformID) ?? .picacg)
        case .aggregate:
            .aggregate(
                defaultAggregatePlatformIDs
                    .split(separator: ",")
                    .compactMap { WatchComicPlatform(rawValue: String($0)) }
            )
        }
    }

    private var searchOptionsSubtitle: String {
        let customizedPlatforms = selectedTarget.platforms.filter { searchOptions.isCustomized(for: $0) }
        if customizedPlatforms.isEmpty {
            return "排序和语言筛选"
        }
        return customizedPlatforms.map(\.title).joined(separator: "、")
    }

    private func applyConfiguredDefaultTargetIfNeeded() {
        guard usesConfiguredDefaultTarget, !hasAppliedDefaultTarget, !viewModel.hasSearched else { return }
        hasAppliedDefaultTarget = true
        selectedTarget = configuredDefaultTarget
        if case .aggregate(let platforms) = selectedTarget {
            aggregatePlatforms = Set(platforms)
        }
    }

    private func aggregatePlatformBinding(_ platform: WatchComicPlatform) -> Binding<Bool> {
        Binding(
            get: { aggregatePlatforms.contains(platform) },
            set: { isOn in
                var nextPlatforms = aggregatePlatforms
                if isOn {
                    nextPlatforms.insert(platform)
                } else {
                    guard nextPlatforms.count > 1 else { return }
                    nextPlatforms.remove(platform)
                }
                aggregatePlatforms = nextPlatforms
                selectedTarget = .aggregate(WatchComicPlatform.allCases.filter { nextPlatforms.contains($0) })
            }
        )
    }

    private func performSearch(force: Bool, recordsHistory: Bool = true) async {
        let trimmed = viewModel.trimmedKeyword(query)
        guard !trimmed.isEmpty else { return }
        query = trimmed
        if recordsHistory {
            searchHistory.record(keyword: trimmed, target: selectedTarget)
        }
        await viewModel.search(
            target: selectedTarget,
            keyword: trimmed,
            accounts: searchAccounts,
            options: searchOptions,
            force: force
        )
    }

    private func applyHistory(_ record: WatchSearchHistoryRecord) {
        query = record.keyword
        selectedTarget = record.target
        if case .aggregate(let platforms) = record.target {
            aggregatePlatforms = Set(platforms)
        }
        Task { await performSearch(force: true) }
    }

    private func loadMoreIfNeeded(currentItem: WatchComicItem, items: [WatchComicItem]) {
        guard viewModel.hasMore, currentItem == items.last else { return }
        Task {
            await viewModel.loadMore(accounts: searchAccounts)
        }
    }
}

private struct WatchSearchHistoryRow: View {
    let record: WatchSearchHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(record.keyword, systemImage: record.target.systemImage)
                .font(.headline)
                .lineLimit(1)
            Text("\(record.target.title) · \(record.searchedAt.formatted(date: .numeric, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct WatchSearchOptionsPage: View {
    let target: WatchSearchTarget
    @Binding var options: WatchSearchOptions

    var body: some View {
        List {
            ForEach(target.platforms) { platform in
                if !platform.searchSortChoices.isEmpty {
                    Section(platform.title) {
                        Picker("排序", selection: sortBinding(for: platform)) {
                            ForEach(platform.searchSortChoices) { choice in
                                Text(choice.title)
                                    .tag(choice.value)
                            }
                        }
                    }
                }
            }

            if target.platforms.contains(.nhentai) {
                Section("NHentai") {
                    Picker("语言", selection: nhentaiLanguageBinding) {
                        Text("不限")
                            .tag(WatchSearchLanguage?.none)
                        ForEach(WatchSearchLanguage.allCases) { language in
                            Text(language.title)
                                .tag(WatchSearchLanguage?.some(language))
                        }
                    }
                }
            }

            if target.platforms.allSatisfy({ $0.searchSortChoices.isEmpty }) && !target.platforms.contains(.nhentai) {
                Section {
                    WatchEmptyRow(title: "当前平台暂无高级选项", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("高级选项")
    }

    private func sortBinding(for platform: WatchComicPlatform) -> Binding<String> {
        Binding(
            get: { options.sortValue(for: platform) },
            set: { options.setSortValue($0, for: platform) }
        )
    }

    private var nhentaiLanguageBinding: Binding<WatchSearchLanguage?> {
        Binding(
            get: { options.nhentaiLanguage },
            set: { options.nhentaiLanguage = $0 }
        )
    }
}

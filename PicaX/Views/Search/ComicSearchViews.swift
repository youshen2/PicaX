import Combine
import SwiftUI

enum ComicSearchTarget: Hashable, Identifiable, Sendable {
    case aggregate([ComicPlatform])
    case platform(ComicPlatform)

    static var defaultAggregate: ComicSearchTarget {
        .aggregate(ComicPlatform.onlinePlatforms)
    }

    var id: String {
        switch self {
        case .aggregate(let platforms):
            "aggregate-\(Self.normalizedPlatforms(platforms).map(\.id).joined(separator: "-"))"
        case .platform(let platform):
            platform.id
        }
    }

    var title: String {
        switch self {
        case .aggregate(let platforms):
            let normalized = Self.normalizedPlatforms(platforms)
            if normalized.count == ComicPlatform.onlinePlatforms.count {
                return "多平台聚合"
            }
            return "\(normalized.count) 个平台聚合"
        case .platform(let platform):
            return platform.title
        }
    }

    var systemImage: String {
        switch self {
        case .aggregate:
            "square.grid.2x2"
        case .platform(let platform):
            platform.systemImage
        }
    }

    var accentColor: Color {
        switch self {
        case .aggregate:
            .blue
        case .platform(let platform):
            platform.accentColor
        }
    }

    var platforms: [ComicPlatform] {
        switch self {
        case .aggregate(let platforms):
            Self.normalizedPlatforms(platforms)
        case .platform(let platform):
            [platform]
        }
    }

    var isAggregate: Bool {
        if case .aggregate = self { return true }
        return false
    }

    var platformSummary: String {
        switch self {
        case .aggregate(let platforms):
            Self.normalizedPlatforms(platforms).map(\.title).joined(separator: "、")
        case .platform(let platform):
            platform.title
        }
    }

    private static func normalizedPlatforms(_ platforms: [ComicPlatform]) -> [ComicPlatform] {
        let selected = Set(platforms)
        let normalized = ComicPlatform.onlinePlatforms.filter { selected.contains($0) }
        return normalized.isEmpty ? ComicPlatform.onlinePlatforms : normalized
    }

    static func configuredDefault(defaults: UserDefaults = .standard) -> ComicSearchTarget {
        let mode = SearchDefaultTargetMode(rawValue: defaults.string(forKey: SearchSettingsKey.defaultTargetMode) ?? "") ?? .platform
        switch mode {
        case .platform:
            let platformID = defaults.string(forKey: SearchSettingsKey.defaultPlatform) ?? ComicPlatform.picacg.rawValue
            return .platform(ComicPlatform(rawValue: platformID) ?? .picacg)
        case .aggregate:
            let platformIDs = defaults.string(forKey: SearchSettingsKey.defaultAggregatePlatforms) ?? Self.defaultAggregatePlatformIDs
            let platforms = platformIDs
                .split(separator: ",")
                .compactMap { ComicPlatform(rawValue: String($0)) }
            return .aggregate(platforms)
        }
    }

    private static var defaultAggregatePlatformIDs: String {
        ComicPlatform.onlinePlatforms.map(\.rawValue).joined(separator: ",")
    }
}

struct ComicSearchPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var searchHistory: SearchHistoryService
    @AppStorage(SearchSettingsKey.focusesSearchFieldOnOpen) private var focusesSearchFieldOnOpen = false
    @AppStorage(SearchSettingsKey.enablesSearchSuggestions) private var enablesSearchSuggestions = true
    @AppStorage(SearchSettingsKey.suggestionSelectionBehavior) private var suggestionSelectionBehavior = SearchSuggestionSelectionBehavior.fill.rawValue
    @AppStorage(SearchSettingsKey.defaultTargetMode) private var defaultTargetMode = SearchDefaultTargetMode.platform.rawValue
    @AppStorage(SearchSettingsKey.defaultPlatform) private var defaultSearchPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage(SearchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = ComicPlatform.onlinePlatforms.map(\.rawValue).joined(separator: ",")
    let service: ComicContentService
    private let usesConfiguredDefaultTarget: Bool
    private let recordsInitialSearchInHistory: Bool
    private let hidesTabBar: Bool
    @StateObject private var viewModel: ComicSearchViewModel
    @State private var query: String
    @State private var selectedSearchTarget: ComicSearchTarget
    @State private var aggregatePlatforms = Set(ComicPlatform.onlinePlatforms)
    @State private var searchOptions = ComicSearchAdvancedOptions()
    @State private var showsAdvancedOptions = false
    @State private var showsSavedSearches = false
    @State private var showsVersions = false
    @State private var showsSearchProgress = false
    @State private var hiddenTagSuggestionsQuery: String?
    @State private var searchSubmitSuppressionGeneration = 0
    @State private var suppressedSearchSubmitGeneration: Int?
    @State private var searchCancelRestorationCandidate: String?
    @State private var searchClearGeneration = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var pendingHistoryRecord: SearchHistoryRecord?
    @State private var currentSearchRecordsHistory = false
    @State private var appliedHistoryTarget: ComicSearchTarget?
    @FocusState private var isSearchFocused: Bool

    init(
        initialQuery: String = "",
        platform: ComicPlatform? = nil,
        recordsInitialSearchInHistory: Bool = true,
        hidesTabBar: Bool = true,
        service: ComicContentService = ComicContentService()
    ) {
        self.service = service
        self.usesConfiguredDefaultTarget = platform == nil
        self.recordsInitialSearchInHistory = recordsInitialSearchInHistory
        self.hidesTabBar = hidesTabBar
        let initialTarget = platform.map(ComicSearchTarget.platform) ?? ComicSearchTarget.configuredDefault()
        _query = State(initialValue: initialQuery)
        _selectedSearchTarget = State(initialValue: initialTarget)
        if case .aggregate = initialTarget {
            let platforms = initialTarget.platforms
            _aggregatePlatforms = State(initialValue: Set(platforms))
        }
        _viewModel = StateObject(wrappedValue: ComicSearchViewModel(service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                if searchHistory.isEnabled, !searchHistory.records.isEmpty {
                    SearchHistoryListView(
                        records: searchHistory.records,
                        onSelect: selectHistory,
                        onDelete: searchHistory.remove
                    )
                } else {
                    ContentUnavailableView("搜索漫画", systemImage: "magnifyingglass", description: Text("输入关键词、作者或标签开始搜索"))
                }
            case .loading:
                LoadingComicListView(accentColor: selectedSearchTarget.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无结果", systemImage: "magnifyingglass", description: Text("换个关键词或平台试试"))
                } else {
                    ComicListSection(
                        comics: comics,
                        service: service,
                        isLoadingMore: viewModel.isLoadingMore,
                        hasMore: viewModel.hasMore,
                        loadMore: {
                            loadMoreTask?.cancel()
                            loadMoreTask = Task {
                                await loadMore()
                            }
                        }
                    )
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("搜索失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        startSearch(force: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.requests.isEmpty {
                Button {
                    showsSearchProgress = true
                } label: {
                    HStack {
                        if viewModel.isSearching || viewModel.isLoadingMore { ProgressView() }
                        let completed = viewModel.requests.filter {
                            if case .loaded = $0.status { return true }; return false
                        }.count
                        Text("搜索进度：\(completed)/\(viewModel.requests.count) · 查看详情")
                            .font(.footnote)
                    }.padding(8).frame(maxWidth: .infinity)
                }.background(.bar)
            }
        }
        .navigationTitle("搜索")
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar(hidesTabBar)
        .searchable(
            text: $query,
            placement: .picaxNavigationSearch,
            prompt: "搜索漫画、作者、标签"
        )
        .picaxSearchSuggestions {
            tagSuggestions
        }
        .picaxSearchFocused($isSearchFocused)
        .picaxOnChange(of: query) { oldValue, newValue in
            handleSearchQueryChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: isSearchFocused) { newValue in
            handleSearchFocusChange(isFocused: newValue)
        }
        .onSubmit(of: .search) {
            if suppressedSearchSubmitGeneration != nil {
                suppressedSearchSubmitGeneration = nil
                return
            }
            startSearch(force: true)
        }
        .onChange(of: selectedSearchTarget) { target in
            if appliedHistoryTarget == target { appliedHistoryTarget = nil; return }
            appliedHistoryTarget = nil
            guard viewModel.hasSearched else { return }
            startSearch(force: true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Menu {
                    Button("多源版本") { showsVersions = true }
                    Button("常用搜索", systemImage: "star") { showsSavedSearches = true }
                    Button("组合预览与进度", systemImage: "list.bullet.rectangle") { showsSearchProgress = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("搜索工具")

                Button {
                    showsAdvancedOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .foregroundStyle(isSearchOptionsCustomized ? selectedSearchTarget.accentColor : .primary)
                .accessibilityLabel("高级选项")

                ComicSearchTargetMenu(
                    selectedTarget: selectedSearchTarget,
                    aggregatePlatforms: aggregatePlatforms,
                    onSelectTarget: { selectedSearchTarget = $0 },
                    onToggleAggregatePlatform: toggleAggregatePlatform
                )
                .equatable()

                Button {
                    startSearch(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.trimmedKeyword(query).isEmpty)
                .accessibilityLabel("刷新")
            }
        }
        .sheet(isPresented: $showsVersions) {
            PicaxNavigationContainer {
                if case .loaded(let comics) = viewModel.state {
                    ComicVersionsView(comics: comics, service: service)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsVersions = false } } }
                } else {
                    ContentUnavailableView("先进行搜索", systemImage: "magnifyingglass")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsVersions = false } } }
                }
            }
        }
        .sheet(isPresented: $showsSavedSearches) {
            SavedSearchesSheet(current: SearchHistoryRecord(
                keyword: query, target: SearchHistoryTarget(selectedSearchTarget),
                advancedOptions: searchOptions, searchedAt: Date()
            )) { record in
                applyHistory(record, resumesFromBreakpoint: false)
            }
        }
        .sheet(isPresented: $showsSearchProgress) {
            ComicSearchProgressSheet(model: viewModel, query: query, target: selectedSearchTarget) { platform in
                searchTask?.cancel()
                searchTask = Task {
                    await viewModel.retryFailed(platform: platform, accounts: searchAccounts)
                    if currentSearchRecordsHistory {
                        searchHistory.updateBreakpoint(keyword: query, target: selectedSearchTarget, breakpoint: viewModel.breakpoint)
                    }
                }
            }
        }
        .sheet(isPresented: $showsAdvancedOptions) {
            ComicSearchAdvancedOptionsSheet(target: selectedSearchTarget, options: $searchOptions) {
                guard viewModel.hasSearched else { return }
                startSearch(force: true)
            }
        }
        .confirmationDialog(
            "继续上次搜索？",
            isPresented: Binding(
                get: { pendingHistoryRecord != nil },
                set: { if !$0 { pendingHistoryRecord = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingHistoryRecord
        ) { record in
            Button("从断点继续") {
                applyHistory(record, resumesFromBreakpoint: true)
            }
            Button("重新搜索") {
                applyHistory(record, resumesFromBreakpoint: false)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("断点续搜会从各搜索组合、各平台上次加载位置的下一页开始。")
        }
        .task {
            applyConfiguredDefaultTargetIfNeeded()
            if focusesSearchFieldOnOpen, viewModel.trimmedKeyword(query).isEmpty {
                isSearchFocused = true
            }
            guard !viewModel.hasSearched, !viewModel.trimmedKeyword(query).isEmpty else { return }
            await search(force: true, recordsHistory: recordsInitialSearchInHistory)
        }
        .onDisappear {
            searchTask?.cancel()
            loadMoreTask?.cancel()
            viewModel.cancelCurrentSearch()
        }
    }

    private func search(
        force: Bool = false,
        recordsHistory: Bool = true,
        resumeFrom breakpoint: ComicSearchBreakpoint? = nil
    ) async {
        let trimmedKeyword = viewModel.trimmedKeyword(query)
        guard !trimmedKeyword.isEmpty else { return }
        let target = selectedSearchTarget
        let options = searchOptions
        let accounts = searchAccounts
        query = trimmedKeyword
        hiddenTagSuggestionsQuery = trimmedKeyword
        isSearchFocused = false
        currentSearchRecordsHistory = recordsHistory
        if recordsHistory {
            searchHistory.record(
                keyword: trimmedKeyword,
                target: target,
                advancedOptions: options,
                breakpoint: breakpoint
            )
        }
        await viewModel.search(
            target: target,
            keyword: trimmedKeyword,
            accounts: accounts,
            options: options,
            resumeFrom: breakpoint,
            force: force
        )
        guard !Task.isCancelled, recordsHistory else { return }
        searchHistory.updateBreakpoint(
            keyword: trimmedKeyword,
            target: target,
            breakpoint: viewModel.breakpoint
        )
    }

    private func loadMore() async {
        let keyword = query
        let target = selectedSearchTarget
        await viewModel.loadMore(accounts: searchAccounts)
        guard !Task.isCancelled, currentSearchRecordsHistory else { return }
        searchHistory.updateBreakpoint(
            keyword: keyword,
            target: target,
            breakpoint: viewModel.breakpoint
        )
    }

    private func startSearch(
        force: Bool,
        recordsHistory: Bool = true,
        resumeFrom breakpoint: ComicSearchBreakpoint? = nil
    ) {
        searchTask?.cancel()
        loadMoreTask?.cancel()
        searchTask = Task {
            await search(
                force: force,
                recordsHistory: recordsHistory,
                resumeFrom: breakpoint
            )
        }
    }

    private func handleSearchQueryChange(oldValue: String, newValue: String) {
        if hiddenTagSuggestionsQuery != nil, newValue != hiddenTagSuggestionsQuery {
            hiddenTagSuggestionsQuery = nil
        }

        if newValue.isEmpty, !oldValue.isEmpty {
            searchTask?.cancel()
            loadMoreTask?.cancel()
            viewModel.cancelCurrentSearch()
            searchCancelRestorationCandidate = oldValue
            searchClearGeneration += 1
            let generation = searchClearGeneration

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard searchClearGeneration == generation else { return }

                if !query.isEmpty {
                    searchCancelRestorationCandidate = nil
                } else if !isSearchFocused {
                    restoreQueryClearedBySearchCancel(generation: generation)
                } else {
                    searchCancelRestorationCandidate = nil
                }
            }
        } else if !newValue.isEmpty {
            searchCancelRestorationCandidate = nil
            searchClearGeneration += 1
        }
    }

    private func handleSearchFocusChange(isFocused: Bool) {
        guard !isFocused, query.isEmpty else { return }
        restoreQueryClearedBySearchCancel(generation: searchClearGeneration)
    }

    private func restoreQueryClearedBySearchCancel(generation: Int) {
        guard searchClearGeneration == generation,
              let candidate = searchCancelRestorationCandidate,
              query.isEmpty else {
            searchCancelRestorationCandidate = nil
            return
        }

        searchCancelRestorationCandidate = nil
        searchClearGeneration += 1
        query = candidate
    }

    private var searchAccounts: [ComicPlatform: PlatformAccount] {
        Dictionary(uniqueKeysWithValues: ComicPlatform.onlinePlatforms.compactMap { platform in
            platformAccounts.account(for: platform).map { (platform, $0) }
        })
    }

    private var isSearchOptionsCustomized: Bool {
        selectedSearchTarget.platforms.contains { searchOptions.isCustomized(for: $0) }
    }

    private var configuredDefaultSearchTarget: ComicSearchTarget {
        switch SearchDefaultTargetMode(rawValue: defaultTargetMode) ?? .platform {
        case .platform:
            .platform(ComicPlatform(rawValue: defaultSearchPlatformID) ?? .picacg)
        case .aggregate:
            .aggregate(
                defaultAggregatePlatformIDs
                    .split(separator: ",")
                    .compactMap { ComicPlatform(rawValue: String($0)) }
            )
        }
    }

    private func applyConfiguredDefaultTargetIfNeeded() {
        guard usesConfiguredDefaultTarget, !viewModel.hasSearched else { return }
        let target = configuredDefaultSearchTarget
        selectedSearchTarget = target
        if case .aggregate = target {
            let platforms = target.platforms
            aggregatePlatforms = Set(platforms)
        }
    }

    private func toggleAggregatePlatform(_ platform: ComicPlatform) {
        var nextPlatforms = aggregatePlatforms
        if nextPlatforms.contains(platform) {
            guard nextPlatforms.count > 1 else { return }
            nextPlatforms.remove(platform)
        } else {
            nextPlatforms.insert(platform)
        }

        aggregatePlatforms = nextPlatforms
        selectedSearchTarget = .aggregate(ComicPlatform.onlinePlatforms.filter { nextPlatforms.contains($0) })
    }

    private func selectHistory(_ record: SearchHistoryRecord) {
        if record.resumableBreakpoint != nil {
            pendingHistoryRecord = record
        } else {
            applyHistory(record, resumesFromBreakpoint: false)
        }
    }

    private func applyHistory(_ record: SearchHistoryRecord, resumesFromBreakpoint: Bool) {
        pendingHistoryRecord = nil
        query = record.keyword
        if selectedSearchTarget != record.target.searchTarget { appliedHistoryTarget = record.target.searchTarget }
        selectedSearchTarget = record.target.searchTarget
        searchOptions = record.advancedOptions
        if let aggregatePlatformSet = record.target.aggregatePlatformSet {
            aggregatePlatforms = aggregatePlatformSet
        }
        startSearch(
            force: true,
            resumeFrom: resumesFromBreakpoint ? record.resumableBreakpoint : nil
        )
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        if hiddenTagSuggestionsQuery != query,
           enablesSearchSuggestions,
           selectedSearchTarget == .platform(.eHentai) {
            let suggestions = EhTagTranslationService.suggestions(for: query.currentSearchOperand)
            if !suggestions.isEmpty {
                Section("E-Hentai 标签") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            applyTagSuggestion(
                                query: suggestion.query,
                                tag: suggestion.tag,
                                translatedTitle: suggestion.translatedTitle
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.query)
                                Text("\(suggestion.displayTitle) · \(suggestion.namespaceTitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else if hiddenTagSuggestionsQuery != query,
                  enablesSearchSuggestions,
                  selectedSearchTarget == .platform(.nhentai) {
            let suggestions = NhentaiTagSuggestionService.suggestions(for: query.currentSearchOperand)
            if !suggestions.isEmpty {
                Section("NHentai 标签") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            applyTagSuggestion(
                                query: suggestion.query,
                                tag: suggestion.tag,
                                translatedTitle: suggestion.translatedTitle
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.query)
                                Text("\(suggestion.displayTitle) · \(suggestion.groupTitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyTagSuggestion(query suggestionQuery: String, tag: String, translatedTitle: String) {
        switch selectedSuggestionSelectionBehavior {
        case .fill:
            searchSubmitSuppressionGeneration += 1
            let suppressionGeneration = searchSubmitSuppressionGeneration
            suppressedSearchSubmitGeneration = suppressionGeneration
            query = query.replacingLastSearchFragment(
                with: "\(suggestionQuery) ",
                suggestionTag: tag,
                translatedTitle: translatedTitle
            )
            Task { @MainActor in
                await Task.yield()
                isSearchFocused = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                if suppressedSearchSubmitGeneration == suppressionGeneration {
                    suppressedSearchSubmitGeneration = nil
                }
            }
        case .search:
            query = query.replacingLastSearchFragment(
                with: suggestionQuery,
                suggestionTag: tag,
                translatedTitle: translatedTitle
            )
            isSearchFocused = false
            Task {
                await search(force: true)
            }
        }
    }

    private var selectedSuggestionSelectionBehavior: SearchSuggestionSelectionBehavior {
        SearchSuggestionSelectionBehavior(rawValue: suggestionSelectionBehavior) ?? .fill
    }
}

private struct ComicSearchTargetMenu: View, Equatable {
    let selectedTarget: ComicSearchTarget
    let aggregatePlatforms: Set<ComicPlatform>
    let onSelectTarget: (ComicSearchTarget) -> Void
    let onToggleAggregatePlatform: (ComicPlatform) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedTarget == rhs.selectedTarget
            && lhs.aggregatePlatforms == rhs.aggregatePlatforms
    }

    var body: some View {
        Menu {
            Section("聚合搜索") {
                Button {
                    onSelectTarget(aggregateSearchTarget)
                } label: {
                    if selectedTarget.isAggregate {
                        Label(aggregateSearchTarget.title, systemImage: "checkmark")
                    } else {
                        Label(aggregateSearchTarget.title, systemImage: aggregateSearchTarget.systemImage)
                    }
                }

                ForEach(ComicPlatform.onlinePlatforms) { platform in
                    Button {
                        onToggleAggregatePlatform(platform)
                    } label: {
                        Label(
                            platform.title,
                            systemImage: aggregatePlatforms.contains(platform) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }

            Divider()

            Section("单平台") {
                ForEach(ComicPlatform.onlinePlatforms) { platform in
                    let target = ComicSearchTarget.platform(platform)
                    Button {
                        onSelectTarget(target)
                    } label: {
                        if selectedTarget == target {
                            Label(platform.title, systemImage: "checkmark")
                        } else {
                            Label(platform.title, systemImage: platform.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedTarget.systemImage)
        }
        .accessibilityLabel("搜索选项")
    }

    private var aggregateSearchTarget: ComicSearchTarget {
        .aggregate(ComicPlatform.onlinePlatforms.filter { aggregatePlatforms.contains($0) })
    }
}

private extension String {
    var currentSearchOperand: String {
        String(self[ComicSearchExpressionTokenizer.currentOperandRange(in: self)])
    }

    func replacingLastSearchFragment(with replacement: String, suggestionTag: String, translatedTitle: String) -> String {
        let range = ComicSearchExpressionTokenizer.currentOperandRange(in: self)
        let prefix = String(self[..<range.lowerBound])
        let operand = String(self[range])
        return prefix + operand.replacingLastOperandFragment(
            with: replacement,
            suggestionTag: suggestionTag,
            translatedTitle: translatedTitle
        ) + self[range.upperBound...]
    }

    private func replacingLastOperandFragment(with replacement: String, suggestionTag: String, translatedTitle: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return replacement }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let wordsToRemove = matchedTrailingWordCount(
            words: words,
            suggestionTag: suggestionTag,
            translatedTitle: translatedTitle
        )
        var prefixEnd = trimmed.endIndex

        for _ in 0..<wordsToRemove {
            while prefixEnd > trimmed.startIndex, trimmed[trimmed.index(before: prefixEnd)].isWhitespace {
                prefixEnd = trimmed.index(before: prefixEnd)
            }
            while prefixEnd > trimmed.startIndex, !trimmed[trimmed.index(before: prefixEnd)].isWhitespace {
                prefixEnd = trimmed.index(before: prefixEnd)
            }
        }

        let prefix = String(trimmed[..<prefixEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? replacement : "\(prefix) \(replacement)"
    }

    private func matchedTrailingWordCount(words: [String], suggestionTag: String, translatedTitle: String) -> Int {
        let maxWordCount = min(words.count, max(suggestionTag.split(separator: " ").count, 1))
        let normalizedTag = suggestionTag.lowercased()
        let normalizedTranslation = translatedTitle.lowercased()

        for count in stride(from: maxWordCount, through: 1, by: -1) {
            let fragment = words.suffix(count).joined(separator: " ").lowercased()
            let comparableFragment = fragment.suggestionComparableFragment
            guard !comparableFragment.isEmpty else { continue }
            if normalizedTag.hasPrefix(comparableFragment) || normalizedTranslation.hasPrefix(comparableFragment) {
                return count
            }
        }
        return 1
    }

    private var suggestionComparableFragment: String {
        guard let separatorIndex = lastIndex(of: ":") else { return self }
        return String(self[index(after: separatorIndex)...])
    }
}

private struct SearchHistoryListView: View {
    let records: [SearchHistoryRecord]
    let onSelect: (SearchHistoryRecord) -> Void
    let onDelete: (SearchHistoryRecord) -> Void

    var body: some View {
        List {
            Section("搜索历史") {
                ForEach(records) { record in
                    Button {
                        onSelect(record)
                    } label: {
                        SearchHistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
    }
}

private struct SearchHistoryRow: View {
    let record: SearchHistoryRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.keyword)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(record.subtitle) · \(record.searchedAtText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: record.target.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 4)
    }
}

private struct ComicSearchAdvancedOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: ComicSearchTarget
    @Binding var options: ComicSearchAdvancedOptions
    let onApply: () -> Void

    var body: some View {
        PicaxNavigationContainer {
            Form {
                if configurablePlatforms.isEmpty {
                    ContentUnavailableView("暂无高级选项", systemImage: "slider.horizontal.3", description: Text("\(target.title) 当前没有可用的搜索筛选项"))
                } else {
                    if target.isAggregate {
                        Section {
                            Text("聚合搜索会使用已选平台各自的搜索选项，并把结果合并展示。当前平台：\(target.platformSummary)。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(configurablePlatforms) { platform in
                        searchOptionsSection(for: platform)
                    }
                }
            }
            .navigationTitle("高级选项")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        resetTargetPlatforms()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }

    private var configurablePlatforms: [ComicPlatform] {
        target.platforms.filter { !$0.searchSortChoices.isEmpty || $0.supportsSearchLanguageFilter }
    }

    private func searchOptionsSection(for platform: ComicPlatform) -> some View {
        Section {
            if !platform.searchSortChoices.isEmpty {
                Picker(selection: sortSelection(for: platform)) {
                    ForEach(platform.searchSortChoices) { choice in
                        Text(choice.title).tag(choice.value)
                    }
                } label: {
                    Label("排序方式", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
            }

            if platform.supportsSearchLanguageFilter {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("语言筛选", systemImage: "globe")
                            .font(.subheadline.weight(.semibold))

                        Text("仅筛选 \(platform.title) 的搜索结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("语言筛选", selection: languageSelection(for: platform)) {
                        Text("不限").tag(ComicSearchLanguage?.none)
                        ForEach(ComicSearchLanguage.allCases) { language in
                            Text(language.title).tag(Optional(language))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("\(platform.title) 搜索选项", systemImage: platform.systemImage)
                .foregroundStyle(platform.accentColor)
        }
    }

    private func languageSelection(for platform: ComicPlatform) -> Binding<ComicSearchLanguage?> {
        Binding {
            options.language(for: platform)
        } set: { language in
            options.setLanguage(language, for: platform)
        }
    }

    private func sortSelection(for platform: ComicPlatform) -> Binding<String> {
        Binding {
            options.sortValue(for: platform)
        } set: { value in
            options.setSortValue(value, for: platform)
        }
    }

    private func resetTargetPlatforms() {
        for platform in target.platforms {
            reset(platform)
        }
    }

    private func reset(_ platform: ComicPlatform) {
        switch platform {
        case .picacg:
            options.picacgSort = "dd"
        case .nhentai:
            options.nhentaiSort = "date"
            options.nhentaiLanguage = nil
        case .jmComic:
            options.jmComicSort = "mr"
        case .eHentai:
            options.ehentaiLanguage = nil
        case .htManga, .hitomi, .local:
            break
        }
    }
}

struct ComicTagComicsPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    let tag: ComicTagReference
    let service: ComicContentService
    @StateObject private var viewModel: ComicTagComicsViewModel

    init(tag: ComicTagReference, service: ComicContentService = ComicContentService()) {
        self.tag = tag
        self.service = service
        _viewModel = StateObject(wrappedValue: ComicTagComicsViewModel(tag: tag, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingComicListView(accentColor: tag.platform.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无漫画", systemImage: "tag", description: Text("这个标签没有返回漫画"))
                } else {
                    ComicListSection(
                        comics: comics,
                        service: service,
                        isLoadingMore: viewModel.isLoadingMore,
                        hasMore: viewModel.hasMore,
                        loadMore: {
                            Task {
                                await loadMore()
                            }
                        }
                    )
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await load(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(tag.displayTitle)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .picaxTopBarTrailing) {
                Button {
                    Task {
                        await load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await load()
        }
    }

    private func load(force: Bool = false) async {
        await viewModel.load(account: platformAccounts.account(for: tag.platform), force: force)
    }

    private func loadMore() async {
        await viewModel.loadMore(account: platformAccounts.account(for: tag.platform))
    }
}

@MainActor
private final class ComicTagComicsViewModel: ObservableObject {
    @Published private(set) var state: ComicTagComicsLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false

    private let tag: ComicTagReference
    private let service: ComicContentService
    private var currentPage = 0
    private var loadedIDs = Set<String>()

    init(tag: ComicTagReference, service: ComicContentService) {
        self.tag = tag
        self.service = service
    }

    func load(account: PlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force {
            return
        }

        state = .loading
        currentPage = 0
        loadedIDs.removeAll()
        hasMore = false
        isLoadingMore = false
        do {
            let comics = try await service.loadTagComics(tag: tag, account: account, page: 1)
            let nextLoadedIDs = try await ComicListBackgroundProcessing.loadedIDs(from: comics, identity: .id)
            currentPage = 1
            loadedIDs = nextLoadedIDs
            hasMore = !comics.isEmpty
            state = .loaded(comics)
        } catch where error.isTaskCancellation {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore(account: PlatformAccount?) async {
        guard hasMore, !isLoadingMore, case .loaded(let comics) = state else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let newComics = try await service.loadTagComics(tag: tag, account: account, page: nextPage)
            let uniqueResult = try await ComicListBackgroundProcessing.uniqueItems(
                from: newComics,
                loadedIDs: loadedIDs,
                identity: .id
            )
            currentPage = nextPage
            loadedIDs = uniqueResult.loadedIDs
            hasMore = !newComics.isEmpty && !uniqueResult.items.isEmpty
            guard !uniqueResult.items.isEmpty else { return }
            state = .loaded(comics + uniqueResult.items)
        } catch where error.isTaskCancellation {
            return
        } catch {
            hasMore = false
        }
    }
}

private enum ComicTagComicsLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

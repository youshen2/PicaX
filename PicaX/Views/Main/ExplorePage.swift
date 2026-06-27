import Combine
import SwiftUI

struct ExplorePage: View {
    @AppStorage("settings.explore.defaultPlatform") private var defaultPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage("settings.explore.rememberSelectedPlatform") private var rememberSelectedPlatform = true
    @AppStorage("settings.explore.lastSelectedPlatform") private var lastSelectedPlatformID = ComicPlatform.picacg.rawValue
    @State private var selectedPlatform: ComicPlatform = .picacg
    @State private var didInitializePlatform = false

    var body: some View {
        List {
            Section {
                Picker("平台", selection: $selectedPlatform) {
                    ForEach(ComicPlatform.allCases) { platform in
                        Label(platform.title, systemImage: platform.systemImage)
                            .tag(platform)
                    }
                }
                .picaxPlatformPickerStyle()
            } header: {
                Text("平台")
            }

            Section("发现") {
                ForEach(availableEntries) { entry in
                    NavigationLink {
                        ExploreEntryPage(platform: selectedPlatform, entry: entry)
                    } label: {
                        ExploreEntryRow(entry: entry, accentColor: selectedPlatform.accentColor)
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .onAppear {
            guard !didInitializePlatform else { return }
            selectedPlatform = initialPlatform
            didInitializePlatform = true
        }
        .onChange(of: selectedPlatform) { _, newValue in
            if rememberSelectedPlatform {
                lastSelectedPlatformID = newValue.rawValue
            }
        }
        .onChange(of: rememberSelectedPlatform) { _, newValue in
            if newValue {
                lastSelectedPlatformID = selectedPlatform.rawValue
            } else {
                selectedPlatform = defaultPlatform
            }
        }
        .onChange(of: defaultPlatformID) { _, _ in
            if !rememberSelectedPlatform {
                selectedPlatform = defaultPlatform
            }
        }
    }

    private var availableEntries: [ComicExploreEntry] {
        ComicExploreEntry.availableEntries(for: selectedPlatform)
    }

    private var initialPlatform: ComicPlatform {
        if rememberSelectedPlatform,
           let platform = ComicPlatform(rawValue: lastSelectedPlatformID) {
            return platform
        }
        return defaultPlatform
    }

    private var defaultPlatform: ComicPlatform {
        ComicPlatform(rawValue: defaultPlatformID) ?? .picacg
    }
}

private struct ExploreEntryRow: View {
    let entry: ComicExploreEntry
    let accentColor: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                Text(entry.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entry.systemImage)
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
        }
        .padding(.vertical, 4)
    }
}

private struct ExploreEntryPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    let platform: ComicPlatform
    let entry: ComicExploreEntry
    private let service: ComicContentService
    @StateObject private var viewModel: ExploreEntryViewModel

    init(platform: ComicPlatform, entry: ComicExploreEntry, service: ComicContentService = ComicContentService()) {
        self.platform = platform
        self.entry = entry
        self.service = service
        _viewModel = StateObject(wrappedValue: ExploreEntryViewModel(platform: platform, entry: entry, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingComicListView(accentColor: platform.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无漫画", systemImage: entry.systemImage, description: Text("接口返回为空"))
                } else {
                    comicList(comics)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task {
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(entry.title)
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
        await viewModel.load(account: platformAccounts.account(for: platform), force: force)
    }

    private func loadMore() async {
        await viewModel.loadMore(account: platformAccounts.account(for: platform))
    }

    private func comicList(_ comics: [ComicListItem]) -> some View {
        ComicListSection(
            comics: comics,
            service: service,
            isLoadingMore: viewModel.isLoadingMore,
            hasMore: viewModel.hasMore
        ) {
            Task {
                await loadMore()
            }
        }
        .refreshable {
            await load(force: true)
        }
    }
}

@MainActor
private final class ExploreEntryViewModel: ObservableObject {
    @Published private(set) var state: ExploreLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false

    private let platform: ComicPlatform
    private let entry: ComicExploreEntry
    private let service: ComicContentService
    private var currentPage = 0
    private var loadedIDs = Set<String>()

    init(platform: ComicPlatform, entry: ComicExploreEntry, service: ComicContentService = ComicContentService()) {
        self.platform = platform
        self.entry = entry
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
            let items = try await service.loadExplore(platform: platform, entry: entry, account: account, page: 1)
            currentPage = 1
            loadedIDs = Set(items.map(\.id))
            hasMore = !items.isEmpty
            state = .loaded(items)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore(account: PlatformAccount?) async {
        guard hasMore, !isLoadingMore, case .loaded(let items) = state else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let newItems = try await service.loadExplore(platform: platform, entry: entry, account: account, page: nextPage)
            currentPage = nextPage
            let uniqueItems = newItems.filter { loadedIDs.insert($0.id).inserted }
            hasMore = !newItems.isEmpty && !uniqueItems.isEmpty
            guard !uniqueItems.isEmpty else { return }
            state = .loaded(items + uniqueItems)
        } catch {
            hasMore = false
        }
    }
}

private enum ExploreLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

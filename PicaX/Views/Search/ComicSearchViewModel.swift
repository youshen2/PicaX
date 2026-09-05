import Combine
import Foundation

nonisolated struct ComicSearchRequestProgress: Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case queued, loading, loaded(Int), failed(String)
    }
    let clause: ComicSearchClause
    let platform: ComicPlatform
    var page: Int
    var status: Status = .queued
    var id: String { "\(platform.id):\(clause.breakpointKey)" }
}

@MainActor
final class ComicSearchViewModel: ObservableObject {
    @Published private(set) var state: ComicSearchLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSearching = false
    @Published private(set) var hasMore = false
    @Published private(set) var hasSearched = false
    @Published private(set) var requests: [ComicSearchRequestProgress] = []

    private let service: ComicContentService
    private var currentPages: [String: Int] = [:]
    private var requestHasMore: [String: Bool] = [:]
    private var loadedIDs = Set<String>()
    private var comics: [ComicListItem] = []
    private var currentTarget: ComicSearchTarget?
    private var currentKeyword = ""
    private var currentOptions = ComicSearchAdvancedOptions()
    private var requestGeneration = 0

    init(service: ComicContentService) { self.service = service }

    func trimmedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var breakpoint: ComicSearchBreakpoint? {
        let pending = requests.compactMap { request -> ComicSearchBreakpoint.Request? in
            guard requestHasMore[request.id] == true else { return nil }
            return .init(keyword: request.clause.breakpointKey, platform: request.platform,
                         nextPage: (currentPages[request.id] ?? 0) + 1)
        }
        return pending.isEmpty ? nil : ComicSearchBreakpoint(requests: pending)
    }

    func search(
        target: ComicSearchTarget,
        keyword: String,
        accounts: [ComicPlatform: PlatformAccount],
        options: ComicSearchAdvancedOptions,
        resumeFrom breakpoint: ComicSearchBreakpoint? = nil,
        force: Bool = false
    ) async {
        let trimmed = trimmedKeyword(keyword)
        let clauses: [ComicSearchClause]
        do {
            clauses = try ComicSearchExpressionParser.clauses(from: trimmed)
        } catch {
            reset()
            hasSearched = true
            state = .failed(error.localizedDescription)
            return
        }
        guard !clauses.isEmpty else { reset(); return }
        if case .loaded = state, !force, breakpoint == nil,
           currentTarget == target, currentKeyword == trimmed, currentOptions == options { return }
        reset()
        hasSearched = true
        currentTarget = target
        currentKeyword = trimmed
        currentOptions = options
        requests = clauses.flatMap { clause in
            target.platforms.map { .init(clause: clause, platform: $0, page: 1) }
        }
        if let breakpoint {
            let resumed = requests.compactMap { request -> ComicSearchRequestProgress? in
                let page = breakpoint.requests.filter {
                    $0.keyword == request.clause.breakpointKey && $0.platform == request.platform
                }.map(\.nextPage).max()
                guard let page, page > 0 else { return nil }
                var request = request
                request.page = page
                return request
            }
            if !resumed.isEmpty { requests = resumed }
        }
        for request in requests {
            currentPages[request.id] = request.page - 1
            requestHasMore[request.id] = true
        }
        state = .loading
        await execute(indices: Array(requests.indices), accounts: accounts, loadingMore: false)
    }

    func loadMore(accounts: [ComicPlatform: PlatformAccount]) async {
        guard hasMore, !isSearching, !isLoadingMore else { return }
        let indices = requests.indices.filter {
            guard case .loaded = requests[$0].status else { return false }
            return requestHasMore[requests[$0].id] == true
        }
        for index in indices {
            requests[index].page = (currentPages[requests[index].id] ?? 0) + 1
        }
        await execute(indices: indices, accounts: accounts, loadingMore: true)
    }

    func retryFailed(platform: ComicPlatform? = nil, accounts: [ComicPlatform: PlatformAccount]) async {
        guard !isSearching, !isLoadingMore else { return }
        let indices = requests.indices.filter {
            guard case .failed = requests[$0].status else { return false }
            return platform == nil || requests[$0].platform == platform
        }
        await execute(indices: indices, accounts: accounts, loadingMore: !comics.isEmpty)
    }

    private func execute(indices: [Int], accounts: [ComicPlatform: PlatformAccount], loadingMore: Bool) async {
        guard !indices.isEmpty else { return }
        let generation = requestGeneration
        let options = currentOptions
        let service = service
        isSearching = !loadingMore
        isLoadingMore = loadingMore
        for index in indices { requests[index].status = .queued }
        defer {
            if generation == requestGeneration {
                isSearching = false
                isLoadingMore = false
                hasMore = requests.contains {
                    if case .loaded = $0.status { return requestHasMore[$0.id] == true }
                    return false
                }
            }
        }
        // Bound the request fan-out even when parentheses expand to many combinations.
        await withTaskGroup(of: SearchResponse.self) { group in
            var next = 0
            @MainActor func enqueueNext() {
                guard next < indices.count, !Task.isCancelled, generation == requestGeneration else { return }
                let index = indices[next]
                next += 1
                requests[index].status = .loading
                let request = requests[index]
                group.addTask {
                    do {
                        let items = try await service.searchComics(
                            platform: request.platform, query: request.clause,
                            account: accounts[request.platform], page: request.page, options: options
                        )
                        return SearchResponse(index: index, items: items, error: nil)
                    } catch {
                        return SearchResponse(index: index, items: nil,
                                              error: error.isTaskCancellation ? "搜索已取消" : error.localizedDescription)
                    }
                }
            }
            for _ in 0..<min(6, indices.count) { enqueueNext() }
            for await response in group {
                guard generation == requestGeneration, !Task.isCancelled else { group.cancelAll(); return }
                let index = response.index
                let request = requests[index]
                if let items = response.items {
                    currentPages[request.id] = request.page
                    requestHasMore[request.id] = !items.isEmpty
                    requests[index].status = .loaded(items.count)
                    for item in items where loadedIDs.insert(item.readingHistoryID).inserted {
                        comics.append(item)
                    }
                    state = .loaded(comics)
                } else {
                    requests[index].status = .failed(response.error ?? "搜索失败")
                }
                enqueueNext()
            }
        }
        guard generation == requestGeneration, !Task.isCancelled else { return }
        if !comics.isEmpty || requests.contains(where: { if case .loaded = $0.status { return true }; return false }) {
            state = .loaded(comics)
        } else {
            state = .failed("请求未完成，可在搜索进度中按平台重试。")
        }
    }

    func cancelCurrentSearch() {
        requestGeneration &+= 1
        isSearching = false
        isLoadingMore = false
        for index in requests.indices {
            switch requests[index].status {
            case .queued, .loading: requests[index].status = .failed("搜索已取消")
            default: break
            }
        }
        if case .loading = state { state = .loaded(comics) }
    }

    private func reset() {
        cancelCurrentSearch()
        state = .idle
        hasSearched = false
        hasMore = false
        currentPages.removeAll()
        requestHasMore.removeAll()
        loadedIDs.removeAll()
        comics.removeAll()
        requests.removeAll()
        currentTarget = nil
        currentKeyword = ""
        currentOptions = ComicSearchAdvancedOptions()
    }
}

private nonisolated struct SearchResponse: Sendable {
    let index: Int
    let items: [ComicListItem]?
    let error: String?
}

enum ComicSearchLoadState {
    case idle, loading
    case loaded([ComicListItem])
    case failed(String)
}

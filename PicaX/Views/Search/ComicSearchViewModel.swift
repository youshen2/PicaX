import Combine
import Foundation

@MainActor
final class ComicSearchViewModel: ObservableObject {
    @Published private(set) var state: ComicSearchLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var hasSearched = false

    private let service: ComicContentService
    private var currentPages: [ComicSearchRequestKey: Int] = [:]
    private var requestHasMore: [ComicSearchRequestKey: Bool] = [:]
    private var loadedIDs = Set<String>()
    private var currentTarget: ComicSearchTarget?
    private var currentKeyword = ""
    private var currentClauses: [ComicSearchClause] = []
    private var currentOptions = ComicSearchAdvancedOptions()
    private var requestGeneration = 0

    init(service: ComicContentService) {
        self.service = service
    }

    func trimmedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var breakpoint: ComicSearchBreakpoint? {
        guard let target = currentTarget else { return nil }
        let requests = currentClauses.flatMap { clause in
            target.platforms.compactMap { platform -> ComicSearchBreakpoint.Request? in
                let key = ComicSearchRequestKey(keyword: clause.breakpointKey, platform: platform)
                guard requestHasMore[key] == true else { return nil }
                return ComicSearchBreakpoint.Request(
                    keyword: clause.breakpointKey,
                    platform: platform,
                    nextPage: (currentPages[key] ?? 0) + 1
                )
            }
        }
        return requests.isEmpty ? nil : ComicSearchBreakpoint(requests: requests)
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
        let clauses = ComicSearchExpressionParser.clauses(from: trimmed)
        guard !clauses.isEmpty else {
            reset()
            return
        }
        if case .loaded = state,
           !force,
           breakpoint == nil,
           currentTarget == target,
           currentKeyword == trimmed,
           currentOptions == options {
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        state = .loading
        hasSearched = true
        hasMore = false
        isLoadingMore = false
        currentPages.removeAll()
        requestHasMore.removeAll()
        loadedIDs.removeAll()
        currentTarget = target
        currentKeyword = trimmed
        currentClauses = clauses
        currentOptions = options

        var comics: [ComicListItem] = []
        var failures: [String] = []
        var requestCount = 0
        let validRequestKeys = Set(clauses.flatMap { clause in
            target.platforms.map {
                ComicSearchRequestKey(keyword: clause.breakpointKey, platform: $0)
            }
        })
        let resumePages: [ComicSearchRequestKey: Int]? = breakpoint.flatMap { breakpoint in
            let pages = Dictionary(
                breakpoint.requests.compactMap { request -> (ComicSearchRequestKey, Int)? in
                    let key = ComicSearchRequestKey(keyword: request.keyword, platform: request.platform)
                    return validRequestKeys.contains(key) ? (key, request.nextPage) : nil
                },
                uniquingKeysWith: max
            )
            return pages.isEmpty ? nil : pages
        }

        for clause in clauses {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            let requestKeyword = clause.breakpointKey

            let platforms = target.platforms.filter { platform in
                guard let resumePages else { return true }
                return resumePages[ComicSearchRequestKey(keyword: requestKeyword, platform: platform)] != nil
            }
            guard !platforms.isEmpty else { continue }
            let pages = Dictionary(uniqueKeysWithValues: platforms.map { platform in
                let key = ComicSearchRequestKey(keyword: requestKeyword, platform: platform)
                return (platform, resumePages?[key] ?? 1)
            })
            requestCount += platforms.count
            for platform in platforms {
                let key = ComicSearchRequestKey(keyword: requestKeyword, platform: platform)
                currentPages[key] = (pages[platform] ?? 1) - 1
                requestHasMore[key] = true
            }

            let responses = await fetchSearchPages(
                platforms: platforms,
                clause: clause,
                accounts: accounts,
                pages: pages,
                options: options
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }

            var groupsByPlatform: [ComicPlatform: [ComicListItem]] = [:]
            for response in responses {
                let key = ComicSearchRequestKey(keyword: requestKeyword, platform: response.platform)
                if let items = response.items {
                    currentPages[key] = pages[response.platform]
                    requestHasMore[key] = !items.isEmpty
                    groupsByPlatform[response.platform] = items
                } else if let message = response.errorMessage {
                    failures.append(failureMessage(keyword: clause.displayKeyword, platform: response.platform, message: message))
                }
            }

            let groups = platforms.compactMap { groupsByPlatform[$0] }
            let uniqueResult: ComicListUniqueResult
            do {
                uniqueResult = try await ComicListBackgroundProcessing.interleavedUniqueItems(
                    from: groups,
                    loadedIDs: loadedIDs,
                    identity: .platformAndID
                )
            } catch where error.isTaskCancellation {
                return
            } catch {
                uniqueResult = ComicListUniqueResult(items: [], loadedIDs: loadedIDs)
            }
            guard generation == requestGeneration, !Task.isCancelled else { return }
            loadedIDs = uniqueResult.loadedIDs
            comics.append(contentsOf: uniqueResult.items)
        }

        hasMore = requestHasMore.values.contains(true)
        if !comics.isEmpty || failures.count < requestCount {
            state = .loaded(comics)
        } else {
            state = .failed(failures.joined(separator: "\n"))
        }
    }

    func loadMore(accounts: [ComicPlatform: PlatformAccount]) async {
        guard hasMore,
              !isLoadingMore,
              case .loaded(let comics) = state,
              let target = currentTarget,
              !currentClauses.isEmpty else {
            return
        }

        let generation = requestGeneration
        let options = currentOptions
        var newComics: [ComicListItem] = []

        isLoadingMore = true
        defer {
            if generation == requestGeneration {
                isLoadingMore = false
            }
        }

        for clause in currentClauses {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            let requestKeyword = clause.breakpointKey

            let platforms = target.platforms.filter { platform in
                requestHasMore[ComicSearchRequestKey(keyword: requestKeyword, platform: platform)] == true
            }
            guard !platforms.isEmpty else { continue }

            let pages = Dictionary(uniqueKeysWithValues: platforms.map { platform in
                let key = ComicSearchRequestKey(keyword: requestKeyword, platform: platform)
                return (platform, (currentPages[key] ?? 0) + 1)
            })
            let responses = await fetchSearchPages(
                platforms: platforms,
                clause: clause,
                accounts: accounts,
                pages: pages,
                options: options
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }

            var groupsByPlatform: [ComicPlatform: [ComicListItem]] = [:]
            for response in responses {
                let key = ComicSearchRequestKey(keyword: requestKeyword, platform: response.platform)
                guard let items = response.items else {
                    continue
                }
                currentPages[key] = pages[response.platform]
                requestHasMore[key] = !items.isEmpty
                groupsByPlatform[response.platform] = items
            }

            let groups = platforms.compactMap { groupsByPlatform[$0] }
            let uniqueResult: ComicListUniqueResult
            do {
                uniqueResult = try await ComicListBackgroundProcessing.interleavedUniqueItems(
                    from: groups,
                    loadedIDs: loadedIDs,
                    identity: .platformAndID
                )
            } catch where error.isTaskCancellation {
                return
            } catch {
                uniqueResult = ComicListUniqueResult(items: [], loadedIDs: loadedIDs)
            }
            guard generation == requestGeneration, !Task.isCancelled else { return }
            loadedIDs = uniqueResult.loadedIDs
            newComics.append(contentsOf: uniqueResult.items)
        }

        hasMore = requestHasMore.values.contains(true)
        guard !newComics.isEmpty else {
            if !hasMore {
                state = .loaded(comics)
            }
            return
        }
        state = .loaded(comics + newComics)
    }

    func cancelCurrentSearch() {
        requestGeneration &+= 1
        isLoadingMore = false
    }

    private func fetchSearchPages(
        platforms: [ComicPlatform],
        clause: ComicSearchClause,
        accounts: [ComicPlatform: PlatformAccount],
        pages: [ComicPlatform: Int],
        options: ComicSearchAdvancedOptions
    ) async -> [PlatformSearchResponse] {
        let service = service
        return await withTaskGroup(of: PlatformSearchResponse.self) { group in
            for platform in platforms {
                group.addTask {
                    do {
                        let items = try await service.searchComics(
                            platform: platform,
                            query: clause,
                            account: accounts[platform],
                            page: pages[platform] ?? 1,
                            options: options
                        )
                        return PlatformSearchResponse(
                            platform: platform,
                            items: items,
                            errorMessage: nil
                        )
                    } catch {
                        return PlatformSearchResponse(
                            platform: platform,
                            items: nil,
                            errorMessage: error.isTaskCancellation ? nil : error.localizedDescription
                        )
                    }
                }
            }

            var responses: [PlatformSearchResponse] = []
            for await response in group {
                responses.append(response)
            }
            return responses
        }
    }

    private func failureMessage(keyword: String, platform: ComicPlatform, message: String) -> String {
        guard currentClauses.count > 1 else { return "\(platform.title): \(message)" }
        return "\(keyword) · \(platform.title): \(message)"
    }

    private func reset() {
        requestGeneration &+= 1
        state = .idle
        isLoadingMore = false
        hasMore = false
        currentPages.removeAll()
        requestHasMore.removeAll()
        loadedIDs.removeAll()
        currentTarget = nil
        currentKeyword = ""
        currentClauses.removeAll()
        currentOptions = ComicSearchAdvancedOptions()
    }
}

private struct ComicSearchRequestKey: Hashable, Sendable {
    let keyword: String
    let platform: ComicPlatform
}

private struct PlatformSearchResponse: Sendable {
    let platform: ComicPlatform
    let items: [ComicListItem]?
    let errorMessage: String?
}

enum ComicSearchLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

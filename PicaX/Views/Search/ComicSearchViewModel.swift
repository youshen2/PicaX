import Combine
import Foundation

enum ComicSearchKeywordSequence {
    nonisolated static func keywords(from rawKeyword: String, searchesSeparately: Bool) -> [String] {
        let trimmedKeyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return [] }
        guard searchesSeparately else { return [trimmedKeyword] }

        return trimmedKeyword
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}

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
    private var currentKeywords: [String] = []
    private var currentOptions = ComicSearchAdvancedOptions()
    private var currentSearchesKeywordsSeparately = false
    private var requestGeneration = 0

    init(service: ComicContentService) {
        self.service = service
    }

    func trimmedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var breakpoint: ComicSearchBreakpoint? {
        guard let target = currentTarget else { return nil }
        let requests = currentKeywords.flatMap { keyword in
            target.platforms.compactMap { platform -> ComicSearchBreakpoint.Request? in
                let key = ComicSearchRequestKey(keyword: keyword, platform: platform)
                guard requestHasMore[key] == true else { return nil }
                return ComicSearchBreakpoint.Request(
                    keyword: keyword,
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
        searchesKeywordsSeparately: Bool,
        resumeFrom breakpoint: ComicSearchBreakpoint? = nil,
        force: Bool = false
    ) async {
        let trimmed = trimmedKeyword(keyword)
        let keywords = ComicSearchKeywordSequence.keywords(
            from: trimmed,
            searchesSeparately: searchesKeywordsSeparately
        )
        guard !keywords.isEmpty else {
            reset()
            return
        }
        if case .loaded = state,
           !force,
           breakpoint == nil,
           currentTarget == target,
           currentKeyword == trimmed,
           currentOptions == options,
           currentSearchesKeywordsSeparately == searchesKeywordsSeparately {
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
        currentKeywords = keywords
        currentOptions = options
        currentSearchesKeywordsSeparately = searchesKeywordsSeparately

        var comics: [ComicListItem] = []
        var failures: [String] = []
        var requestCount = 0
        let resumePages = breakpoint.map { breakpoint in
            Dictionary(
                breakpoint.requests.map {
                    (ComicSearchRequestKey(keyword: $0.keyword, platform: $0.platform), $0.nextPage)
                },
                uniquingKeysWith: max
            )
        }

        for searchKeyword in keywords {
            guard generation == requestGeneration, !Task.isCancelled else { return }

            let platforms = target.platforms.filter { platform in
                guard let resumePages else { return true }
                return resumePages[ComicSearchRequestKey(keyword: searchKeyword, platform: platform)] != nil
            }
            guard !platforms.isEmpty else { continue }
            let pages = Dictionary(uniqueKeysWithValues: platforms.map { platform in
                let key = ComicSearchRequestKey(keyword: searchKeyword, platform: platform)
                return (platform, resumePages?[key] ?? 1)
            })
            requestCount += platforms.count
            for platform in platforms {
                let key = ComicSearchRequestKey(keyword: searchKeyword, platform: platform)
                currentPages[key] = (pages[platform] ?? 1) - 1
                requestHasMore[key] = true
            }

            let responses = await fetchSearchPages(
                platforms: platforms,
                keyword: searchKeyword,
                accounts: accounts,
                pages: pages,
                options: options
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }

            var groupsByPlatform: [ComicPlatform: [ComicListItem]] = [:]
            for response in responses {
                let key = ComicSearchRequestKey(keyword: searchKeyword, platform: response.platform)
                if let items = response.items {
                    currentPages[key] = pages[response.platform]
                    requestHasMore[key] = !items.isEmpty
                    groupsByPlatform[response.platform] = items
                } else if let message = response.errorMessage {
                    failures.append(failureMessage(keyword: searchKeyword, platform: response.platform, message: message))
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
              !currentKeywords.isEmpty else {
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

        for searchKeyword in currentKeywords {
            guard generation == requestGeneration, !Task.isCancelled else { return }

            let platforms = target.platforms.filter { platform in
                requestHasMore[ComicSearchRequestKey(keyword: searchKeyword, platform: platform)] == true
            }
            guard !platforms.isEmpty else { continue }

            let pages = Dictionary(uniqueKeysWithValues: platforms.map { platform in
                let key = ComicSearchRequestKey(keyword: searchKeyword, platform: platform)
                return (platform, (currentPages[key] ?? 0) + 1)
            })
            let responses = await fetchSearchPages(
                platforms: platforms,
                keyword: searchKeyword,
                accounts: accounts,
                pages: pages,
                options: options
            )
            guard generation == requestGeneration, !Task.isCancelled else { return }

            var groupsByPlatform: [ComicPlatform: [ComicListItem]] = [:]
            for response in responses {
                let key = ComicSearchRequestKey(keyword: searchKeyword, platform: response.platform)
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
        keyword: String,
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
                            keyword: keyword,
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
        guard currentKeywords.count > 1 else { return "\(platform.title): \(message)" }
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
        currentKeywords.removeAll()
        currentOptions = ComicSearchAdvancedOptions()
        currentSearchesKeywordsSeparately = false
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

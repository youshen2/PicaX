import Combine
import Foundation

@MainActor
final class ComicReaderViewModel: ObservableObject {
    @Published private(set) var state: ReaderLoadState = .idle
    @Published private(set) var currentChapterIndex: Int
    @Published private(set) var currentPageIndex: Int
    @Published private(set) var requestedPageIndex: Int

    private let detail: ComicDetailInfo
    private let service: ComicContentService
    private let localChapterImageProvider: ((ComicChapter, Int) async -> [ComicChapterImage])?
    private var loadedChapterID: String?
    private var preloadDebounceTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var preloadedImageKeys = Set<String>()

    init(
        detail: ComicDetailInfo,
        initialChapterIndex: Int,
        initialPageIndex: Int,
        service: ComicContentService,
        localChapterImageProvider: ((ComicChapter, Int) async -> [ComicChapterImage])?
    ) {
        self.detail = detail
        self.currentChapterIndex = min(max(initialChapterIndex, 0), max(detail.chapters.count - 1, 0))
        self.currentPageIndex = max(initialPageIndex, 0)
        self.requestedPageIndex = max(initialPageIndex, 0)
        self.service = service
        self.localChapterImageProvider = localChapterImageProvider
    }

    var navigationTitle: String {
        guard detail.chapters.indices.contains(currentChapterIndex) else { return detail.item.title }
        return detail.chapters[currentChapterIndex].title
    }

    var progressTitle: String {
        let page = currentPageIndex + 1
        let total = currentImagesCount
        return total > 0 ? "E\(currentChapterIndex + 1)/\(max(detail.chapters.count, 1)) · P\(page)/\(total)" : "正在准备"
    }

    var progress: Double {
        guard currentImagesCount > 0 else { return 0 }
        return Double(currentPageIndex + 1) / Double(currentImagesCount)
    }

    var canLoadPreviousChapter: Bool {
        currentChapterIndex > 0
    }

    var canLoadNextChapter: Bool {
        currentChapterIndex < detail.chapters.count - 1
    }

    private var currentImagesCount: Int {
        if case .loaded(let images) = state {
            return images.count
        }
        return 0
    }

    func loadChapter(index: Int, pageIndex: Int, account: PlatformAccount?, force: Bool = false, preloadImageCount: Int = 0, preloadDelay: Double = 0) async {
        guard !detail.chapters.isEmpty else {
            state = .failed("当前漫画没有章节。")
            return
        }
        let boundedIndex = min(max(index, 0), detail.chapters.count - 1)
        let chapter = detail.chapters[boundedIndex]
        if loadedChapterID == chapter.id, case .loaded = state, !force {
            return
        }

        currentChapterIndex = boundedIndex
        currentPageIndex = max(pageIndex, 0)
        requestedPageIndex = max(pageIndex, 0)
        cancelImagePreload()
        state = .loading
        do {
            let images: [ComicChapterImage]
            if let localChapterImageProvider {
                images = await localChapterImageProvider(chapter, boundedIndex)
                guard !images.isEmpty else {
                    state = .failed("当前章节尚未下载。")
                    return
                }
            } else {
                images = try await service.loadChapterImages(item: detail.item, chapter: chapter, account: account)
            }
            loadedChapterID = chapter.id
            state = .loaded(images)
            currentPageIndex = min(currentPageIndex, max(images.count - 1, 0))
            requestedPageIndex = min(requestedPageIndex, max(images.count - 1, 0))
            scheduleImagePreload(
                aroundPage: currentPageIndex,
                count: preloadImageCount,
                delay: 0,
                targetPixelWidth: nil
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadPreviousChapter(account: PlatformAccount?, preloadImageCount: Int = 0, preloadDelay: Double = 0) async {
        guard canLoadPreviousChapter else { return }
        await loadChapter(index: currentChapterIndex - 1, pageIndex: 0, account: account, force: true, preloadImageCount: preloadImageCount, preloadDelay: preloadDelay)
    }

    func loadNextChapter(account: PlatformAccount?, preloadImageCount: Int = 0, preloadDelay: Double = 0) async {
        guard canLoadNextChapter else { return }
        await loadChapter(index: currentChapterIndex + 1, pageIndex: 0, account: account, force: true, preloadImageCount: preloadImageCount, preloadDelay: preloadDelay)
    }

    func updateCurrentPage(_ index: Int) -> Bool {
        let boundedIndex = max(index, 0)
        guard currentPageIndex != boundedIndex || requestedPageIndex != boundedIndex else {
            return false
        }
        currentPageIndex = boundedIndex
        requestedPageIndex = boundedIndex
        return true
    }

    func scheduleImagePreload(aroundPage index: Int, count: Int, delay: Double, targetPixelWidth: Int?) {
        preloadDebounceTask?.cancel()
        guard case .loaded(let images) = state else { return }
        let boundedCount = min(max(count, 0), 15)
        guard boundedCount > 0, !images.isEmpty else {
            preloadTask?.cancel()
            return
        }

        let pageIndex = min(max(index, 0), images.count - 1)
        let startIndex = max(pageIndex - boundedCount, 0)
        let endIndex = min(pageIndex + boundedCount, images.count - 1)
        let preloadItems = (startIndex...endIndex)
            .filter { $0 != pageIndex }
            .map { images[$0].urlString }
            .map { (urlString: $0, key: preloadKey(urlString: $0, targetPixelWidth: targetPixelWidth)) }
            .filter { !preloadedImageKeys.contains($0.key) }
        let urlStrings = preloadItems.map(\.urlString)
        let preloadKeys = preloadItems.map(\.key)
        guard !urlStrings.isEmpty else {
            preloadTask?.cancel()
            return
        }

        let chapterID = loadedChapterID
        let boundedDelay = min(max(delay, 0), 5)
        if boundedDelay <= 0 {
            startImagePreload(urlStrings: urlStrings, preloadKeys: preloadKeys, chapterID: chapterID, pageIndex: pageIndex, targetPixelWidth: targetPixelWidth)
            return
        }

        preloadDebounceTask = Task { [weak self, urlStrings, preloadKeys, chapterID, pageIndex, boundedDelay, targetPixelWidth] in
            let delayNanoseconds = UInt64((boundedDelay * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedChapterID == chapterID, self.currentPageIndex == pageIndex else { return }
                self.startImagePreload(urlStrings: urlStrings, preloadKeys: preloadKeys, chapterID: chapterID, pageIndex: pageIndex, targetPixelWidth: targetPixelWidth)
            }
        }
    }

    private func startImagePreload(urlStrings: [String], preloadKeys: [String], chapterID: String?, pageIndex: Int, targetPixelWidth: Int?) {
        preloadTask?.cancel()
        let service = service
        preloadTask = Task(priority: .background) { [weak self, service, urlStrings, preloadKeys, chapterID, pageIndex, targetPixelWidth] in
            let shouldStart = await MainActor.run {
                guard let self else { return false }
                return self.loadedChapterID == chapterID && self.currentPageIndex == pageIndex
            }
            guard shouldStart, !Task.isCancelled else { return }
            if targetPixelWidth == nil {
                await service.prefetchImages(urlStrings: urlStrings)
            } else {
                await ReaderImageDecoder.preload(urlStrings: urlStrings, targetPixelWidth: targetPixelWidth)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedChapterID == chapterID, self.currentPageIndex == pageIndex else { return }
                self.preloadedImageKeys.formUnion(preloadKeys)
            }
        }
    }

    private func preloadKey(urlString: String, targetPixelWidth: Int?) -> String {
        "\(urlString)#\(targetPixelWidth ?? 0)"
    }

    private func cancelImagePreload() {
        preloadDebounceTask?.cancel()
        preloadDebounceTask = nil
        preloadTask?.cancel()
        preloadTask = nil
    }
}

enum ReaderLoadState {
    case idle
    case loading
    case loaded([ComicChapterImage])
    case failed(String)
}

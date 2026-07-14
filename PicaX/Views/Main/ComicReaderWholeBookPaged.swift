import SwiftUI

private enum ReaderWholeBookPagedItem {
    case page(section: ReaderWholeBookChapterSection, pageIndex: Int)
    case comments(section: ReaderWholeBookChapterSection)

    var id: String {
        switch self {
        case .page(let section, let pageIndex):
            "whole-book-page-\(section.chapterIndex)-\(pageIndex)"
        case .comments(let section):
            "whole-book-comments-\(section.chapterIndex)"
        }
    }

    var pageID: ReaderWholeBookPageID? {
        guard case .page(let section, let pageIndex) = self else { return nil }
        return ReaderWholeBookPageID(chapterIndex: section.chapterIndex, pageIndex: pageIndex)
    }
}

struct ReaderWholeBookPagedView: View {
    let item: ComicListItem
    let chapters: [ComicChapter]
    let readingMode: ReaderReadingMode
    let initialChapterIndex: Int
    let initialPageIndex: Int
    let initialImages: [ComicChapterImage]
    let service: ComicContentService
    let account: PlatformAccount?
    let localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?
    let loadChapterImages: (Int) async throws -> [ComicChapterImage]
    let preloadImageCount: Int
    let chapterLoadThreshold: Int
    let retryCount: Int
    let retryInterval: Double
    let targetPixelWidth: Int?
    let displaySize: CGSize
    let zoomConfiguration: ReaderZoomConfiguration
    let dimsImages: Bool
    let showsChapterComments: Bool
    let uiToggleMode: ReaderUIToggleMode
    let tapPagingEnabled: Bool
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let doubleTapZoomEnabled: Bool
    let isAutoPaging: Bool
    let autoPagingInterval: Double
    @Binding var progressJumpRequest: ReaderProgressJumpRequest?
    let onToggleUI: () -> Void
    let onPositionChange: (Int, Int, Int) -> Void
    let onReachedBookEnd: () -> Void

    @State private var sections: [ReaderWholeBookChapterSection]
    @State private var selectedItemID: String
    @State private var loadableImageIDs = Set<String>()
    @State private var isLoadingNextChapter = false
    @State private var nextChapterError: String?
    @State private var appendTask: Task<Void, Never>?
    @State private var pendingForwardTurn = false
    @State private var isAutoPagingTurnInFlight = false

    init(
        item: ComicListItem,
        chapters: [ComicChapter],
        readingMode: ReaderReadingMode,
        initialChapterIndex: Int,
        initialPageIndex: Int,
        initialImages: [ComicChapterImage],
        service: ComicContentService,
        account: PlatformAccount?,
        localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?,
        loadChapterImages: @escaping (Int) async throws -> [ComicChapterImage],
        preloadImageCount: Int,
        chapterLoadThreshold: Int,
        retryCount: Int,
        retryInterval: Double,
        targetPixelWidth: Int?,
        displaySize: CGSize,
        zoomConfiguration: ReaderZoomConfiguration,
        dimsImages: Bool,
        showsChapterComments: Bool,
        uiToggleMode: ReaderUIToggleMode,
        tapPagingEnabled: Bool,
        tapPagingEdgePercent: Int,
        tapPagingInverted: Bool,
        doubleTapZoomEnabled: Bool,
        isAutoPaging: Bool,
        autoPagingInterval: Double,
        progressJumpRequest: Binding<ReaderProgressJumpRequest?>,
        onToggleUI: @escaping () -> Void,
        onPositionChange: @escaping (Int, Int, Int) -> Void,
        onReachedBookEnd: @escaping () -> Void
    ) {
        self.item = item
        self.chapters = chapters
        self.readingMode = readingMode
        self.initialChapterIndex = initialChapterIndex
        self.initialPageIndex = initialPageIndex
        self.initialImages = initialImages
        self.service = service
        self.account = account
        self.localCommentsProvider = localCommentsProvider
        self.loadChapterImages = loadChapterImages
        self.preloadImageCount = preloadImageCount
        self.chapterLoadThreshold = chapterLoadThreshold
        self.retryCount = retryCount
        self.retryInterval = retryInterval
        self.targetPixelWidth = targetPixelWidth
        self.displaySize = displaySize
        self.zoomConfiguration = zoomConfiguration
        self.dimsImages = dimsImages
        self.showsChapterComments = showsChapterComments
        self.uiToggleMode = uiToggleMode
        self.tapPagingEnabled = tapPagingEnabled
        self.tapPagingEdgePercent = tapPagingEdgePercent
        self.tapPagingInverted = tapPagingInverted
        self.doubleTapZoomEnabled = doubleTapZoomEnabled
        self.isAutoPaging = isAutoPaging
        self.autoPagingInterval = autoPagingInterval
        _progressJumpRequest = progressJumpRequest
        self.onToggleUI = onToggleUI
        self.onPositionChange = onPositionChange
        self.onReachedBookEnd = onReachedBookEnd

        let boundedChapterIndex = min(max(initialChapterIndex, 0), max(chapters.count - 1, 0))
        let chapter = chapters.indices.contains(boundedChapterIndex)
            ? chapters[boundedChapterIndex]
            : ComicChapter(id: "reader-empty", title: "", subtitle: nil)
        let boundedPageIndex = min(max(initialPageIndex, 0), max(initialImages.count - 1, 0))
        let section = ReaderWholeBookChapterSection(
            chapterIndex: boundedChapterIndex,
            chapter: chapter,
            images: initialImages
        )
        _sections = State(initialValue: [section])
        _selectedItemID = State(initialValue: ReaderWholeBookPagedItem.page(
            section: section,
            pageIndex: boundedPageIndex
        ).id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if readingMode == .topToBottom {
                    verticalScroll(proxy: proxy)
                } else {
                    horizontalScroll(proxy: proxy)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .background(Color.black)
            .environment(\.layoutDirection, readingMode == .rightToLeft ? .rightToLeft : .leftToRight)
            .readerInteractionGesture(
                size: displaySize,
                mode: uiToggleMode,
                tapPagingEnabled: tapPagingEnabled,
                tapPagingEdgePercent: tapPagingEdgePercent,
                tapPagingInverted: tapPagingInverted,
                doubleTapZoomEnabled: doubleTapZoomEnabled,
                readingMode: readingMode,
                toggleUI: onToggleUI,
                turnPage: { direction in
                    turnPage(direction, proxy: proxy, animated: true)
                }
            )
            .readerAutoPaging(isEnabled: isAutoPaging, interval: autoPagingInterval) {
                handleAutoPageTick(proxy: proxy)
            }
            .overlay(alignment: .bottom) {
                chapterLoadOverlay
            }
            .onAppear {
                focusLoadableImages(aroundItemID: selectedItemID)
                reportPosition(forItemID: selectedItemID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    proxy.scrollTo(selectedItemID, anchor: pageAnchor)
                }
            }
            .onDisappear {
                appendTask?.cancel()
                appendTask = nil
            }
            .onChange(of: sections.count) { _ in
                guard pendingForwardTurn else { return }
                pendingForwardTurn = false
                turnPage(.next, proxy: proxy, animated: true)
            }
            .onChange(of: progressJumpRequest) { request in
                handleProgressJump(request, proxy: proxy)
            }
        }
    }

    private var pagedItems: [ReaderWholeBookPagedItem] {
        sections.flatMap { section in
            var items = section.images.indices.map {
                ReaderWholeBookPagedItem.page(section: section, pageIndex: $0)
            }
            if showsChapterComments {
                items.append(.comments(section: section))
            }
            return items
        }
    }

    private var hasReachedBookEnd: Bool {
        guard let lastSection = sections.last else { return true }
        return lastSection.chapterIndex >= chapters.count - 1
    }

    private var pageAnchor: UnitPoint {
        readingMode == .topToBottom ? .top : .leading
    }

    @ViewBuilder
    private func verticalScroll(proxy: ScrollViewProxy) -> some View {
        let scroll = ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                pagedContent
            }
            .modifier(ReaderScrollTargetLayoutModifier())
        }
        scroll.modifier(ReaderPagingScrollModifier())
    }

    @ViewBuilder
    private func horizontalScroll(proxy: ScrollViewProxy) -> some View {
        let scroll = ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                pagedContent
            }
            .modifier(ReaderScrollTargetLayoutModifier())
        }
        scroll.modifier(ReaderPagingScrollModifier())
    }

    @ViewBuilder
    private var pagedContent: some View {
        ForEach(pagedItems, id: \.id) { item in
            switch item {
            case .page(let section, let pageIndex):
                ReaderImageView(
                    image: section.images[pageIndex],
                    retryCount: retryCount,
                    retryInterval: retryInterval,
                    targetPixelWidth: targetPixelWidth,
                    containerSize: displaySize,
                    isLoadAllowed: loadableImageIDs.contains(section.images[pageIndex].urlString),
                    zoomConfiguration: zoomConfiguration,
                    dimsImage: dimsImages
                )
                .frame(width: displaySize.width, height: displaySize.height)
                .id(item.id)
                .onAppear {
                    select(item)
                }
            case .comments(let section):
                ReaderChapterCommentsView(
                    item: self.item,
                    chapter: section.chapter,
                    chapterIndex: section.chapterIndex,
                    service: service,
                    account: account,
                    localCommentsProvider: localCommentsProvider
                )
                .frame(width: displaySize.width, height: displaySize.height)
                .id(item.id)
                .onAppear {
                    selectedItemID = item.id
                }
            }
        }
    }

    @ViewBuilder
    private var chapterLoadOverlay: some View {
        if isLoadingNextChapter {
            ProgressView("正在加载下一章…")
                .tint(.white)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(.bottom, 24)
        } else if let nextChapterError {
            Button {
                requestNextChapter()
            } label: {
                Label(nextChapterError, systemImage: "arrow.clockwise")
                    .lineLimit(2)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func select(_ item: ReaderWholeBookPagedItem) {
        guard case .page(let section, let pageIndex) = item else { return }
        selectedItemID = item.id
        focusLoadableImages(aroundItemID: item.id)
        onPositionChange(section.chapterIndex, pageIndex, section.images.count)
        if section.chapterIndex == sections.last?.chapterIndex,
           pageIndex >= max(section.images.count - chapterLoadThreshold, 0) {
            requestNextChapter()
        }
    }

    private func reportPosition(forItemID itemID: String) {
        guard let item = pagedItems.first(where: { $0.id == itemID }),
              case .page(let section, let pageIndex) = item else {
            return
        }
        onPositionChange(section.chapterIndex, pageIndex, section.images.count)
    }

    private func focusLoadableImages(aroundItemID itemID: String) {
        let items = pagedItems
        guard let center = items.firstIndex(where: { $0.id == itemID }) else { return }
        let radius = min(max(preloadImageCount, 0), 15)
        let start = max(center - radius, 0)
        let end = min(center + radius, items.count - 1)
        let imageIDs = Set(items[start...end].compactMap { item -> String? in
            guard case .page(let section, let pageIndex) = item else { return nil }
            return section.images[pageIndex].urlString
        })
        guard imageIDs != loadableImageIDs else { return }
        loadableImageIDs = imageIDs
    }

    private func turnPage(_ direction: ReaderPageTurnDirection, proxy: ScrollViewProxy, animated: Bool) {
        let items = pagedItems
        guard let currentIndex = items.firstIndex(where: { $0.id == selectedItemID }) else { return }
        let targetIndex = direction == .next ? currentIndex + 1 : currentIndex - 1
        guard items.indices.contains(targetIndex) else {
            if direction == .next {
                if hasReachedBookEnd {
                    onReachedBookEnd()
                } else {
                    pendingForwardTurn = true
                    requestNextChapter()
                }
            }
            return
        }

        let target = items[targetIndex]
        selectedItemID = target.id
        focusLoadableImages(aroundItemID: target.id)
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(target.id, anchor: pageAnchor)
            }
        } else {
            proxy.scrollTo(target.id, anchor: pageAnchor)
        }
        if case .page(let section, let pageIndex) = target {
            onPositionChange(section.chapterIndex, pageIndex, section.images.count)
        }
    }

    private func handleAutoPageTick(proxy: ScrollViewProxy) {
        guard isAutoPaging, !isAutoPagingTurnInFlight else { return }
        isAutoPagingTurnInFlight = true
        turnPage(.next, proxy: proxy, animated: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            isAutoPagingTurnInFlight = false
        }
    }

    private func requestNextChapter() {
        guard !isLoadingNextChapter,
              let lastSection = sections.last,
              lastSection.chapterIndex < chapters.count - 1 else {
            return
        }
        let nextIndex = lastSection.chapterIndex + 1
        isLoadingNextChapter = true
        nextChapterError = nil
        appendTask?.cancel()
        appendTask = Task { @MainActor in
            do {
                let images = try await loadChapterImages(nextIndex)
                guard !Task.isCancelled else { return }
                guard !images.isEmpty else {
                    throw ReaderWholeBookPagedLoadError.emptyChapter
                }
                sections.append(ReaderWholeBookChapterSection(
                    chapterIndex: nextIndex,
                    chapter: chapters[nextIndex],
                    images: images
                ))
                isLoadingNextChapter = false
                appendTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                pendingForwardTurn = false
                isLoadingNextChapter = false
                nextChapterError = "加载下一章失败，点按重试"
                appendTask = nil
            }
        }
    }

    private func handleProgressJump(_ request: ReaderProgressJumpRequest?, proxy: ScrollViewProxy) {
        guard let request else { return }
        defer {
            if progressJumpRequest?.id == request.id {
                progressJumpRequest = nil
            }
        }
        guard let section = sections.first(where: { $0.chapterIndex == request.chapterIndex }),
              !section.images.isEmpty else {
            return
        }
        let pageIndex = min(max(request.pageIndex, 0), section.images.count - 1)
        let target = ReaderWholeBookPagedItem.page(section: section, pageIndex: pageIndex)
        selectedItemID = target.id
        focusLoadableImages(aroundItemID: target.id)
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(target.id, anchor: pageAnchor)
        }
        onPositionChange(section.chapterIndex, pageIndex, section.images.count)
    }
}

private enum ReaderWholeBookPagedLoadError: LocalizedError {
    case emptyChapter

    var errorDescription: String? {
        "章节没有返回可阅读图片。"
    }
}

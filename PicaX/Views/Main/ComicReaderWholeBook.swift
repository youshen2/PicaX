import SwiftUI

struct ReaderWholeBookChapterSection: Identifiable {
    let chapterIndex: Int
    let chapter: ComicChapter
    let images: [ComicChapterImage]

    var id: String {
        "\(chapterIndex)-\(chapter.id)"
    }
}

struct ReaderWholeBookContinuousView: View {
    let item: ComicListItem
    let chapters: [ComicChapter]
    let initialChapterIndex: Int
    let initialPageIndex: Int
    let initialImages: [ComicChapterImage]
    let service: ComicContentService
    let account: PlatformAccount?
    let localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?
    let loadChapterImages: (Int) async throws -> [ComicChapterImage]
    let imageSpacing: CGFloat
    let firstImageTopPadding: CGFloat
    let lastImageBottomPadding: CGFloat
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
    let tapPagingDistancePercent: Int
    let doubleTapZoomEnabled: Bool
    let isAutoPaging: Bool
    let isAutoPagingSuspended: Bool
    let autoPagingInterval: Double
    let autoPagingDistancePercent: Int
    let smoothContinuousAutoPaging: Bool
    @Binding var progressJumpRequest: ReaderProgressJumpRequest?
    let onToggleUI: () -> Void
    let onPositionChange: (Int, Int, Int) -> Void
    let onReachedBookEnd: () -> Void

    @State private var sections: [ReaderWholeBookChapterSection]
    @State private var loadableImageIDs = Set<String>()
    @State private var currentVisiblePage: ReaderWholeBookPageID
    @State private var isLoadingNextChapter = false
    @State private var nextChapterError: String?
    @State private var appendTask: Task<Void, Never>?
    @State private var scrollBridge = ReaderContinuousScrollBridge()
    @State private var scrollTracker = ReaderContinuousScrollTracker()
    @State private var isAutoPagingTurnInFlight = false
    @State private var visiblePageIDs = Set<ReaderWholeBookPageID>()

    init(
        item: ComicListItem,
        chapters: [ComicChapter],
        initialChapterIndex: Int,
        initialPageIndex: Int,
        initialImages: [ComicChapterImage],
        service: ComicContentService,
        account: PlatformAccount?,
        localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?,
        loadChapterImages: @escaping (Int) async throws -> [ComicChapterImage],
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
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
        tapPagingDistancePercent: Int,
        doubleTapZoomEnabled: Bool,
        isAutoPaging: Bool,
        isAutoPagingSuspended: Bool,
        autoPagingInterval: Double,
        autoPagingDistancePercent: Int,
        smoothContinuousAutoPaging: Bool,
        progressJumpRequest: Binding<ReaderProgressJumpRequest?>,
        onToggleUI: @escaping () -> Void,
        onPositionChange: @escaping (Int, Int, Int) -> Void,
        onReachedBookEnd: @escaping () -> Void
    ) {
        self.item = item
        self.chapters = chapters
        self.initialChapterIndex = initialChapterIndex
        self.initialPageIndex = initialPageIndex
        self.initialImages = initialImages
        self.service = service
        self.account = account
        self.localCommentsProvider = localCommentsProvider
        self.loadChapterImages = loadChapterImages
        self.imageSpacing = imageSpacing
        self.firstImageTopPadding = firstImageTopPadding
        self.lastImageBottomPadding = lastImageBottomPadding
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
        self.tapPagingDistancePercent = tapPagingDistancePercent
        self.doubleTapZoomEnabled = doubleTapZoomEnabled
        self.isAutoPaging = isAutoPaging
        self.isAutoPagingSuspended = isAutoPagingSuspended
        self.autoPagingInterval = autoPagingInterval
        self.autoPagingDistancePercent = autoPagingDistancePercent
        self.smoothContinuousAutoPaging = smoothContinuousAutoPaging
        _progressJumpRequest = progressJumpRequest
        self.onToggleUI = onToggleUI
        self.onPositionChange = onPositionChange
        self.onReachedBookEnd = onReachedBookEnd

        let boundedChapterIndex = min(max(initialChapterIndex, 0), max(chapters.count - 1, 0))
        let chapter = chapters.indices.contains(boundedChapterIndex)
            ? chapters[boundedChapterIndex]
            : ComicChapter(id: "reader-empty", title: "", subtitle: nil)
        let boundedPageIndex = min(max(initialPageIndex, 0), max(initialImages.count - 1, 0))
        _sections = State(initialValue: [
            ReaderWholeBookChapterSection(
                chapterIndex: boundedChapterIndex,
                chapter: chapter,
                images: initialImages
            )
        ])
        _currentVisiblePage = State(initialValue: ReaderWholeBookPageID(
            chapterIndex: boundedChapterIndex,
            pageIndex: boundedPageIndex
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: imageSpacing) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionOffset, section in
                        Section {
                            ForEach(section.images.indices, id: \.self) { pageIndex in
                                let pageID = ReaderWholeBookPageID(
                                    chapterIndex: section.chapterIndex,
                                    pageIndex: pageIndex
                                )
                                ReaderImageView(
                                    image: section.images[pageIndex],
                                    retryCount: retryCount,
                                    retryInterval: retryInterval,
                                    targetPixelWidth: targetPixelWidth,
                                    displayWidth: displaySize.width,
                                    containerSize: nil,
                                    isLoadAllowed: loadableImageIDs.contains(section.images[pageIndex].urlString),
                                    zoomConfiguration: zoomConfiguration,
                                    dimsImage: dimsImages
                                )
                                .padding(.top, sectionOffset == 0 && pageIndex == 0 ? firstImageTopPadding : 0)
                                .padding(.bottom, pageIndex == section.images.index(before: section.images.endIndex) ? lastImageBottomPadding : 0)
                                .id(pageID)
                                .background {
                                    GeometryReader { pageGeometry in
                                        Color.clear.preference(
                                            key: ReaderWholeBookVisiblePageFramesPreferenceKey.self,
                                            value: [
                                                pageID: pageGeometry.frame(in: .named(coordinateSpaceName))
                                            ]
                                        )
                                    }
                                }
                                .onAppear {
                                    requestNextChapterIfNeeded(visiblePage: pageID)
                                }
                            }

                            if showsChapterComments {
                                ReaderChapterCommentsView(
                                    item: item,
                                    chapter: section.chapter,
                                    chapterIndex: section.chapterIndex,
                                    service: service,
                                    account: account,
                                    localCommentsProvider: localCommentsProvider
                                )
                                .id("whole-book-comments-\(section.chapterIndex)")
                                .padding(.horizontal, 10)
                            }
                        } header: {
                            if sectionOffset > 0 {
                                chapterHeader(section)
                            }
                        }
                    }

                    chapterAppendFooter
                }
                .padding(.vertical, 10)
                .readerContinuousScrollBridge(scrollBridge) { metrics in
                    scrollTracker.updateMetrics(metrics)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .background(Color.black)
            .ignoresSafeArea(.container)
            .readerInteractionGesture(
                size: displaySize,
                mode: uiToggleMode,
                tapPagingEnabled: tapPagingEnabled,
                tapPagingEdgePercent: tapPagingEdgePercent,
                tapPagingInverted: tapPagingInverted,
                doubleTapZoomEnabled: doubleTapZoomEnabled,
                readingMode: .topToBottomContinuous,
                toggleUI: onToggleUI,
                turnPage: { direction in
                    handleTapPage(direction)
                }
            )
            .readerAutoPaging(
                isEnabled: isAutoPaging && !isAutoPagingSuspended && !smoothContinuousAutoPaging,
                interval: autoPagingInterval
            ) {
                handleAutoPageTick()
            }
            .readerSmoothAutoPaging(
                isEnabled: isAutoPaging && !isAutoPagingSuspended && smoothContinuousAutoPaging,
                pointsPerSecond: smoothAutoPagingPointsPerSecond
            ) { distance in
                handleSmoothAutoPageStep(distance: distance)
            }
            .onPreferenceChange(ReaderWholeBookVisiblePageFramesPreferenceKey.self) { pageFrames in
                syncVisiblePage(pageFrames)
            }
            .onAppear {
                focusLoadableImages(around: currentVisiblePage)
                onPositionChange(
                    currentVisiblePage.chapterIndex,
                    currentVisiblePage.pageIndex,
                    initialImages.count
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    proxy.scrollTo(currentVisiblePage, anchor: .top)
                }
            }
            .onDisappear {
                appendTask?.cancel()
                appendTask = nil
            }
            .onChange(of: progressJumpRequest) { request in
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
                let pageID = ReaderWholeBookPageID(chapterIndex: request.chapterIndex, pageIndex: pageIndex)
                focusLoadableImages(around: pageID)
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(pageID, anchor: .top)
                }
                onPositionChange(request.chapterIndex, pageIndex, section.images.count)
            }
            .readerContinuousZoom(
                configuration: zoomConfiguration,
                resetID: coordinateSpaceName,
                allowsInteraction: true
            )
        }
    }

    private var coordinateSpaceName: String {
        "reader-whole-book-\(item.platform.rawValue)-\(item.id)-\(initialChapterIndex)"
    }

    private var lastSection: ReaderWholeBookChapterSection? {
        sections.last
    }

    private var hasReachedBookEnd: Bool {
        guard let lastSection else { return true }
        return lastSection.chapterIndex >= chapters.count - 1
    }

    private var smoothAutoPagingPointsPerSecond: CGFloat {
        guard displaySize.height.isFinite,
              displaySize.height > 0,
              autoPagingInterval.isFinite,
              autoPagingInterval > 0 else {
            return 0
        }
        let distance = displaySize.height * CGFloat(autoPagingDistancePercent) / 100
        return distance / CGFloat(autoPagingInterval)
    }

    private var flattenedPages: [(id: ReaderWholeBookPageID, image: ComicChapterImage)] {
        sections.flatMap { section in
            section.images.indices.map { pageIndex in
                (
                    id: ReaderWholeBookPageID(chapterIndex: section.chapterIndex, pageIndex: pageIndex),
                    image: section.images[pageIndex]
                )
            }
        }
    }

    @ViewBuilder
    private func chapterHeader(_ section: ReaderWholeBookChapterSection) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.caption.weight(.bold))
            Text(section.chapter.title.isEmpty ? "第 \(section.chapterIndex + 1) 章" : section.chapter.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.black)
    }

    @ViewBuilder
    private var chapterAppendFooter: some View {
        if isLoadingNextChapter {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("正在加载下一章…")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.78))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if let nextChapterError {
            VStack(spacing: 12) {
                Text(nextChapterError)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                Button("重试加载下一章") {
                    requestNextChapter()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        } else if hasReachedBookEnd {
            Label("已读完全书", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        }
    }

    private func syncVisiblePage(_ pageFrames: [ReaderWholeBookPageID: CGRect]) {
        guard displaySize.height.isFinite, displaySize.height > 0 else { return }
        let viewport = CGRect(x: 0, y: 0, width: .greatestFiniteMagnitude, height: displaySize.height)
        let viewportCenterY = displaySize.height / 2
        let visiblePages = pageFrames.compactMap { id, frame -> (ReaderWholeBookPageID, CGFloat, CGFloat)? in
            guard frame.minY.isFinite, frame.maxY.isFinite else { return nil }
            let visibleHeight = frame.intersection(viewport).height
            guard visibleHeight > 1 else { return nil }
            return (id, visibleHeight, abs(frame.midY - viewportCenterY))
        }
        guard let visiblePage = visiblePages.max(by: { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 1 {
                return lhs.1 < rhs.1
            }
            return lhs.2 > rhs.2
        })?.0,
              let section = sections.first(where: { $0.chapterIndex == visiblePage.chapterIndex }) else {
            return
        }

        if visiblePage == flattenedPages.first?.id,
           visiblePage != currentVisiblePage,
           !scrollTracker.isUserInteracting,
           !scrollTracker.wasLastUserScrollNearTop(
               maximumOffset: (pageFrames[visiblePage]?.height ?? displaySize.height) + imageSpacing
           ) {
            return
        }

        let newVisiblePageIDs = Set(visiblePages.map(\.0))
        if newVisiblePageIDs != visiblePageIDs {
            visiblePageIDs = newVisiblePageIDs
            focusLoadableImages(around: visiblePage, visiblePageIDs: newVisiblePageIDs)
        }
        guard visiblePage != currentVisiblePage else { return }
        currentVisiblePage = visiblePage
        onPositionChange(visiblePage.chapterIndex, visiblePage.pageIndex, section.images.count)
        requestNextChapterIfNeeded(visiblePage: visiblePage)
    }

    private func focusLoadableImages(
        around pageID: ReaderWholeBookPageID,
        visiblePageIDs: Set<ReaderWholeBookPageID> = []
    ) {
        let pages = flattenedPages
        guard !pages.isEmpty else {
            loadableImageIDs.removeAll(keepingCapacity: true)
            return
        }
        var centers = pages.indices.filter { visiblePageIDs.contains(pages[$0].id) }
        if centers.isEmpty, let index = pages.firstIndex(where: { $0.id == pageID }) {
            centers = [index]
        }
        guard !centers.isEmpty else { return }

        let radius = min(max(preloadImageCount, 0), 15)
        var indices = Set<Int>()
        for center in centers {
            let start = max(center - radius, 0)
            let end = min(center + radius, pages.count - 1)
            indices.formUnion(start...end)
        }
        let imageIDs = Set(indices.map { pages[$0].image.urlString })
        guard imageIDs != loadableImageIDs else { return }
        loadableImageIDs = imageIDs
    }

    private func requestNextChapterIfNeeded(visiblePage: ReaderWholeBookPageID) {
        guard let lastSection,
              visiblePage.chapterIndex == lastSection.chapterIndex,
              visiblePage.pageIndex >= max(lastSection.images.count - chapterLoadThreshold, 0) else {
            return
        }
        requestNextChapter()
    }

    private func requestNextChapter() {
        guard !isLoadingNextChapter,
              let lastSection,
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
                    throw ReaderWholeBookLoadError.emptyChapter
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
                isLoadingNextChapter = false
                nextChapterError = "下一章加载失败：\(error.localizedDescription)"
                appendTask = nil
            }
        }
    }

    private func handleTapPage(_ direction: ReaderPageTurnDirection) {
        guard displaySize.height.isFinite, displaySize.height > 0 else { return }
        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let distance = max(displaySize.height * CGFloat(tapPagingDistancePercent) / 100, 1)
        let targetY = direction == .previous
            ? max(currentY - distance, 0)
            : min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: true) {
            scrollTracker.updateScrollY(targetY)
        }
        if direction == .next, targetY >= maxY - 4 {
            requestNextChapter()
        }
    }

    private func handleAutoPageTick() {
        guard isAutoPaging,
              !isAutoPagingSuspended,
              !smoothContinuousAutoPaging,
              !isAutoPagingTurnInFlight,
              displaySize.height.isFinite, displaySize.height > 0 else {
            return
        }
        isAutoPagingTurnInFlight = true
        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let distance = max(displaySize.height * CGFloat(autoPagingDistancePercent) / 100, 1)
        let targetY = min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: true) {
            scrollTracker.updateScrollY(targetY)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            isAutoPagingTurnInFlight = false
            guard isAutoPaging, targetY >= maxY - 4 else { return }
            if hasReachedBookEnd {
                onReachedBookEnd()
            } else {
                requestNextChapter()
            }
        }
    }

    private func handleSmoothAutoPageStep(distance: CGFloat) {
        guard isAutoPaging,
              !isAutoPagingSuspended,
              smoothContinuousAutoPaging,
              !isAutoPagingTurnInFlight,
              !scrollBridge.isUserInteracting,
              !isLoadingNextChapter,
              nextChapterError == nil,
              scrollTracker.hasContentMetrics,
              displaySize.height.isFinite,
              displaySize.height > 0,
              distance.isFinite,
              distance > 0 else {
            return
        }

        let currentY = scrollTracker.effectiveScrollY(fallback: nil)
        let maxY = scrollTracker.maxScrollY(fallbackViewportHeight: displaySize.height)
        let targetY = min(currentY + distance, maxY)
        if scrollBridge.scroll(toY: targetY, animated: false) {
            scrollTracker.updateScrollY(targetY)
        }

        guard targetY >= maxY - 0.5 else { return }
        if hasReachedBookEnd {
            onReachedBookEnd()
        } else {
            requestNextChapter()
        }
    }
}

private enum ReaderWholeBookLoadError: LocalizedError {
    case emptyChapter

    var errorDescription: String? {
        "章节没有返回可阅读图片。"
    }
}

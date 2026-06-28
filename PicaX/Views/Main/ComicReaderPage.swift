import Combine
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ComicReaderPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var readingDuration: ReadingDurationService
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReaderSettingsKey.progressStyle) private var progressStyle = ReaderProgressStyle.circular.rawValue
    @AppStorage(ReaderSettingsKey.progressPosition) private var progressPosition = ReaderProgressPosition.trailing.rawValue
    @AppStorage(ReaderSettingsKey.showsPageLabel) private var showsPageLabel = true
    @AppStorage(ReaderSettingsKey.progressFollowsUIVisibility) private var progressFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.progressTapSelectionEnabled) private var progressTapSelectionEnabled = false
    @AppStorage(ReaderSettingsKey.progressBackgroundOpacity) private var progressBackgroundOpacity = 0.78
    @AppStorage(ReaderSettingsKey.progressBottomInset) private var progressBottomInset = 16.0
    @AppStorage(ReaderSettingsKey.readingMode) private var readingMode = ReaderReadingMode.topToBottomContinuous.rawValue
    @AppStorage(ReaderSettingsKey.imageSpacing) private var imageSpacing = 0.0
    @AppStorage(ReaderSettingsKey.firstImageTopPadding) private var firstImageTopPadding = 115.0
    @AppStorage(ReaderSettingsKey.lastImageBottomPadding) private var lastImageBottomPadding = 0.0
    @AppStorage(ReaderSettingsKey.preloadImageCount) private var preloadImageCount = 3
    @AppStorage(ReaderSettingsKey.pagedPreloadDelay) private var pagedPreloadDelay = 1.2
    @AppStorage(ReaderSettingsKey.imageRetryCount) private var imageRetryCount = 2
    @AppStorage(ReaderSettingsKey.imageRetryInterval) private var imageRetryInterval = 1.0
    @AppStorage(ReaderSettingsKey.reducesImageBrightnessInDarkMode) private var reducesImageBrightnessInDarkMode = false
    @AppStorage(ReaderSettingsKey.hidesStatusBar) private var hidesStatusBar = false
    @AppStorage(ReaderSettingsKey.uiToggleMode) private var uiToggleMode = ReaderUIToggleMode.single.rawValue
    @AppStorage(ReaderSettingsKey.tapPagingEnabled) private var tapPagingEnabled = false
    @AppStorage(ReaderSettingsKey.tapPagingInverted) private var tapPagingInverted = false
    @AppStorage(ReaderSettingsKey.tapPagingEdgePercent) private var tapPagingEdgePercent = 28
    @AppStorage(ReaderSettingsKey.tapPagingDistancePercent) private var tapPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.pinchZoomEnabled) private var pinchZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomEnabled) private var doubleTapZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomScale) private var doubleTapZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.longPressZoomEnabled) private var longPressZoomEnabled = true
    @AppStorage(ReaderSettingsKey.longPressZoomScale) private var longPressZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.autoPagingInterval) private var autoPagingInterval = 6.0
    @AppStorage(ReaderSettingsKey.autoPagingDistancePercent) private var autoPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.autoPagingTurnsChapter) private var autoPagingTurnsChapter = true
    @AppStorage(ReaderSettingsKey.showsChapterCommentsAtEnd) private var showsChapterCommentsAtEnd = false
    @AppStorage(ReaderSettingsKey.showsSystemStatus) private var showsSystemStatus = false
    @AppStorage(ReaderSettingsKey.systemStatusFollowsUIVisibility) private var systemStatusFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.systemStatusStyle) private var systemStatusStyle = ReaderSystemStatusStyle.compact.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusPosition) private var systemStatusPosition = ReaderOverlayPosition.bottomLeading.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusBottomInset) private var systemStatusBottomInset = 16.0
    @AppStorage(ReaderSettingsKey.usesProgressGlassBackground) private var usesProgressGlassBackground = false
    @AppStorage(ReaderSettingsKey.usesSystemStatusGlassBackground) private var usesSystemStatusGlassBackground = false
    @AppStorage(ReaderSettingsKey.showsReadingListBookToast) private var showsReadingListBookToast = true
    @AppStorage(ReaderSettingsKey.readingListAutoAdvancesAtBoundary) private var readingListAutoAdvancesAtBoundary = true
    @AppStorage(ReaderSettingsKey.visibilityDefaultsVersion) private var visibilityDefaultsVersion = 0

    let detail: ComicDetailInfo
    let initialChapterIndex: Int
    let initialPageIndex: Int
    let ignoresHistoryProgress: Bool
    let service: ComicContentService
    let localChapterImageProvider: ((ComicChapter, Int) async -> [ComicChapterImage])?
    let localChapterCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?
    let historyChapterIndexResolver: (Int) -> Int
    let listContext: ComicReaderListContext?
    let initialToastMessage: String?
    @StateObject private var viewModel: ComicReaderViewModel
    @State private var showsChapters = false
    @State private var hidesReaderUI = false
    @State private var pagedPageIndex = 0
    @State private var continuousScrollPosition = ScrollPosition()
    @State private var continuousScrollBridge = ReaderContinuousScrollBridge()
    @State private var continuousScrollTracker = ReaderContinuousScrollTracker()
    @State private var continuousScrollRestoreTask: Task<Void, Never>?
    @State private var continuousLoadableImageIDs = Set<String>()
    @State private var pagedScrollRestoreToken = UUID()
    @State private var isRestoringPagedScrollPosition = false
    @State private var isAutoPaging = false
    @State private var isAutoPagingTurnInFlight = false
    @State private var autoPagingCommentActionChapterIndex: Int?
    @State private var readerToastMessage: String?
    @State private var readerToastTask: Task<Void, Never>?
    @State private var historyRecordTask: Task<Void, Never>?
    @State private var pendingHistoryRecord: ReaderHistoryRecordSnapshot?
    @State private var progressSelectionContext: ReaderProgressSelectionContext?
    @State private var progressJumpRequest: ReaderProgressJumpRequest?
    @State private var readingDurationSessionStart: Date?
    @State private var didShowInitialToast = false

    init(
        detail: ComicDetailInfo,
        initialChapterIndex: Int = 0,
        initialPageIndex: Int = 0,
        ignoresHistoryProgress: Bool = false,
        service: ComicContentService,
        localChapterImageProvider: ((ComicChapter, Int) async -> [ComicChapterImage])? = nil,
        localChapterCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])? = nil,
        historyChapterIndexResolver: @escaping (Int) -> Int = { $0 },
        listContext: ComicReaderListContext? = nil,
        initialToastMessage: String? = nil
    ) {
        self.detail = detail
        self.initialChapterIndex = initialChapterIndex
        self.initialPageIndex = initialPageIndex
        self.ignoresHistoryProgress = ignoresHistoryProgress
        self.service = service
        self.localChapterImageProvider = localChapterImageProvider
        self.localChapterCommentsProvider = localChapterCommentsProvider
        self.historyChapterIndexResolver = historyChapterIndexResolver
        self.listContext = listContext
        self.initialToastMessage = initialToastMessage
        _viewModel = StateObject(wrappedValue: ComicReaderViewModel(
            detail: detail,
            initialChapterIndex: initialChapterIndex,
            initialPageIndex: initialPageIndex,
            service: service,
            localChapterImageProvider: localChapterImageProvider
        ))
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                readerLoadingContent()
            case .loaded(let images):
                if images.isEmpty {
                    ContentUnavailableView("暂无图片", systemImage: "photo", description: Text("这个章节没有返回可阅读图片"))
                } else {
                    readerContent(images: images)
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
        .background(Color.black)
        .ignoresSafeArea(.container)
        .navigationTitle(viewModel.navigationTitle)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .picaxReaderChrome(hidesNavigationBar: shouldHideNavigationBar, hidesStatusBar: hidesStatusBar)
        .tint(.white)
        .overlay(alignment: readerProgressPosition.alignment) {
            if showsProgressOverlay {
                ReaderProgressOverlay(
                    title: viewModel.progressTitle,
                    progress: viewModel.progress,
                    style: readerProgressStyle,
                    showsPageLabel: showsPageLabel,
                    backgroundOpacity: progressBackgroundOpacity,
                    usesGlassBackground: usesProgressGlassBackground
                )
                .padding(.horizontal, 16)
                .padding(.bottom, progressBottomPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    presentProgressSelection()
                }
                .accessibilityLabel("选择阅读进度")
                .accessibilityAddTraits(progressTapSelectionEnabled ? .isButton : [])
                .allowsHitTesting(progressTapSelectionEnabled)
            }
        }
        .overlay(alignment: readerSystemStatusPosition.alignment) {
            if showsSystemStatusOverlay {
                ReaderSystemStatusOverlay(
                    style: readerSystemStatus,
                    backgroundOpacity: progressBackgroundOpacity,
                    usesGlassBackground: usesSystemStatusGlassBackground
                )
                .padding(readerSystemStatusInsets)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let readerToastMessage {
                ReaderToastView(message: readerToastMessage)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 86)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsSystemStatus)
        .animation(readerChromeAnimation, value: showsReaderUI)
        .animation(.easeInOut(duration: 0.16), value: readerToastMessage)
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    Task {
                        await handlePreviousToolbarNavigation()
                    }
                } label: {
                    Image(systemName: previousNavigationSystemImage)
                }
                .disabled(!canNavigatePrevious)
                .accessibilityLabel(previousNavigationAccessibilityLabel)

                Button {
                    toggleAutoPaging()
                } label: {
                    Image(systemName: isAutoPaging ? "timer.circle.fill" : "timer")
                }
                .accessibilityLabel(isAutoPaging ? "停止自动翻页" : "自动翻页")

                Button {
                    showsChapters = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("章节")

                Button {
                    Task {
                        await handleNextToolbarNavigation()
                    }
                } label: {
                    Image(systemName: nextNavigationSystemImage)
                }
                .disabled(!canNavigateNext)
                .accessibilityLabel(nextNavigationAccessibilityLabel)
            }
        }
        .sheet(isPresented: $showsChapters) {
            ReaderChapterPickerSheet(
                chapters: detail.chapters,
                selectedIndex: viewModel.currentChapterIndex,
                listContext: listContext,
                onSelectReadingListEntry: { entry in
                    listContext?.selectEntry(entry)
                }
            ) { index in
                showsChapters = false
                Task {
                    await viewModel.loadChapter(
                        index: index,
                        pageIndex: 0,
                        account: platformAccounts.account(for: detail.item.platform),
                        force: true,
                        preloadImageCount: boundedPreloadImageCount,
                        preloadDelay: readerPreloadDelay
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $progressSelectionContext) { context in
            ReaderProgressSelectionDialog(context: context) { pageIndex in
                requestProgressJump(to: pageIndex, chapterIndex: context.chapterIndex)
            }
            .presentationDetents([.height(280), .medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            migrateReaderVisibilityDefaultsIfNeeded()
            startReadingDurationSessionIfNeeded()
            showInitialToastIfNeeded()
            await load()
        }
        .onDisappear {
            continuousScrollRestoreTask?.cancel()
            flushPendingHistoryRecord()
            flushReadingDurationSession()
            readerToastTask?.cancel()
            isAutoPaging = false
            isAutoPagingTurnInFlight = false
            autoPagingCommentActionChapterIndex = nil
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                startReadingDurationSessionIfNeeded()
            case .inactive, .background:
                flushPendingHistoryRecord()
                flushReadingDurationSession()
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.currentChapterIndex) { _, _ in
            autoPagingCommentActionChapterIndex = nil
        }
    }

    private var canNavigatePrevious: Bool {
        viewModel.canLoadPreviousChapter || (listContext?.canMovePrevious ?? false)
    }

    private var canNavigateNext: Bool {
        viewModel.canLoadNextChapter || (listContext?.canMoveNext ?? false)
    }

    private var previousNavigationSystemImage: String {
        canMoveToPreviousReadingListEntry ? "backward.end" : "chevron.up"
    }

    private var nextNavigationSystemImage: String {
        canMoveToNextReadingListEntry ? "forward.end" : "chevron.down"
    }

    private var previousNavigationAccessibilityLabel: String {
        canMoveToPreviousReadingListEntry ? "上一本" : "上一章"
    }

    private var nextNavigationAccessibilityLabel: String {
        canMoveToNextReadingListEntry ? "下一本" : "下一章"
    }

    private var canMoveToPreviousReadingListEntry: Bool {
        !viewModel.canLoadPreviousChapter && (listContext?.canMovePrevious ?? false)
    }

    private var canMoveToNextReadingListEntry: Bool {
        !viewModel.canLoadNextChapter && (listContext?.canMoveNext ?? false)
    }

    private func handlePreviousToolbarNavigation() async {
        if viewModel.canLoadPreviousChapter {
            await viewModel.loadPreviousChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
        } else {
            _ = moveReadingList(.previous)
        }
    }

    private func handleNextToolbarNavigation() async {
        if viewModel.canLoadNextChapter {
            await viewModel.loadNextChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
        } else {
            _ = moveReadingList(.next)
        }
    }

    @ViewBuilder
    private func readerLoadingContent() -> some View {
        GeometryReader { geometry in
            LoadingStateView(title: "正在加载章节")
                .frame(width: geometry.size.width, height: geometry.size.height)
                .readerInteractionGesture(
                    size: geometry.size,
                    mode: readerUIToggleMode,
                    tapPagingEnabled: false,
                    tapPagingEdgePercent: boundedTapPagingEdgePercent,
                    tapPagingInverted: tapPagingInverted,
                    doubleTapZoomEnabled: effectiveDoubleTapZoomEnabled,
                    readingMode: readerReadingMode,
                    toggleUI: { toggleReaderUI() },
                    turnPage: { _ in }
                )
        }
        .ignoresSafeArea(.container)
    }

    @ViewBuilder
    private func readerContent(images: [ComicChapterImage]) -> some View {
        switch readerReadingMode {
        case .topToBottomContinuous:
            continuousReaderContent(images: images)
        case .topToBottom:
            verticalPagedReaderContent(images: images)
        case .leftToRight, .rightToLeft:
            horizontalPagedReaderContent(images: images)
        }
    }

    @ViewBuilder
    private func continuousReaderContent(images: [ComicChapterImage]) -> some View {
        GeometryReader { geometry in
            let targetPixelWidth = readerTargetPixelWidth(for: geometry.size.width)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: CGFloat(imageSpacing)) {
                        ForEach(images.indices, id: \.self) { index in
                            ReaderImageView(
                                image: images[index],
                                retryCount: boundedImageRetryCount,
                                retryInterval: boundedImageRetryInterval,
                                targetPixelWidth: targetPixelWidth,
                                displayWidth: geometry.size.width,
                                containerSize: nil,
                                isLoadAllowed: continuousLoadableImageIDs.contains(images[index].urlString),
                                zoomConfiguration: readerZoomConfiguration,
                                dimsImage: dimsReaderImages,
                                onAspectRatioResolved: { aspectRatio in
                                    if let adjustedY = continuousScrollTracker.updateAspectRatio(
                                        aspectRatio,
                                        for: index,
                                        images: images,
                                        displayWidth: geometry.size.width,
                                        imageSpacing: CGFloat(imageSpacing),
                                        firstImageTopPadding: CGFloat(firstImageTopPadding),
                                        lastImageBottomPadding: CGFloat(lastImageBottomPadding)
                                    ) {
                                        restoreContinuousScrollPosition(
                                            ReaderContinuousScrollSnapshot(
                                                chapterIndex: viewModel.currentChapterIndex,
                                                scrollY: adjustedY
                                            )
                                        )
                                    }
                                    updateContinuousLoadableImages(
                                        images: images,
                                        displayWidth: geometry.size.width,
                                        fallbackViewportHeight: geometry.size.height
                                    )
                                    syncContinuousVisiblePage(
                                        images: images,
                                        displayWidth: geometry.size.width,
                                        fallbackViewportHeight: geometry.size.height,
                                        targetPixelWidth: targetPixelWidth
                                    )
                                }
                            )
                                .padding(.top, index == images.startIndex ? CGFloat(firstImageTopPadding) : 0)
                                .padding(.bottom, index == images.index(before: images.endIndex) ? CGFloat(lastImageBottomPadding) : 0)
                                .id(readerPageID(index))
                        }
                        if shouldShowChapterCommentsAtEnd,
                           let chapter = currentChapter {
                            ReaderChapterCommentsView(
                                item: detail.item,
                                chapter: chapter,
                                chapterIndex: viewModel.currentChapterIndex,
                                service: service,
                                account: platformAccounts.account(for: detail.item.platform),
                                localCommentsProvider: localChapterCommentsProvider
                            )
                            .id(readerCommentsPageID())
                            .padding(.horizontal, 10)
                            .onAppear {
                                handleContinuousAutoPagingEnteredComments(targetPixelWidth: targetPixelWidth)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                .background(Color.black)
                .ignoresSafeArea(.container)
                .scrollPosition($continuousScrollPosition)
                .readerContinuousScrollBridge(continuousScrollBridge)
                .onChange(of: continuousScrollPosition) { _, newValue in
                    if let point = newValue.point {
                        continuousScrollTracker.updateScrollY(point.y)
                    }
                    updateContinuousLoadableImages(
                        images: images,
                        displayWidth: geometry.size.width,
                        fallbackViewportHeight: geometry.size.height
                    )
                    syncContinuousVisiblePage(
                        images: images,
                        displayWidth: geometry.size.width,
                        fallbackViewportHeight: geometry.size.height,
                        targetPixelWidth: targetPixelWidth
                    )
                }
                .onScrollGeometryChange(for: ReaderScrollMetrics.self) { geometry in
                    ReaderScrollMetrics(
                        offsetY: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        visibleHeight: geometry.visibleRect.height
                    )
                } action: { _, metrics in
                    continuousScrollTracker.updateMetrics(metrics)
                    updateContinuousLoadableImages(
                        images: images,
                        displayWidth: geometry.size.width,
                        fallbackViewportHeight: metrics.visibleHeight > 0 ? metrics.visibleHeight : geometry.size.height
                    )
                    syncContinuousVisiblePage(
                        images: images,
                        displayWidth: geometry.size.width,
                        fallbackViewportHeight: metrics.visibleHeight > 0 ? metrics.visibleHeight : geometry.size.height,
                        targetPixelWidth: targetPixelWidth
                    )
                }
                .readerInteractionGesture(
                    size: geometry.size,
                    mode: readerUIToggleMode,
                    tapPagingEnabled: tapPagingEnabled,
                    tapPagingEdgePercent: boundedTapPagingEdgePercent,
                    tapPagingInverted: tapPagingInverted,
                    doubleTapZoomEnabled: effectiveDoubleTapZoomEnabled,
                    readingMode: readerReadingMode,
                    toggleUI: { toggleReaderUI() },
                    turnPage: { direction in
                        Task {
                            await handleContinuousTapPage(
                                direction,
                                images: images,
                                viewportHeight: geometry.size.height,
                                targetPixelWidth: targetPixelWidth,
                                proxy: proxy
                            )
                        }
                    }
                )
                .readerAutoPaging(isEnabled: isAutoPaging, interval: boundedAutoPageInterval) {
                    handleContinuousAutoPageTick(
                        images: images,
                        viewportHeight: geometry.size.height,
                        targetPixelWidth: targetPixelWidth
                    )
                }
                .onAppear {
                    resetContinuousImageState()
                    continuousScrollTracker.reset()
                    focusContinuousLoadableImage(viewModel.currentPageIndex, images: images)
                    updateReadingPage(viewModel.currentPageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth, force: true)
                    scrollToInitialPage(proxy: proxy)
                }
                .onChange(of: viewModel.currentChapterIndex) { _, _ in
                    resetContinuousImageState()
                    continuousScrollTracker.reset()
                    scrollContinuous(toY: 0, animated: false)
                    focusContinuousLoadableImage(viewModel.currentPageIndex, images: images)
                    scrollToInitialPage(proxy: proxy)
                }
                .onChange(of: progressJumpRequest) { _, request in
                    handleProgressJumpRequest(
                        request,
                        images: images,
                        targetPixelWidth: targetPixelWidth
                    ) { pageIndex in
                        focusContinuousLoadableImage(pageIndex, images: images)
                        scrollToPage(pageIndex, proxy: proxy, animated: true)
                    }
                }
                .readerContinuousZoom(
                    configuration: readerZoomConfiguration,
                    resetID: continuousZoomResetID,
                    allowsInteraction: allowsContinuousZoom(images: images)
                )
            }
        }
        .ignoresSafeArea(.container)
    }

    @ViewBuilder
    private func horizontalPagedReaderContent(images: [ComicChapterImage]) -> some View {
        GeometryReader { geometry in
            let targetPixelWidth = readerTargetPixelWidth(for: geometry.size.width)
            ScrollViewReader { proxy in
                horizontalPagedScroll(images: images, size: geometry.size, targetPixelWidth: targetPixelWidth)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .environment(\.layoutDirection, readerReadingMode == .rightToLeft ? .rightToLeft : .leftToRight)
                    .ignoresSafeArea(.container)
                    .readerInteractionGesture(
                        size: geometry.size,
                        mode: readerUIToggleMode,
                        tapPagingEnabled: tapPagingEnabled,
                        tapPagingEdgePercent: boundedTapPagingEdgePercent,
                        tapPagingInverted: tapPagingInverted,
                        doubleTapZoomEnabled: effectiveDoubleTapZoomEnabled,
                        readingMode: readerReadingMode,
                        toggleUI: { toggleReaderUI() },
                        turnPage: { direction in
                            Task {
                                await turnPage(direction, images: images, targetPixelWidth: targetPixelWidth) { pageIndex in
                                    setPagedPageIndex(pageIndex, animated: false)
                                    if pageIndex == images.count, pagedCommentPageIndex(for: images) != nil {
                                        scrollToComments(proxy: proxy, anchor: .leading, animated: true)
                                    } else {
                                        scrollToPage(pageIndex, proxy: proxy, anchor: .leading, animated: true)
                                    }
                                }
                            }
                        }
                    )
                    .readerAutoPaging(isEnabled: isAutoPaging, interval: boundedAutoPageInterval) {
                        handleAutoPageTick(images: images, targetPixelWidth: targetPixelWidth) { pageIndex in
                            setPagedPageIndex(pageIndex, animated: false)
                            if pageIndex == images.count, pagedCommentPageIndex(for: images) != nil {
                                scrollToComments(proxy: proxy, anchor: .leading, animated: true)
                            } else {
                                scrollToPage(pageIndex, proxy: proxy, anchor: .leading, animated: true)
                            }
                        }
                    }
                    .onAppear {
                        let pageIndex = syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToHorizontalPagedSelection(pageIndex, proxy: proxy)
                    }
                    .onChange(of: viewModel.currentChapterIndex) { _, _ in
                        let pageIndex = syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToHorizontalPagedSelection(pageIndex, proxy: proxy)
                    }
                    .onChange(of: pagedPageIndex) { _, newValue in
                        if images.indices.contains(newValue) {
                            updateReadingPage(newValue, totalPages: images.count, targetPixelWidth: targetPixelWidth)
                        }
                    }
                    .onChange(of: progressJumpRequest) { _, request in
                        handleProgressJumpRequest(
                            request,
                            images: images,
                            targetPixelWidth: targetPixelWidth
                        ) { pageIndex in
                            setPagedPageIndex(pageIndex, animated: false)
                            scrollToPage(pageIndex, proxy: proxy, anchor: .leading, animated: true)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func horizontalPagedScroll(images: [ComicChapterImage], size: CGSize, targetPixelWidth: Int?) -> some View {
        let scroll = ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(images.indices, id: \.self) { index in
                    ReaderImageView(
                        image: images[index],
                        retryCount: boundedImageRetryCount,
                        retryInterval: boundedImageRetryInterval,
                        targetPixelWidth: targetPixelWidth,
                        containerSize: size,
                        isLoadAllowed: isImageInPreloadWindow(index, around: pagedPageIndex, imageCount: images.count),
                        zoomConfiguration: readerZoomConfiguration,
                        dimsImage: dimsReaderImages
                    )
                    .frame(width: size.width, height: size.height)
                    .id(readerPageID(index))
                    .onAppear {
                        guard !isRestoringPagedScrollPosition else { return }
                        if pagedPageIndex != index {
                            pagedPageIndex = index
                        }
                    }
                }
                if shouldShowChapterCommentsAtEnd,
                   let chapter = currentChapter {
                    ReaderChapterCommentsView(
                        item: detail.item,
                        chapter: chapter,
                        chapterIndex: viewModel.currentChapterIndex,
                        service: service,
                        account: platformAccounts.account(for: detail.item.platform),
                        localCommentsProvider: localChapterCommentsProvider
                    )
                    .frame(width: size.width, height: size.height)
                    .id(readerCommentsPageID())
                    .onAppear {
                        guard !isRestoringPagedScrollPosition else { return }
                        if pagedPageIndex != images.count {
                            pagedPageIndex = images.count
                        }
                    }
                }
            }
            .modifier(ReaderScrollTargetLayoutModifier())
        }

        scroll
            .modifier(ReaderPagingScrollModifier())
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { oldValue, newValue in
                syncPagedScrollOffset(
                    oldValue: oldValue,
                    newValue: newValue,
                    pageExtent: size.width,
                    images: images,
                    targetPixelWidth: targetPixelWidth
                )
            }
    }

    @ViewBuilder
    private func verticalPagedReaderContent(images: [ComicChapterImage]) -> some View {
        GeometryReader { geometry in
            let targetPixelWidth = readerTargetPixelWidth(for: geometry.size.width)
            ScrollViewReader { proxy in
                verticalPagedScroll(images: images, size: geometry.size, targetPixelWidth: targetPixelWidth)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .readerInteractionGesture(
                        size: geometry.size,
                        mode: readerUIToggleMode,
                        tapPagingEnabled: tapPagingEnabled,
                        tapPagingEdgePercent: boundedTapPagingEdgePercent,
                        tapPagingInverted: tapPagingInverted,
                        doubleTapZoomEnabled: effectiveDoubleTapZoomEnabled,
                        readingMode: readerReadingMode,
                        toggleUI: { toggleReaderUI() },
                        turnPage: { direction in
                            Task {
                                await turnPage(direction, images: images, targetPixelWidth: targetPixelWidth) { pageIndex in
                                    setPagedPageIndex(pageIndex, animated: false)
                                    if pageIndex == images.count, pagedCommentPageIndex(for: images) != nil {
                                        scrollToComments(proxy: proxy, animated: true)
                                    } else {
                                        scrollToPage(pageIndex, proxy: proxy, animated: true)
                                    }
                                }
                            }
                        }
                    )
                    .readerAutoPaging(isEnabled: isAutoPaging, interval: boundedAutoPageInterval) {
                        handleAutoPageTick(images: images, targetPixelWidth: targetPixelWidth) { pageIndex in
                            setPagedPageIndex(pageIndex, animated: false)
                            if pageIndex == images.count, pagedCommentPageIndex(for: images) != nil {
                                scrollToComments(proxy: proxy, animated: true)
                            } else {
                                scrollToPage(pageIndex, proxy: proxy, animated: true)
                            }
                        }
                    }
                    .onAppear {
                        let pageIndex = syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToPagedSelection(pageIndex, proxy: proxy)
                    }
                    .onChange(of: viewModel.currentChapterIndex) { _, _ in
                        let pageIndex = syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToPagedSelection(pageIndex, proxy: proxy)
                    }
                    .onChange(of: pagedPageIndex) { _, newValue in
                        if images.indices.contains(newValue) {
                            updateReadingPage(newValue, totalPages: images.count, targetPixelWidth: targetPixelWidth)
                        }
                    }
	                    .onChange(of: progressJumpRequest) { _, request in
	                        handleProgressJumpRequest(
	                            request,
	                            images: images,
	                            targetPixelWidth: targetPixelWidth
	                        ) { pageIndex in
	                            setPagedPageIndex(pageIndex, animated: false)
	                            scrollToPage(pageIndex, proxy: proxy, animated: true)
	                        }
	                    }
            }
        }
        .ignoresSafeArea(.container)
    }

    @ViewBuilder
    private func verticalPagedScroll(images: [ComicChapterImage], size: CGSize, targetPixelWidth: Int?) -> some View {
        let scroll = ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(images.indices, id: \.self) { index in
                    ReaderImageView(
                        image: images[index],
                        retryCount: boundedImageRetryCount,
                        retryInterval: boundedImageRetryInterval,
                        targetPixelWidth: targetPixelWidth,
                        containerSize: size,
                        isLoadAllowed: isImageInPreloadWindow(index, around: pagedPageIndex, imageCount: images.count),
                        zoomConfiguration: readerZoomConfiguration,
                        dimsImage: dimsReaderImages
                    )
                        .frame(width: size.width, height: size.height)
                        .id(readerPageID(index))
                        .onAppear {
                            guard !isRestoringPagedScrollPosition else { return }
                            if pagedPageIndex != index {
                                pagedPageIndex = index
                            }
                        }
                }
                if shouldShowChapterCommentsAtEnd,
                   let chapter = currentChapter {
                    ReaderChapterCommentsView(
                        item: detail.item,
                        chapter: chapter,
                        chapterIndex: viewModel.currentChapterIndex,
                        service: service,
                        account: platformAccounts.account(for: detail.item.platform),
                        localCommentsProvider: localChapterCommentsProvider
                    )
                    .frame(width: size.width, height: size.height)
                    .id(readerCommentsPageID())
                    .onAppear {
                        guard !isRestoringPagedScrollPosition else { return }
                        if pagedPageIndex != images.count {
                            pagedPageIndex = images.count
                        }
                    }
                }
            }
            .modifier(ReaderScrollTargetLayoutModifier())
        }

        scroll
            .modifier(ReaderPagingScrollModifier())
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                syncPagedScrollOffset(
                    oldValue: oldValue,
                    newValue: newValue,
                    pageExtent: size.height,
                    images: images,
                    targetPixelWidth: targetPixelWidth
                )
            }
    }

    private func load(force: Bool = false) async {
        let record = readingHistory.record(for: detail.item)
        let progress = ignoresHistoryProgress ? nil : record?.progress
        let chapterIndex = progress?.status == .viewed ? initialChapterIndex : progress?.chapterIndex ?? initialChapterIndex
        let pageIndex = progress?.status == .viewed ? initialPageIndex : progress?.pageIndex ?? initialPageIndex
        await viewModel.loadChapter(
            index: chapterIndex,
            pageIndex: pageIndex,
            account: platformAccounts.account(for: detail.item.platform),
            force: force,
            preloadImageCount: boundedPreloadImageCount,
            preloadDelay: readerPreloadDelay
        )
    }

    private func scrollToInitialPage(proxy: ScrollViewProxy) {
        let pageIndex = max(viewModel.requestedPageIndex, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            scrollToPage(pageIndex, proxy: proxy, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                continuousScrollTracker.setReady()
            }
        }
    }

    private func scrollToPage(
        _ pageIndex: Int,
        proxy: ScrollViewProxy,
        anchor: UnitPoint = .top,
        animated: Bool
    ) {
        if animated {
            withAnimation(readerPageTurnAnimation) {
                proxy.scrollTo(readerPageID(pageIndex), anchor: anchor)
            }
        } else {
            proxy.scrollTo(readerPageID(pageIndex), anchor: anchor)
        }
    }

    private func scrollToComments(
        proxy: ScrollViewProxy,
        anchor: UnitPoint = .top,
        animated: Bool
    ) {
        if animated {
            withAnimation(readerPageTurnAnimation) {
                proxy.scrollTo(readerCommentsPageID(), anchor: anchor)
            }
        } else {
            proxy.scrollTo(readerCommentsPageID(), anchor: anchor)
        }
    }

    private func scrollContinuous(toY y: CGFloat, animated: Bool) {
        let targetY = max(y, 0)
        _ = animated && continuousScrollBridge.scroll(toY: targetY, animated: true)

        let update = {
            continuousScrollPosition.scrollTo(y: targetY)
        }
        if animated {
            withAnimation(readerPageTurnAnimation, update)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
        continuousScrollTracker.updateScrollY(targetY)
    }

    private func setPagedPageIndex(_ pageIndex: Int, animated: Bool) {
        if animated {
            withAnimation(readerPageTurnAnimation) {
                pagedPageIndex = pageIndex
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pagedPageIndex = pageIndex
            }
        }
    }

    private func readerPageID(_ index: Int) -> String {
        "page-\(viewModel.currentChapterIndex)-\(index)"
    }

    private var continuousZoomResetID: String {
        "\(detail.item.platform.rawValue)-\(detail.item.id)-\(viewModel.currentChapterIndex)"
    }

    private func readerCommentsPageID() -> String {
        "comments-\(viewModel.currentChapterIndex)"
    }

    private func syncPagedSelection(images: [ComicChapterImage], targetPixelWidth: Int?) -> Int {
        let pageIndex = min(max(viewModel.requestedPageIndex, 0), max(images.count - 1, 0))
        pagedPageIndex = pageIndex
        updateReadingPage(pageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth, force: true)
        return pageIndex
    }

    private func syncPagedScrollOffset(
        oldValue: CGFloat,
        newValue: CGFloat,
        pageExtent: CGFloat,
        images: [ComicChapterImage],
        targetPixelWidth: Int?
    ) {
        guard pageExtent.isFinite, pageExtent > 0, !images.isEmpty, !isRestoringPagedScrollPosition else { return }
        let rawPage = max(newValue / pageExtent, 0)
        let incomingPage: Int
        if newValue < oldValue {
            incomingPage = Int(floor(rawPage))
        } else if newValue > oldValue {
            incomingPage = Int(ceil(rawPage))
        } else {
            incomingPage = Int(round(rawPage))
        }
        let pageIndex = min(max(incomingPage, 0), images.count - 1)
        guard pageIndex != pagedPageIndex else { return }

        pagedPageIndex = pageIndex
        updateReadingPage(pageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth)
    }

    private func scrollToPagedSelection(_ pageIndex: Int, proxy: ScrollViewProxy) {
        restorePagedScrollPosition(to: pageIndex, proxy: proxy, anchor: .top)
    }

    private func scrollToHorizontalPagedSelection(_ pageIndex: Int, proxy: ScrollViewProxy) {
        restorePagedScrollPosition(to: pageIndex, proxy: proxy, anchor: .leading)
    }

    private func restorePagedScrollPosition(to pageIndex: Int, proxy: ScrollViewProxy, anchor: UnitPoint) {
        let token = UUID()
        pagedScrollRestoreToken = token
        isRestoringPagedScrollPosition = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard pagedScrollRestoreToken == token else { return }
            scrollToPage(pageIndex, proxy: proxy, anchor: anchor, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                guard pagedScrollRestoreToken == token else { return }
                isRestoringPagedScrollPosition = false
            }
        }
    }

    private func handleAutoPageTick(
        images: [ComicChapterImage],
        targetPixelWidth: Int?,
        selectPage: @escaping (Int) -> Void
    ) {
        guard isAutoPaging, !isAutoPagingTurnInFlight, !showsChapters else { return }
        isAutoPagingTurnInFlight = true
        Task {
            if await handlePagedAutoPagingAtCommentBoundary(images: images, selectPage: selectPage) {
                isAutoPagingTurnInFlight = false
                return
            }

            let didTurn = await turnPage(
                .next,
                images: images,
                targetPixelWidth: targetPixelWidth,
                allowsChapterTurn: autoPagingTurnsChapter,
                selectPage: selectPage
            )
            isAutoPagingTurnInFlight = false
            if !didTurn {
                stopAutoPaging(toast: "已到最后一页")
            }
        }
    }

    @MainActor
    private func handlePagedAutoPagingAtCommentBoundary(
        images: [ComicChapterImage],
        selectPage: @escaping (Int) -> Void
    ) async -> Bool {
        guard let commentPageIndex = pagedCommentPageIndex(for: images) else {
            return false
        }

        let currentPage = min(max(pagedPageIndex, 0), commentPageIndex)
        guard currentPage >= max(images.count - 1, 0) else {
            return false
        }

        if autoPagingTurnsChapter, viewModel.canLoadNextChapter {
            await viewModel.loadNextChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
            return true
        }

        if autoPagingTurnsChapter, moveReadingList(.next, respectsAutoAdvanceSetting: true) {
            return true
        }

	        if currentPage != commentPageIndex {
	            selectPage(commentPageIndex)
	        }
        stopAutoPaging(toast: "已到最后一页")
        return true
    }

    private func handleContinuousAutoPageTick(
        images: [ComicChapterImage],
        viewportHeight: CGFloat,
        targetPixelWidth: Int?
    ) {
        guard isAutoPaging, !isAutoPagingTurnInFlight, !showsChapters else { return }
        guard viewportHeight.isFinite, viewportHeight > 0 else { return }

        isAutoPagingTurnInFlight = true
        let distance = viewportHeight * CGFloat(boundedAutoPageDistancePercent) / 100
        let maxY = continuousScrollTracker.maxScrollY(fallbackViewportHeight: viewportHeight)
        let targetY = min(continuousScrollTracker.scrollY + max(distance, 1), maxY)

        scrollContinuous(toY: targetY, animated: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            isAutoPagingTurnInFlight = false
            guard isAutoPaging else { return }
            if reachedContinuousBottom(in: images) {
                if shouldShowChapterCommentsAtEnd {
                    await finishAutoPagingAtChapterEnd(targetPixelWidth: targetPixelWidth)
                    return
                }
                let didTurn = await turnPage(.next, images: images, targetPixelWidth: targetPixelWidth, allowsChapterTurn: autoPagingTurnsChapter) { pageIndex in
                    continuousScrollTracker.reset()
                    scrollContinuous(toY: 0, animated: false)
                    updateReadingPage(pageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth)
                }
                if !didTurn {
                    stopAutoPaging(toast: "已到最后一页")
                }
            }
        }
    }

    private func handleContinuousAutoPagingEnteredComments(targetPixelWidth: Int?) {
        guard isAutoPaging,
              readerReadingMode == .topToBottomContinuous,
              autoPagingCommentActionChapterIndex != viewModel.currentChapterIndex else {
            return
        }
        autoPagingCommentActionChapterIndex = viewModel.currentChapterIndex

        Task { @MainActor in
            await finishAutoPagingAtChapterEnd(targetPixelWidth: targetPixelWidth)
        }
    }

    @MainActor
    private func finishAutoPagingAtChapterEnd(targetPixelWidth: Int?) async {
        if autoPagingTurnsChapter, viewModel.canLoadNextChapter {
            isAutoPagingTurnInFlight = true
            await viewModel.loadNextChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
            continuousScrollTracker.reset()
            scrollContinuous(toY: 0, animated: false)
            isAutoPagingTurnInFlight = false
            return
        }

        if autoPagingTurnsChapter, moveReadingList(.next, respectsAutoAdvanceSetting: true) {
            isAutoPagingTurnInFlight = false
            return
        }

        stopAutoPaging(toast: "已到最后一页")
    }

    private func handleContinuousTapPage(
        _ direction: ReaderPageTurnDirection,
        images: [ComicChapterImage],
        viewportHeight: CGFloat,
        targetPixelWidth: Int?,
        proxy: ScrollViewProxy
    ) async {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return }
        let currentY = continuousScrollTracker.effectiveScrollY(fallback: continuousScrollPosition.point?.y)
        let maxY = continuousScrollTracker.maxScrollY(fallbackViewportHeight: viewportHeight)
        let distance = max(viewportHeight * CGFloat(boundedTapPagingDistancePercent) / 100, 1)

        switch direction {
        case .previous:
            if currentY <= 1 {
                _ = await turnPage(.previous, images: images, targetPixelWidth: targetPixelWidth, selectPage: { pageIndex in
                    scrollToPage(pageIndex, proxy: proxy, animated: true)
                })
                return
            }
            let targetY = max(currentY - distance, 0)
            scrollContinuous(toY: targetY, animated: true)
        case .next:
            if currentY >= maxY - 4 {
                _ = await turnPage(.next, images: images, targetPixelWidth: targetPixelWidth, selectPage: { pageIndex in
                    scrollToPage(pageIndex, proxy: proxy, animated: true)
                })
                return
            }
            let targetY = min(currentY + distance, maxY)
            scrollContinuous(toY: targetY, animated: true)
        }
    }

    @discardableResult
    private func turnPage(
        _ direction: ReaderPageTurnDirection,
        images: [ComicChapterImage],
        targetPixelWidth: Int?,
        allowsChapterTurn: Bool = true,
        selectPage: @escaping (Int) -> Void
    ) async -> Bool {
        guard !images.isEmpty else { return false }
        let commentPageIndex = pagedCommentPageIndex(for: images)
        let maxPageIndex = commentPageIndex ?? max(images.count - 1, 0)
        let currentCandidate = readerReadingMode == .topToBottomContinuous ? viewModel.currentPageIndex : pagedPageIndex
        let currentPage = min(max(currentCandidate, 0), maxPageIndex)
        let nextPage = direction == .next ? currentPage + 1 : currentPage - 1

        if images.indices.contains(nextPage) {
            selectPage(nextPage)
            updateReadingPage(nextPage, totalPages: images.count, targetPixelWidth: targetPixelWidth)
            return true
        }

        if let commentPageIndex, nextPage == commentPageIndex {
            selectPage(commentPageIndex)
            return true
        }

        guard allowsChapterTurn else { return false }
        switch direction {
        case .next:
            guard viewModel.canLoadNextChapter else {
                return moveReadingList(.next, respectsAutoAdvanceSetting: true)
            }
            await viewModel.loadNextChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
            return true
        case .previous:
            guard viewModel.canLoadPreviousChapter else {
                return moveReadingList(.previous, respectsAutoAdvanceSetting: true)
            }
            await viewModel.loadPreviousChapter(
                account: platformAccounts.account(for: detail.item.platform),
                preloadImageCount: boundedPreloadImageCount,
                preloadDelay: readerPreloadDelay
            )
            return true
        }
    }

    @MainActor
    private func moveReadingList(_ direction: ReaderPageTurnDirection, respectsAutoAdvanceSetting: Bool = false) -> Bool {
        guard let listContext else { return false }
        if respectsAutoAdvanceSetting, !readingListAutoAdvancesAtBoundary {
            return false
        }
        switch direction {
        case .previous:
            guard listContext.canMovePrevious else { return false }
            isAutoPaging = false
            listContext.movePrevious()
            return true
        case .next:
            guard listContext.canMoveNext else { return false }
            listContext.moveNext()
            return true
        }
    }

    private func updateReadingPage(_ index: Int, totalPages: Int, targetPixelWidth: Int?, force: Bool = false) {
        let didChange = viewModel.updateCurrentPage(index)
        guard didChange || force else { return }
        viewModel.scheduleImagePreload(
            aroundPage: index,
            count: boundedPreloadImageCount,
            delay: readerPreloadDelay,
            targetPixelWidth: targetPixelWidth
        )
        scheduleReadingHistoryRecord(pageIndex: index, totalPages: totalPages)
    }

    private func presentProgressSelection() {
        guard progressTapSelectionEnabled,
              case .loaded(let images) = viewModel.state,
              !images.isEmpty else {
            return
        }

        let pageIndex = min(max(viewModel.currentPageIndex, 0), images.count - 1)
        progressSelectionContext = ReaderProgressSelectionContext(
            chapterIndex: viewModel.currentChapterIndex,
            chapterTitle: viewModel.navigationTitle,
            pageIndex: pageIndex,
            pageCount: images.count
        )
    }

    private func requestProgressJump(to pageIndex: Int, chapterIndex: Int) {
        progressJumpRequest = ReaderProgressJumpRequest(
            chapterIndex: chapterIndex,
            pageIndex: pageIndex
        )
    }

    private func handleProgressJumpRequest(
        _ request: ReaderProgressJumpRequest?,
        images: [ComicChapterImage],
        targetPixelWidth: Int?,
        performJump: (Int) -> Void
    ) {
        guard let request else { return }
        defer {
            if progressJumpRequest?.id == request.id {
                progressJumpRequest = nil
            }
        }
        guard request.chapterIndex == viewModel.currentChapterIndex,
              !images.isEmpty else {
            return
        }

        let pageIndex = min(max(request.pageIndex, 0), images.count - 1)
        performJump(pageIndex)
        updateReadingPage(pageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth, force: true)
    }

    private func syncContinuousVisiblePage(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        fallbackViewportHeight: CGFloat,
        targetPixelWidth: Int?
    ) {
        guard readerReadingMode == .topToBottomContinuous,
              let pageIndex = continuousScrollTracker.visiblePageIndex(
                images: images,
                displayWidth: displayWidth,
                imageSpacing: CGFloat(imageSpacing),
                firstImageTopPadding: CGFloat(firstImageTopPadding),
                lastImageBottomPadding: CGFloat(lastImageBottomPadding),
                fallbackViewportHeight: fallbackViewportHeight
              ) else {
            return
        }
        updateReadingPage(pageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth)
    }

    private func updateContinuousLoadableImages(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        fallbackViewportHeight: CGFloat
    ) {
        let indices = continuousScrollTracker.visiblePageIndices(
            images: images,
            displayWidth: displayWidth,
            imageSpacing: CGFloat(imageSpacing),
            firstImageTopPadding: CGFloat(firstImageTopPadding),
            lastImageBottomPadding: CGFloat(lastImageBottomPadding),
            fallbackViewportHeight: fallbackViewportHeight
        )
        guard !indices.isEmpty else {
            if continuousLoadableImageIDs.isEmpty {
                focusContinuousLoadableImage(viewModel.currentPageIndex, images: images)
            }
            return
        }

        let loadableIndices = expandedPreloadIndices(around: indices, imageCount: images.count)
        let imageIDs = Set(loadableIndices.map { images[$0].urlString })
        guard continuousLoadableImageIDs != imageIDs else { return }
        continuousLoadableImageIDs = imageIDs
    }

    private func focusContinuousLoadableImage(_ pageIndex: Int, images: [ComicChapterImage]) {
        guard !images.isEmpty else {
            continuousLoadableImageIDs.removeAll(keepingCapacity: true)
            return
        }

        let imageIDs = Set(preloadIndices(around: pageIndex, imageCount: images.count).map { images[$0].urlString })
        guard continuousLoadableImageIDs != imageIDs else { return }
        continuousLoadableImageIDs = imageIDs
    }

    private func isImageInPreloadWindow(_ index: Int, around pageIndex: Int, imageCount: Int) -> Bool {
        preloadIndices(around: pageIndex, imageCount: imageCount).contains(index)
    }

    private func expandedPreloadIndices(around indices: Set<Int>, imageCount: Int) -> Set<Int> {
        guard imageCount > 0 else { return [] }
        var result = Set<Int>()
        for index in indices {
            result.formUnion(preloadIndices(around: index, imageCount: imageCount))
        }
        return result
    }

    private func preloadIndices(around pageIndex: Int, imageCount: Int) -> Set<Int> {
        guard imageCount > 0 else { return [] }
        let boundedIndex = min(max(pageIndex, 0), imageCount - 1)
        let radius = boundedPreloadImageCount
        let startIndex = max(boundedIndex - radius, 0)
        let endIndex = min(boundedIndex + radius, imageCount - 1)
        return Set(startIndex...endIndex)
    }

    private func allowsContinuousZoom(images: [ComicChapterImage]) -> Bool {
        guard readerReadingMode == .topToBottomContinuous,
              !images.isEmpty else {
            return true
        }

        let pageIndex = min(max(viewModel.currentPageIndex, 0), images.count - 1)
        guard images.indices.contains(pageIndex) else { return true }
        return continuousLoadableImageIDs.contains(images[pageIndex].urlString)
    }

    private func resetContinuousImageState() {
        continuousLoadableImageIDs.removeAll(keepingCapacity: true)
    }

    private func restoreContinuousScrollPosition(_ snapshot: ReaderContinuousScrollSnapshot) {
        guard readerReadingMode == .topToBottomContinuous,
              snapshot.chapterIndex == viewModel.currentChapterIndex else {
            return
        }

        let scrollY = max(snapshot.scrollY, 0)
        continuousScrollRestoreTask?.cancel()
        scrollContinuous(toY: scrollY, animated: false)
        continuousScrollRestoreTask = Task { @MainActor [snapshot] in
            let delays: [UInt64] = [70_000_000, 180_000_000, 320_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      readerReadingMode == .topToBottomContinuous,
                      snapshot.chapterIndex == viewModel.currentChapterIndex else {
                    return
                }
                let scrollY = max(snapshot.scrollY, 0)
                scrollContinuous(toY: scrollY, animated: false)
            }
            continuousScrollRestoreTask = nil
        }
    }

    private func readerTargetPixelWidth(for width: CGFloat) -> Int? {
        guard width.isFinite, width > 0, displayScale > 0 else { return nil }
        return max(Int((width * displayScale).rounded(.up)), 1)
    }

    private func scheduleReadingHistoryRecord(pageIndex: Int, totalPages: Int) {
        let snapshot = ReaderHistoryRecordSnapshot(
            item: detail.item,
            chapterIndex: historyChapterIndexResolver(viewModel.currentChapterIndex),
            pageIndex: pageIndex,
            totalPages: totalPages,
            totalChapters: detail.chapters.count
        )
        pendingHistoryRecord = snapshot
        historyRecordTask?.cancel()
        historyRecordTask = Task { [snapshot] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistPendingHistoryRecord(matching: snapshot)
            }
        }
    }

    private func flushPendingHistoryRecord() {
        historyRecordTask?.cancel()
        historyRecordTask = nil
        guard let pendingHistoryRecord else { return }
        persistHistoryRecord(pendingHistoryRecord)
        self.pendingHistoryRecord = nil
    }

    private func persistPendingHistoryRecord(matching snapshot: ReaderHistoryRecordSnapshot) {
        guard pendingHistoryRecord == snapshot else { return }
        persistHistoryRecord(snapshot)
        pendingHistoryRecord = nil
        historyRecordTask = nil
    }

    private func persistHistoryRecord(_ snapshot: ReaderHistoryRecordSnapshot) {
        readingHistory.recordReading(
            item: snapshot.item,
            chapterIndex: snapshot.chapterIndex,
            pageIndex: snapshot.pageIndex,
            totalPages: snapshot.totalPages,
            totalChapters: snapshot.totalChapters
        )
    }

    private func startReadingDurationSessionIfNeeded() {
        guard scenePhase == .active, readingDurationSessionStart == nil else { return }
        readingDurationSessionStart = Date()
    }

    private func flushReadingDurationSession() {
        guard let startedAt = readingDurationSessionStart else { return }
        readingDurationSessionStart = nil
        readingDuration.record(item: detail.item, seconds: Date().timeIntervalSince(startedAt))
    }

    private var readerProgressStyle: ReaderProgressStyle {
        ReaderProgressStyle(rawValue: progressStyle) ?? .circular
    }

    private var readerProgressPosition: ReaderProgressPosition {
        ReaderProgressPosition(rawValue: progressPosition) ?? .trailing
    }

    private var readerSystemStatus: ReaderSystemStatusStyle {
        ReaderSystemStatusStyle(rawValue: systemStatusStyle) ?? .compact
    }

    private var readerSystemStatusPosition: ReaderOverlayPosition {
        ReaderOverlayPosition(rawValue: systemStatusPosition) ?? .bottomLeading
    }

    private var boundedPreloadImageCount: Int {
        min(max(preloadImageCount, 0), 15)
    }

    private var boundedPagedPreloadDelay: Double {
        min(max(pagedPreloadDelay, 0), 5)
    }

    private var readerPreloadDelay: Double {
        boundedPagedPreloadDelay
    }

    private var boundedImageRetryCount: Int {
        min(max(imageRetryCount, 0), 8)
    }

    private var boundedImageRetryInterval: Double {
        min(max(imageRetryInterval, 0.2), 10)
    }

    private var boundedTapPagingEdgePercent: Int {
        min(max(tapPagingEdgePercent, 5), 45)
    }

    private var boundedTapPagingDistancePercent: Int {
        min(max(tapPagingDistancePercent, 10), 120)
    }

    private var boundedDoubleTapZoomScale: Double {
        min(max(doubleTapZoomScale, 1.2), 5)
    }

    private var boundedLongPressZoomScale: Double {
        min(max(longPressZoomScale, 1.2), 5)
    }

    private var readerZoomConfiguration: ReaderZoomConfiguration {
        ReaderZoomConfiguration(
            pinchEnabled: pinchZoomEnabled,
            doubleTapEnabled: effectiveDoubleTapZoomEnabled,
            doubleTapScale: CGFloat(boundedDoubleTapZoomScale),
            longPressEnabled: longPressZoomEnabled,
            longPressScale: CGFloat(boundedLongPressZoomScale)
        )
    }

    private var effectiveDoubleTapZoomEnabled: Bool {
        doubleTapZoomEnabled && readerUIToggleMode != .double
    }

    private var boundedAutoPageInterval: Double {
        min(max(autoPagingInterval, 1), 60)
    }

    private var boundedAutoPageDistancePercent: Int {
        min(max(autoPagingDistancePercent, 10), 120)
    }

    private var readerReadingMode: ReaderReadingMode {
        ReaderReadingMode(rawValue: readingMode) ?? .topToBottomContinuous
    }

    private var currentChapter: ComicChapter? {
        guard detail.chapters.indices.contains(viewModel.currentChapterIndex) else { return nil }
        return detail.chapters[viewModel.currentChapterIndex]
    }

    private var shouldShowChapterCommentsAtEnd: Bool {
        showsChapterCommentsAtEnd && service.supportsChapterComments(platform: detail.item.platform)
    }

    private var dimsReaderImages: Bool {
        reducesImageBrightnessInDarkMode && colorScheme == .dark
    }

    private func pagedCommentPageIndex(for images: [ComicChapterImage]) -> Int? {
        guard readerReadingMode != .topToBottomContinuous,
              shouldShowChapterCommentsAtEnd,
              currentChapter != nil,
              !images.isEmpty else {
            return nil
        }
        return images.count
    }

    private var showsReaderUI: Bool {
        !hidesReaderUI
    }

    private var showsProgressOverlay: Bool {
        showsReaderUI || !progressFollowsUIVisibility
    }

    private var showsSystemStatusOverlay: Bool {
        showsSystemStatus && (showsReaderUI || !systemStatusFollowsUIVisibility)
    }

    private var shouldHideNavigationBar: Bool {
        hidesReaderUI
    }

    private func toggleReaderUI() {
        withAnimation(readerChromeAnimation) {
            hidesReaderUI.toggle()
        }
    }

    private func toggleAutoPaging() {
        if isAutoPaging {
            stopAutoPaging(toast: "已关闭自动翻页")
            return
        }

        syncAutoPagingStartPage()
        isAutoPagingTurnInFlight = false
        withAnimation(.easeOut(duration: 0.12)) {
            isAutoPaging = true
            hidesReaderUI = true
        }
        showReaderToast("已开启自动翻页")
    }

    private func stopAutoPaging(toast message: String? = nil) {
        isAutoPagingTurnInFlight = false
        withAnimation(.easeOut(duration: 0.12)) {
            isAutoPaging = false
        }
        if let message {
            showReaderToast(message)
        }
    }

    private func syncAutoPagingStartPage() {
        guard case .loaded(let images) = viewModel.state, !images.isEmpty else { return }
        let candidatePage: Int
        switch readerReadingMode {
        case .topToBottomContinuous:
            continuousScrollTracker.effectiveScrollY(fallback: continuousScrollPosition.point?.y)
            candidatePage = viewModel.currentPageIndex
        case .topToBottom, .leftToRight, .rightToLeft:
            candidatePage = pagedPageIndex
        }
        let pageIndex = min(max(candidatePage, 0), images.count - 1)
        _ = viewModel.updateCurrentPage(pageIndex)
    }

    private func reachedContinuousBottom(in images: [ComicChapterImage]) -> Bool {
        guard !images.isEmpty else { return true }
        let maxY = continuousScrollTracker.maxScrollY(fallbackViewportHeight: 1)
        if continuousScrollTracker.hasContentMetrics {
            return continuousScrollTracker.scrollY >= maxY - 4
        }
        return viewModel.currentPageIndex >= images.count - 1
    }

    private func showReaderToast(_ message: String) {
        readerToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.16)) {
            readerToastMessage = message
        }
        readerToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if readerToastMessage == message {
                        readerToastMessage = nil
                    }
                }
            }
        }
    }

    private func showInitialToastIfNeeded() {
        guard !didShowInitialToast else { return }
        didShowInitialToast = true
        guard showsReadingListBookToast,
              let initialToastMessage,
              !initialToastMessage.isEmpty else {
            return
        }
        showReaderToast(initialToastMessage)
    }

    private var readerUIToggleMode: ReaderUIToggleMode {
        ReaderUIToggleMode(rawValue: uiToggleMode) ?? .single
    }

    private var readerChromeAnimation: Animation {
        .easeInOut(duration: 0.22)
    }

    private var readerPageTurnAnimation: Animation {
        .easeInOut(duration: 0.22)
    }

    private func migrateReaderVisibilityDefaultsIfNeeded() {
        guard visibilityDefaultsVersion < 1 else { return }
        progressFollowsUIVisibility = false
        systemStatusFollowsUIVisibility = false
        visibilityDefaultsVersion = 1
    }

    private var progressBottomPadding: CGFloat {
        let baseInset = CGFloat(progressBottomInset)
        guard showsSystemStatus else { return baseInset }
        switch (readerProgressPosition, readerSystemStatusPosition) {
        case (.leading, .bottomLeading), (.trailing, .bottomTrailing):
            return max(baseInset, CGFloat(systemStatusBottomInset) + readerSystemStatus.bottomClearance)
        default:
            return baseInset
        }
    }

    private var readerSystemStatusInsets: EdgeInsets {
        var insets = readerSystemStatusPosition.edgeInsets
        if shouldHideNavigationBar {
            switch readerSystemStatusPosition {
            case .topLeading, .topTrailing:
                insets.top = 64
            case .bottomLeading, .bottomTrailing:
                break
            }
        }
        switch readerSystemStatusPosition {
        case .topLeading, .topTrailing:
            break
        case .bottomLeading, .bottomTrailing:
            insets.bottom = CGFloat(systemStatusBottomInset)
        }
        return insets
    }
}

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
    @State private var continuousScrollTracker = ReaderContinuousScrollTracker()
    @State private var continuousScrollRestoreTask: Task<Void, Never>?
    @State private var continuousLoadableImageIDs = Set<String>()
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
                    continuousScrollPosition.scrollTo(y: 0)
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
                    resetID: continuousZoomResetID
                )
            }
        }
        .ignoresSafeArea(.container)
    }

    @ViewBuilder
    private func horizontalPagedReaderContent(images: [ComicChapterImage]) -> some View {
        GeometryReader { geometry in
            let targetPixelWidth = readerTargetPixelWidth(for: geometry.size.width)
            TabView(selection: $pagedPageIndex) {
                ForEach(images.indices, id: \.self) { index in
                    ReaderImageView(
                        image: images[index],
                        retryCount: boundedImageRetryCount,
                        retryInterval: boundedImageRetryInterval,
                                targetPixelWidth: targetPixelWidth,
                                containerSize: geometry.size,
                                isLoadAllowed: index == pagedPageIndex,
                                zoomConfiguration: readerZoomConfiguration,
                                dimsImage: dimsReaderImages
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tag(index)
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
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tag(images.count)
                    .id(readerCommentsPageID())
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .picaxPageTabViewStyle()
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
                            pagedPageIndex = pageIndex
                        }
                    }
                }
            )
            .readerAutoPaging(isEnabled: isAutoPaging, interval: boundedAutoPageInterval) {
                handleAutoPageTick(images: images, targetPixelWidth: targetPixelWidth) { pageIndex in
                    pagedPageIndex = pageIndex
                }
            }
            .onAppear {
                syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
            }
            .onChange(of: viewModel.currentChapterIndex) { _, _ in
                syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        pagedPageIndex = pageIndex
                    }
                }
            }
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
                                    pagedPageIndex = pageIndex
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
                            pagedPageIndex = pageIndex
                            if pageIndex == images.count, pagedCommentPageIndex(for: images) != nil {
                                scrollToComments(proxy: proxy, animated: true)
                            } else {
                                scrollToPage(pageIndex, proxy: proxy, animated: true)
                            }
                        }
                    }
                    .onAppear {
                        syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToPagedSelection(proxy: proxy)
                    }
                    .onChange(of: viewModel.currentChapterIndex) { _, _ in
                        syncPagedSelection(images: images, targetPixelWidth: targetPixelWidth)
                        scrollToPagedSelection(proxy: proxy)
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
                            pagedPageIndex = pageIndex
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
                        isLoadAllowed: index == pagedPageIndex,
                        zoomConfiguration: readerZoomConfiguration,
                        dimsImage: dimsReaderImages
                    )
                        .frame(width: size.width, height: size.height)
                        .id(readerPageID(index))
                        .onAppear {
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

    private func scrollToPage(_ pageIndex: Int, proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(readerPageID(pageIndex), anchor: .top)
            }
        } else {
            proxy.scrollTo(readerPageID(pageIndex), anchor: .top)
        }
    }

    private func scrollToComments(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(readerCommentsPageID(), anchor: .top)
            }
        } else {
            proxy.scrollTo(readerCommentsPageID(), anchor: .top)
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

    private func syncPagedSelection(images: [ComicChapterImage], targetPixelWidth: Int?) {
        pagedPageIndex = min(max(viewModel.requestedPageIndex, 0), max(images.count - 1, 0))
        updateReadingPage(pagedPageIndex, totalPages: images.count, targetPixelWidth: targetPixelWidth, force: true)
    }

    private func scrollToPagedSelection(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            scrollToPage(pagedPageIndex, proxy: proxy, animated: false)
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
            pagedPageIndex = commentPageIndex
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

        withAnimation(.easeInOut(duration: 0.2)) {
            continuousScrollPosition.scrollTo(y: targetY)
        }
        continuousScrollTracker.updateScrollY(targetY)

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
                    continuousScrollPosition.scrollTo(y: 0)
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
            continuousScrollPosition.scrollTo(y: 0)
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
            withAnimation(.easeInOut(duration: 0.18)) {
                continuousScrollPosition.scrollTo(y: targetY)
            }
            continuousScrollTracker.updateScrollY(targetY)
        case .next:
            if currentY >= maxY - 4 {
                _ = await turnPage(.next, images: images, targetPixelWidth: targetPixelWidth, selectPage: { pageIndex in
                    scrollToPage(pageIndex, proxy: proxy, animated: true)
                })
                return
            }
            let targetY = min(currentY + distance, maxY)
            withAnimation(.easeInOut(duration: 0.18)) {
                continuousScrollPosition.scrollTo(y: targetY)
            }
            continuousScrollTracker.updateScrollY(targetY)
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
            pagedPageIndex = nextPage
            selectPage(nextPage)
            updateReadingPage(nextPage, totalPages: images.count, targetPixelWidth: targetPixelWidth)
            return true
        }

        if let commentPageIndex, nextPage == commentPageIndex {
            pagedPageIndex = commentPageIndex
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
            afterPage: index,
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

        let imageIDs = Set(indices.map { images[$0].urlString })
        guard continuousLoadableImageIDs != imageIDs else { return }
        continuousLoadableImageIDs = imageIDs
    }

    private func focusContinuousLoadableImage(_ pageIndex: Int, images: [ComicChapterImage]) {
        guard !images.isEmpty else {
            continuousLoadableImageIDs.removeAll(keepingCapacity: true)
            return
        }

        let boundedIndex = min(max(pageIndex, 0), images.count - 1)
        let imageIDs = Set([images[boundedIndex].urlString])
        guard continuousLoadableImageIDs != imageIDs else { return }
        continuousLoadableImageIDs = imageIDs
    }

    private func resetContinuousImageState() {
        continuousLoadableImageIDs.removeAll(keepingCapacity: true)
    }

    private func currentContinuousScrollSnapshot() -> ReaderContinuousScrollSnapshot? {
        guard readerReadingMode == .topToBottomContinuous else { return nil }
        let scrollY = continuousScrollTracker.effectiveScrollY(fallback: continuousScrollPosition.point?.y)
        guard scrollY.isFinite else { return nil }
        return ReaderContinuousScrollSnapshot(
            chapterIndex: viewModel.currentChapterIndex,
            scrollY: max(scrollY, 0)
        )
    }

    private func restoreContinuousScrollPosition(_ snapshot: ReaderContinuousScrollSnapshot) {
        guard readerReadingMode == .topToBottomContinuous,
              snapshot.chapterIndex == viewModel.currentChapterIndex else {
            return
        }

        let scrollY = max(snapshot.scrollY, 0)
        continuousScrollRestoreTask?.cancel()
        continuousScrollTracker.updateScrollY(scrollY)
        continuousScrollPosition.scrollTo(y: scrollY)
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
                continuousScrollTracker.updateScrollY(scrollY)
                continuousScrollPosition.scrollTo(y: scrollY)
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
        min(max(preloadImageCount, 0), 12)
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
        let scrollSnapshot = currentContinuousScrollSnapshot()
        withAnimation(readerChromeAnimation) {
            hidesReaderUI.toggle()
        }
        if let scrollSnapshot {
            restoreContinuousScrollPosition(scrollSnapshot)
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

private struct ReaderScrollTargetLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetLayout()
        } else {
            content
        }
    }
}

private struct ReaderPagingScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetBehavior(.paging)
        } else {
            content
        }
    }
}

private enum ReaderPageTurnDirection {
    case previous
    case next

    var inverted: ReaderPageTurnDirection {
        switch self {
        case .previous:
            .next
        case .next:
            .previous
        }
    }
}

private struct ReaderScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat

    init(offsetY: CGFloat, contentHeight: CGFloat, visibleHeight: CGFloat) {
        self.offsetY = max(offsetY, 0)
        self.contentHeight = max(contentHeight, 0)
        self.visibleHeight = max(visibleHeight, 0)
    }
}

private struct ReaderContinuousScrollSnapshot {
    let chapterIndex: Int
    let scrollY: CGFloat
}

@MainActor
private final class ReaderContinuousScrollTracker {
    private static let verticalPadding: CGFloat = 10
    private static let defaultAspectRatio: Double = 1.42

    private(set) var scrollY: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0
    private(set) var visibleHeight: CGFloat = 0
    private var isReady = false
    private var aspectRatios: [Int: Double] = [:]
    private var lastReportedPageIndex: Int?

    var hasContentMetrics: Bool {
        contentHeight > 0 && visibleHeight > 0
    }

    func reset() {
        scrollY = 0
        contentHeight = 0
        visibleHeight = 0
        isReady = false
        aspectRatios.removeAll(keepingCapacity: true)
        lastReportedPageIndex = nil
    }

    func setReady() {
        isReady = true
    }

    func updateMetrics(_ metrics: ReaderScrollMetrics) {
        scrollY = metrics.offsetY
        contentHeight = metrics.contentHeight
        visibleHeight = metrics.visibleHeight
    }

    func updateScrollY(_ value: CGFloat) {
        scrollY = max(value, 0)
    }

    @discardableResult
    func effectiveScrollY(fallback: CGFloat?) -> CGFloat {
        if let fallback {
            updateScrollY(fallback)
        }
        return scrollY
    }

    @discardableResult
    func updateAspectRatio(
        _ aspectRatio: Double,
        for index: Int,
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat? {
        guard images.indices.contains(index),
              displayWidth.isFinite,
              displayWidth > 0,
              aspectRatio.isFinite,
              aspectRatio > 0 else {
            if index >= 0, aspectRatio.isFinite, aspectRatio > 0 {
                aspectRatios[index] = aspectRatio
            }
            return nil
        }

        let oldAspectRatio = self.aspectRatio(for: index, image: images[index])
        guard abs(oldAspectRatio - aspectRatio) > 0.001 else {
            aspectRatios[index] = aspectRatio
            return nil
        }

        let oldPageTop = pageTop(
            for: index,
            images: images,
            displayWidth: displayWidth,
            imageSpacing: imageSpacing,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )
        let oldPageHeight = pageHeight(
            for: index,
            imageCount: images.count,
            displayWidth: displayWidth,
            aspectRatio: oldAspectRatio,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )
        aspectRatios[index] = aspectRatio
        let newPageHeight = pageHeight(
            for: index,
            imageCount: images.count,
            displayWidth: displayWidth,
            aspectRatio: aspectRatio,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )

        guard isReady,
              oldPageTop.isFinite,
              oldPageHeight.isFinite,
              newPageHeight.isFinite else {
            return nil
        }

        let heightDelta = newPageHeight - oldPageHeight
        guard abs(heightDelta) > 0.5 else { return nil }

        let oldPageBottom = oldPageTop + oldPageHeight
        let adjustedY: CGFloat?
        if oldPageBottom <= scrollY + 1 {
            adjustedY = scrollY + heightDelta
        } else if oldPageTop < scrollY {
            let progressInsidePage = min(max((scrollY - oldPageTop) / max(oldPageHeight, 1), 0), 1)
            adjustedY = scrollY + heightDelta * progressInsidePage
        } else {
            adjustedY = nil
        }

        guard let adjustedY else { return nil }
        scrollY = max(adjustedY, 0)
        return scrollY
    }

    func maxScrollY(fallbackViewportHeight: CGFloat) -> CGFloat {
        max(contentHeight - max(visibleHeight, fallbackViewportHeight, 1), 0)
    }

    func visiblePageIndices(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
        fallbackViewportHeight: CGFloat
    ) -> Set<Int> {
        guard isReady, !images.isEmpty, displayWidth.isFinite, displayWidth > 0 else {
            return []
        }

        let viewportHeight = max(visibleHeight > 0 ? visibleHeight : fallbackViewportHeight, 0)
        guard viewportHeight > 0 else { return [] }

        let viewportPadding: CGFloat = 8
        let viewportTop = max(scrollY - viewportPadding, 0)
        let viewportBottom = scrollY + viewportHeight + viewportPadding
        var visibleIndices = Set<Int>()
        var pageTop = Self.verticalPadding

        for index in images.indices {
            let pageHeight = pageHeight(
                for: index,
                imageCount: images.count,
                displayWidth: displayWidth,
                aspectRatio: aspectRatio(for: index, image: images[index]),
                firstImageTopPadding: firstImageTopPadding,
                lastImageBottomPadding: lastImageBottomPadding
            )
            let pageBottom = pageTop + pageHeight
            if pageBottom >= viewportTop, pageTop <= viewportBottom {
                visibleIndices.insert(index)
            } else if pageTop > viewportBottom {
                break
            }

            pageTop = pageBottom
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }

        return visibleIndices
    }

    func visiblePageIndex(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
        fallbackViewportHeight: CGFloat
    ) -> Int? {
        guard isReady, !images.isEmpty, displayWidth.isFinite, displayWidth > 0 else {
            return nil
        }

        let viewportHeight = max(visibleHeight > 0 ? visibleHeight : fallbackViewportHeight, 0)
        guard viewportHeight > 0 else { return nil }

        let viewportTop = scrollY
        let viewportBottom = viewportTop + viewportHeight
        let viewportCenterY = viewportTop + viewportHeight / 2
        var bestIndex: Int?
        var bestVisibleHeight: CGFloat = 0
        var bestDistanceFromCenter = CGFloat.greatestFiniteMagnitude
        var pageTop = Self.verticalPadding

        for index in images.indices {
            let topPadding = index == images.startIndex ? max(firstImageTopPadding, 0) : 0
            let bottomPadding = index == images.index(before: images.endIndex) ? max(lastImageBottomPadding, 0) : 0
            let imageHeight = displayWidth * CGFloat(aspectRatio(for: index, image: images[index]))
            let pageHeight = topPadding + max(imageHeight, 120) + bottomPadding
            let pageBottom = pageTop + pageHeight
            let visibleTop = max(pageTop, viewportTop)
            let visibleBottom = min(pageBottom, viewportBottom)
            let visibleHeight = max(visibleBottom - visibleTop, 0)

            if visibleHeight > 1 {
                let distanceFromCenter = abs((pageTop + pageBottom) / 2 - viewportCenterY)
                if visibleHeight > bestVisibleHeight + 1
                    || (abs(visibleHeight - bestVisibleHeight) <= 1 && distanceFromCenter < bestDistanceFromCenter) {
                    bestIndex = index
                    bestVisibleHeight = visibleHeight
                    bestDistanceFromCenter = distanceFromCenter
                }
            }

            pageTop = pageBottom
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }

        guard let bestIndex, bestIndex != lastReportedPageIndex else {
            return nil
        }
        lastReportedPageIndex = bestIndex
        return bestIndex
    }

    private func aspectRatio(for index: Int, image: ComicChapterImage) -> Double {
        if let aspectRatio = aspectRatios[index] {
            return aspectRatio
        }
        if let cached = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) {
            aspectRatios[index] = cached
            return cached
        }
        return Self.defaultAspectRatio
    }

    private func pageTop(
        for targetIndex: Int,
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat {
        var pageTop = Self.verticalPadding
        for index in images.indices {
            if index == targetIndex {
                return pageTop
            }
            let pageHeight = pageHeight(
                for: index,
                imageCount: images.count,
                displayWidth: displayWidth,
                aspectRatio: aspectRatio(for: index, image: images[index]),
                firstImageTopPadding: firstImageTopPadding,
                lastImageBottomPadding: lastImageBottomPadding
            )
            pageTop += pageHeight
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }
        return pageTop
    }

    private func pageHeight(
        for index: Int,
        imageCount: Int,
        displayWidth: CGFloat,
        aspectRatio: Double,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat {
        let topPadding = index == 0 ? max(firstImageTopPadding, 0) : 0
        let bottomPadding = index == imageCount - 1 ? max(lastImageBottomPadding, 0) : 0
        let imageHeight = displayWidth * CGFloat(aspectRatio)
        return topPadding + max(imageHeight, 120) + bottomPadding
    }
}

private struct ReaderZoomConfiguration: Equatable {
    let pinchEnabled: Bool
    let doubleTapEnabled: Bool
    let doubleTapScale: CGFloat
    let longPressEnabled: Bool
    let longPressScale: CGFloat

    var normalizedDoubleTapScale: CGFloat {
        min(max(doubleTapScale, 1.2), 5)
    }

    var normalizedLongPressScale: CGFloat {
        min(max(longPressScale, 1.2), 5)
    }

    var isZoomEnabled: Bool {
        pinchEnabled || doubleTapEnabled || longPressEnabled
    }
}

private struct ReaderInteractionGestureModifier: ViewModifier {
    private static let delayedSingleTapNanoseconds: UInt64 = 320_000_000
    private static let doubleTapSuppressionDuration: TimeInterval = 0.45

    let size: CGSize
    let mode: ReaderUIToggleMode
    let tapPagingEnabled: Bool
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let doubleTapZoomEnabled: Bool
    let readingMode: ReaderReadingMode
    let toggleUI: () -> Void
    let turnPage: (ReaderPageTurnDirection) -> Void
    @State private var delayedTapTask: Task<Void, Never>?
    @State private var tapSuppressionUntil = Date.distantPast

    func body(content: Content) -> some View {
        let content = content
            .contentShape(Rectangle())
            .simultaneousGesture(tapMovementSuppressionGesture)

        switch mode {
        case .single:
            if doubleTapZoomEnabled {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                content
                    .simultaneousGesture(singleTapGesture)
            }
        case .double:
            if doubleTapZoomEnabled {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { _ in toggleUI() })
            }
        }
    }

    private var tapMovementSuppressionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if shouldSuppressTap(for: value.translation) {
                    suppressTapForCurrentMovement()
                }
            }
            .onEnded { value in
                if shouldSuppressTap(for: value.translation) {
                    suppressTapForCurrentMovement()
                }
            }
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { value in
                if doubleTapZoomEnabled {
                    scheduleDelayedTap(at: value.location)
                } else {
                    handleTap(at: value.location)
                }
            }
    }

    private var doubleTapCancellationGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                suppressTapAfterDoubleTap()
            }
    }

    private func scheduleDelayedTap(at location: CGPoint) {
        delayedTapTask?.cancel()
        delayedTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.delayedSingleTapNanoseconds)
            guard !Task.isCancelled else { return }
            handleTap(at: location)
            delayedTapTask = nil
        }
    }

    private func handleTap(at location: CGPoint) {
        guard !ReaderZoomTapSuppressor.shouldSuppressTap,
              Date() >= tapSuppressionUntil else {
            return
        }

        if tapPagingEnabled, let direction = tapPageDirection(at: location) {
            turnPage(tapPagingInverted ? direction.inverted : direction)
            return
        }

        if mode == .single {
            toggleUI()
        }
    }

    private func tapPageDirection(at location: CGPoint) -> ReaderPageTurnDirection? {
        let ratio = CGFloat(min(max(tapPagingEdgePercent, 5), 45)) / 100
        guard size.width > 0, size.height > 0 else { return nil }

        switch readingMode {
        case .leftToRight:
            if location.x >= size.width * (1 - ratio) { return .next }
            if location.x <= size.width * ratio { return .previous }
        case .rightToLeft:
            if location.x >= size.width * (1 - ratio) { return .previous }
            if location.x <= size.width * ratio { return .next }
        case .topToBottom, .topToBottomContinuous:
            if location.y >= size.height * (1 - ratio) { return .next }
            if location.y <= size.height * ratio { return .previous }
        }

        return nil
    }

    private func shouldSuppressTap(for translation: CGSize) -> Bool {
        let distance = hypot(translation.width, translation.height)
        return distance > 6
    }

    private func suppressTapForCurrentMovement() {
        delayedTapTask?.cancel()
        tapSuppressionUntil = Date().addingTimeInterval(0.25)
    }

    private func suppressTapAfterDoubleTap() {
        delayedTapTask?.cancel()
        delayedTapTask = nil
        tapSuppressionUntil = Date().addingTimeInterval(Self.doubleTapSuppressionDuration)
        ReaderZoomTapSuppressor.suppressTap(for: Self.doubleTapSuppressionDuration)
    }
}

private struct ReaderImageView: View {
    let image: ComicChapterImage
    let retryCount: Int
    let retryInterval: Double
    let targetPixelWidth: Int?
    var displayWidth: CGFloat? = nil
    var containerSize: CGSize? = nil
    var isLoadAllowed = true
    let zoomConfiguration: ReaderZoomConfiguration
    let dimsImage: Bool
    var onAspectRatioResolved: ((Double) -> Void)? = nil
    @State private var retryID = 0
    @State private var loadState: ReaderImageLoadState = .loading
    @State private var knownAspectRatio: Double?
    @State private var layoutAspectRatio: Double?
    @State private var reportedLayoutAspectRatio: Double?

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ReaderImagePlaceholder(height: reservedHeight)
            case .loaded(let image):
                ReaderZoomableImage(
                    image: image,
                    imageID: self.image.urlString,
                    displayWidth: displayWidth,
                    containerSize: containerSize,
                    configuration: zoomConfiguration,
                    layoutAspectRatio: currentLayoutAspectRatio,
                    dimsImage: dimsImage
                )
            case .failed:
                ReaderImageFailure(height: reservedHeight) {
                    retryID += 1
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .task(id: "\(image.urlString)-\(targetPixelWidth ?? 0)-\(retryID)-\(isLoadAllowed)") {
            guard isLoadAllowed else {
                loadCachedAspectRatio()
                return
            }
            await loadImage()
        }
        .onChange(of: image.urlString) { _, _ in
            resetLocalImageState()
        }
    }

    private var reservedHeight: CGFloat? {
        guard let displayWidth, displayWidth > 0 else {
            return nil
        }
        let aspectRatio = currentLayoutAspectRatio
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return max(displayWidth * 1.42, 120)
        }
        return max(displayWidth * CGFloat(aspectRatio), 120)
    }

    private var currentLayoutAspectRatio: Double {
        let aspectRatio = layoutAspectRatio
            ?? knownAspectRatio
            ?? ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString)
            ?? 1.42
        return aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.42
    }

    @MainActor
    private func loadCachedAspectRatio() {
        guard knownAspectRatio == nil,
              let cachedAspectRatio = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) else {
            return
        }
        receiveAspectRatio(cachedAspectRatio, storesInCache: false)
    }

    @MainActor
    private func loadImage() async {
        guard let url = image.url else {
            loadState = .failed
            return
        }

        if let cachedAspectRatio = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) {
            receiveAspectRatio(cachedAspectRatio, storesInCache: false)
        }
        loadState = .loading
        let attempts = max(retryCount, 0) + 1
        for attempt in 0..<attempts {
            do {
                let decodedImage = try await ReaderImageDecoder.image(
                    url: url,
                    targetPixelWidth: targetPixelWidth,
                    onAspectRatioResolved: { aspectRatio in
                        guard !Task.isCancelled else { return }
                        receiveAspectRatio(aspectRatio)
                    }
                )
                guard !Task.isCancelled else { return }
                receiveAspectRatio(decodedImage.aspectRatio)
                loadState = .loaded(decodedImage.image)
                return
            } catch {
                guard attempt < attempts - 1 else {
                    loadState = .failed
                    return
                }
                let delay = UInt64(max(retryInterval, 0.2) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
        }
    }

    @MainActor
    private func receiveAspectRatio(_ aspectRatio: Double, storesInCache: Bool = true) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        knownAspectRatio = aspectRatio
        if storesInCache {
            ReaderImageAspectRatioCache.shared.store(aspectRatio, for: image.urlString)
        }
        applyLayoutAspectRatio(aspectRatio)
    }

    @MainActor
    private func applyLayoutAspectRatio(_ aspectRatio: Double) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        layoutAspectRatio = aspectRatio
        guard reportedLayoutAspectRatio.map({ abs($0 - aspectRatio) > 0.001 }) ?? true else {
            return
        }
        reportedLayoutAspectRatio = aspectRatio
        onAspectRatioResolved?(aspectRatio)
    }

    @MainActor
    private func resetLocalImageState() {
        retryID = 0
        loadState = .loading
        knownAspectRatio = nil
        layoutAspectRatio = nil
        reportedLayoutAspectRatio = nil
    }
}

private struct ReaderZoomableImage: View {
    let image: PicaXPlatformImage
    let imageID: String
    let displayWidth: CGFloat?
    let containerSize: CGSize?
    let configuration: ReaderZoomConfiguration
    let layoutAspectRatio: Double?
    let dimsImage: Bool

    var body: some View {
        Group {
            if displayWidth != nil {
                Image(picaxImage: image)
                    .resizable()
                    .scaledToFit()
                    .readerImageBrightnessReduction(dimsImage)
            } else {
                ReaderPhotoViewImage(
                    image: image,
                    imageID: imageID,
                    configuration: configuration,
                    dimsImage: dimsImage
                )
                .id(imageID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: reservedDisplayHeight)
    }

    private var reservedDisplayHeight: CGFloat? {
        guard let displayWidth, displayWidth > 0 else { return nil }
        if let layoutAspectRatio, layoutAspectRatio.isFinite, layoutAspectRatio > 0 {
            return max(displayWidth * CGFloat(layoutAspectRatio), 120)
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return displayWidth * size.height / size.width
    }
}

@MainActor
private enum ReaderZoomTapSuppressor {
    private static var suppressUntil = Date.distantPast

    static var shouldSuppressTap: Bool {
        Date() < suppressUntil
    }

    static func suppressTap(for duration: TimeInterval = 0.36) {
        suppressUntil = Date().addingTimeInterval(duration)
    }
}

private extension View {
    @ViewBuilder
    func readerImageBrightnessReduction(_ isEnabled: Bool) -> some View {
        if isEnabled {
            overlay {
                Color.black
                    .opacity(0.2)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

#if os(iOS)
private struct ReaderContinuousZoomHost<Content: View>: UIViewRepresentable {
    let configuration: ReaderZoomConfiguration
    let resetID: String
    let content: Content

    init(
        configuration: ReaderZoomConfiguration,
        resetID: String,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.resetID = resetID
        self.content = content()
    }

    func makeUIView(context: Context) -> ReaderContinuousZoomUIView<Content> {
        ReaderContinuousZoomUIView(rootView: content)
    }

    func updateUIView(_ uiView: ReaderContinuousZoomUIView<Content>, context: Context) {
        uiView.update(rootView: content, configuration: configuration, resetID: resetID)
    }

    static func dismantleUIView(_ uiView: ReaderContinuousZoomUIView<Content>, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

private final class ReaderContinuousZoomUIView<Content: View>: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let hostingController: UIHostingController<Content>
    private var resetID = ""
    private var lastBoundsSize: CGSize = .zero
    private var configuration = ReaderZoomConfiguration(
        pinchEnabled: true,
        doubleTapEnabled: true,
        doubleTapScale: 1.75,
        longPressEnabled: true,
        longPressScale: 1.75
    )
    private var longPressStartedZoom = false

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: Content, configuration: ReaderZoomConfiguration, resetID: String) {
        hostingController.rootView = rootView
        let wasZoomEnabled = self.configuration.isZoomEnabled
        self.configuration = configuration
        let shouldReset = self.resetID != resetID
        self.resetID = resetID
        configureGestures()
        configureZoomLimits()
        if shouldReset || (wasZoomEnabled && !configuration.isZoomEnabled) {
            resetZoom(animated: false)
        }
        setNeedsLayout()
    }

    func prepareForReuse() {
        resetZoom(animated: false)
        resetID = ""
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        scrollView.frame = bounds
        let didChangeSize = lastBoundsSize != bounds.size
        lastBoundsSize = bounds.size
        if didChangeSize {
            resetZoom(animated: false)
        }
        hostingController.view.frame = CGRect(origin: .zero, size: bounds.size)
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            scrollView.contentSize = bounds.size
        }
        updateContentInsets()
        updateInteractionState()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInsets()
        updateInteractionState()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateInteractionState()
    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.isEnabled = false

        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = bounds

        addSubview(scrollView)
        scrollView.addSubview(hostingController.view)
        configureGestures()
        configureZoomLimits()
    }

    private func configureGestures() {
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchEnabled
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousDoubleTapZoom" }) != true {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.name = "reader.continuousDoubleTapZoom"
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousLongPressZoom" }) != true {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = 0.30
            recognizer.allowableMovement = 12
            recognizer.name = "reader.continuousLongPressZoom"
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        scrollView.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "reader.continuousDoubleTapZoom" {
                recognizer.isEnabled = configuration.doubleTapEnabled
            } else if recognizer.name == "reader.continuousLongPressZoom" {
                recognizer.isEnabled = configuration.longPressEnabled
            }
        }
    }

    private func configureZoomLimits() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(2.5, configuration.normalizedDoubleTapScale, configuration.normalizedLongPressScale)
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
        updateInteractionState()
    }

    private func resetZoom(animated: Bool) {
        longPressStartedZoom = false
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        scrollView.contentOffset = .zero
        scrollView.contentSize = bounds.size
        updateContentInsets()
        updateInteractionState()
    }

    private func updateContentInsets() {
        let contentSize = scrollView.contentSize
        let insetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let insetY = max((bounds.height - contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func updateInteractionState() {
        let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        scrollView.panGestureRecognizer.isEnabled = isZoomed
        hostingController.view.isUserInteractionEnabled = !isZoomed
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration.doubleTapEnabled, recognizer.state == .ended else { return }
        ReaderZoomTapSuppressor.suppressTap()
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            resetZoom(animated: true)
            return
        }

        zoom(to: configuration.normalizedDoubleTapScale, at: recognizer.location(in: hostingController.view), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard configuration.longPressEnabled else { return }
        switch recognizer.state {
        case .began:
            ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                longPressStartedZoom = false
                return
            }
            longPressStartedZoom = true
            zoom(to: configuration.normalizedLongPressScale, at: recognizer.location(in: hostingController.view), animated: true)
        case .changed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            }
        case .ended, .cancelled, .failed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap()
                resetZoom(animated: true)
            }
            longPressStartedZoom = false
        default:
            break
        }
    }

    private func zoom(to multiplier: CGFloat, at location: CGPoint, animated: Bool) {
        let targetScale = min(max(scrollView.minimumZoomScale * multiplier, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: location.x - size.width * 0.5,
            y: location.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private struct ReaderPhotoViewImage: UIViewRepresentable {
    let image: UIImage
    let imageID: String
    let configuration: ReaderZoomConfiguration
    let dimsImage: Bool

    func makeUIView(context: Context) -> ReaderPhotoZoomView {
        ReaderPhotoZoomView()
    }

    func updateUIView(_ uiView: ReaderPhotoZoomView, context: Context) {
        uiView.update(image: image, imageID: imageID, configuration: configuration, dimsImage: dimsImage)
    }

    static func dismantleUIView(_ uiView: ReaderPhotoZoomView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

private final class ReaderPhotoZoomView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var imageID = ""
    private var dimsImage = false
    private var configuration = ReaderZoomConfiguration(
        pinchEnabled: true,
        doubleTapEnabled: true,
        doubleTapScale: 1.75,
        longPressEnabled: true,
        longPressScale: 1.75
    )
    private var longPressStartedZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(image: UIImage, imageID: String, configuration: ReaderZoomConfiguration, dimsImage: Bool) {
        self.configuration = configuration
        self.dimsImage = dimsImage
        let didChangeImage = self.imageID != imageID
        self.imageID = imageID
        if didChangeImage {
            resetZoom(animated: false)
        }
        if imageView.image !== image {
            imageView.image = image
        }
        imageView.alpha = dimsImage ? 0.8 : 1
        configureGestures()
        configureZoomLimits()
        if didChangeImage {
            setNeedsLayout()
        }
    }

    func prepareForReuse() {
        resetZoom(animated: false)
        imageID = ""
        dimsImage = false
        imageView.alpha = 1
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        scrollView.frame = bounds
        layoutImageView(resetZoomIfNeeded: scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
        updatePanState()
    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.isEnabled = false

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        addSubview(scrollView)
        scrollView.addSubview(imageView)
        configureGestures()
        configureZoomLimits()
    }

    private func configureGestures() {
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchEnabled
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.doubleTapZoom" }) != true {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.name = "reader.doubleTapZoom"
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.longPressZoom" }) != true {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = 0.30
            recognizer.allowableMovement = 1
            recognizer.name = "reader.longPressZoom"
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        scrollView.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "reader.doubleTapZoom" {
                recognizer.isEnabled = configuration.doubleTapEnabled
            } else if recognizer.name == "reader.longPressZoom" {
                recognizer.isEnabled = configuration.longPressEnabled
            }
        }
    }

    private func configureZoomLimits() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(2.5, configuration.normalizedDoubleTapScale, configuration.normalizedLongPressScale)
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
        updatePanState()
    }

    private func resetZoom(animated: Bool) {
        longPressStartedZoom = false
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        scrollView.contentOffset = .zero
        updatePanState()
    }

    private func layoutImageView(resetZoomIfNeeded: Bool) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = bounds
            scrollView.contentSize = bounds.size
            return
        }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        if resetZoomIfNeeded {
            scrollView.zoomScale = scrollView.minimumZoomScale
            imageView.bounds = CGRect(origin: .zero, size: fittedSize)
            scrollView.contentSize = fittedSize
        }
        centerImageView()
    }

    private func centerImageView() {
        let contentSize = scrollView.contentSize
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(
            x: contentSize.width * 0.5 + offsetX,
            y: contentSize.height * 0.5 + offsetY
        )
    }

    private func updatePanState() {
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration.doubleTapEnabled, recognizer.state == .ended else { return }
        ReaderZoomTapSuppressor.suppressTap()
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        zoom(to: configuration.normalizedDoubleTapScale, at: recognizer.location(in: imageView), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard configuration.longPressEnabled else { return }
        switch recognizer.state {
        case .began:
            ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                longPressStartedZoom = false
                return
            }
            longPressStartedZoom = true
            zoom(to: configuration.normalizedLongPressScale, at: recognizer.location(in: imageView), animated: true)
        case .changed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            }
        case .ended, .cancelled, .failed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap()
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            }
            longPressStartedZoom = false
        default:
            break
        }
    }

    private func zoom(to multiplier: CGFloat, at imageLocation: CGPoint, animated: Bool) {
        let targetScale = min(max(scrollView.minimumZoomScale * multiplier, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: imageLocation.x - size.width * 0.5,
            y: imageLocation.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
#else
private struct ReaderPhotoViewImage: View {
    let image: PicaXPlatformImage
    let imageID: String
    let configuration: ReaderZoomConfiguration
    let dimsImage: Bool

    var body: some View {
        Image(picaxImage: image)
            .resizable()
            .scaledToFit()
            .readerImageBrightnessReduction(dimsImage)
            .background(Color.black)
    }
}
#endif

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}

private struct ReaderDecodedImage: @unchecked Sendable {
    let image: PicaXPlatformImage

    var aspectRatio: Double {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1.4 }
        return Double(size.height / size.width)
    }
}

private struct ReaderHistoryRecordSnapshot: Equatable {
    let item: ComicListItem
    let chapterIndex: Int
    let pageIndex: Int
    let totalPages: Int
    let totalChapters: Int
}

private struct ReaderProgressSelectionContext: Identifiable, Equatable {
    let id = UUID()
    let chapterIndex: Int
    let chapterTitle: String
    let pageIndex: Int
    let pageCount: Int
}

private struct ReaderProgressJumpRequest: Equatable {
    let id = UUID()
    let chapterIndex: Int
    let pageIndex: Int
}

private enum ReaderImageMemoryCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, PicaXPlatformImage> = {
        let cache = NSCache<NSString, PicaXPlatformImage>()
        cache.countLimit = 18
        cache.totalCostLimit = 112 * 1024 * 1024
        return cache
    }()

    nonisolated static func image(for key: String) -> ReaderDecodedImage? {
        guard let image = cache.object(forKey: key as NSString) else {
            return nil
        }
        return ReaderDecodedImage(image: image)
    }

    nonisolated static func store(_ decodedImage: ReaderDecodedImage, key: String) {
        cache.setObject(decodedImage.image, forKey: key as NSString, cost: decodedImage.image.picaxEstimatedMemoryCost)
    }
}

private final class ReaderImageAspectRatioCache: @unchecked Sendable {
    static let shared = ReaderImageAspectRatioCache()

    private let lock = NSLock()
    private var aspectRatios: [String: Double] = [:]

    private init() {}

    func aspectRatio(for key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return aspectRatios[key]
    }

    func store(_ aspectRatio: Double, for key: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        aspectRatios[key] = aspectRatio
        if aspectRatios.count > 800 {
            aspectRatios.removeValue(forKey: aspectRatios.keys.first ?? key)
        }
    }
}

private enum ReaderImageDecoder {
    nonisolated static func image(
        url: URL,
        targetPixelWidth: Int?,
        decodePriority: TaskPriority = .userInitiated,
        onAspectRatioResolved: (@MainActor (Double) -> Void)? = nil
    ) async throws -> ReaderDecodedImage {
        let cacheKey = cacheKey(url: url, targetPixelWidth: targetPixelWidth)
        if let cached = ReaderImageMemoryCache.image(for: cacheKey) {
            return cached
        }

        var data = try await ImageCacheService.data(for: url)
        guard !Task.isCancelled else { throw CancellationError() }
        if let aspectRatio = encodedAspectRatio(data: data) {
            await onAspectRatioResolved?(aspectRatio)
        }
        let decoded: ReaderDecodedImage
        do {
            decoded = try await decode(data: data, url: url, targetPixelWidth: targetPixelWidth, priority: decodePriority)
        } catch {
            ImageCacheService.removeCachedImageData(for: url)
            data = try await ImageCacheService.data(for: url, storesInCache: false)
            guard !Task.isCancelled else { throw CancellationError() }
            if let aspectRatio = encodedAspectRatio(data: data) {
                await onAspectRatioResolved?(aspectRatio)
            }
            decoded = try await decode(data: data, url: url, targetPixelWidth: targetPixelWidth, priority: decodePriority)
        }
        ImageCacheService.storeDecodedImageData(data, for: url)
        ReaderImageMemoryCache.store(decoded, key: cacheKey)
        return decoded
    }

    nonisolated static func preload(urlStrings: [String], targetPixelWidth: Int?) async {
        for urlString in urlStrings {
            guard !Task.isCancelled,
                  let url = URL.picaxResolved(from: urlString),
                  ReaderImageMemoryCache.image(for: cacheKey(url: url, targetPixelWidth: targetPixelWidth)) == nil else {
                continue
            }

            _ = try? await image(url: url, targetPixelWidth: targetPixelWidth, decodePriority: .utility)
        }
    }

    private nonisolated static func decode(data: Data, url: URL, targetPixelWidth: Int?, priority: TaskPriority) async throws -> ReaderDecodedImage {
        try await Task.detached(priority: priority) {
            if Task.isCancelled {
                throw CancellationError()
            }

            let image = JmImageScrambler.decodedImage(
                data: data,
                url: url,
                targetPixelWidth: targetPixelWidth
            ) ?? downsampledImage(data: data, targetPixelWidth: targetPixelWidth) ?? PicaXPlatformImage.picaxImage(data: data)

            guard let image else {
                throw URLError(.cannotDecodeContentData)
            }
            return ReaderDecodedImage(image: image)
        }.value
    }

    nonisolated static func downsampledImage(data: Data, targetPixelWidth: Int?) -> PicaXPlatformImage? {
        guard let targetPixelWidth,
              targetPixelWidth > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let sourceHeightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              sourceWidthNumber.doubleValue > 0,
              sourceHeightNumber.doubleValue > 0 else {
            return nil
        }

        let sourceWidth = CGFloat(sourceWidthNumber.doubleValue)
        let sourceHeight = CGFloat(sourceHeightNumber.doubleValue)
        let outputWidth = min(CGFloat(targetPixelWidth), sourceWidth)
        let scale = outputWidth / sourceWidth
        let maxPixelSize = max(Int((sourceHeight * scale).rounded(.up)), Int(outputWidth.rounded(.up)), 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return PicaXPlatformImage.picaxImage(cgImage: cgImage)
    }

    private nonisolated static func encodedAspectRatio(data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              widthNumber.doubleValue > 0,
              heightNumber.doubleValue > 0 else {
            return nil
        }
        let aspectRatio = heightNumber.doubleValue / widthNumber.doubleValue
        return aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : nil
    }

    private nonisolated static func cacheKey(url: URL, targetPixelWidth: Int?) -> String {
        "\(url.absoluteString)#\(targetPixelWidth ?? 0)"
    }
}

private enum JmImageScrambler {
    private nonisolated static let scrambleID = 220_980

    nonisolated static func decodedImage(data: Data, url: URL, targetPixelWidth: Int?) -> PicaXPlatformImage? {
        guard let info = imageInfo(from: url),
              let segmentCount = segmentCount(epsID: info.epsID, pictureName: info.pictureName),
              segmentCount > 1,
              let cgImage = originalCGImage(data: data) else {
            return nil
        }

        guard let rendered = reorderedImage(cgImage: cgImage, segmentCount: segmentCount) else {
            return PicaXPlatformImage.picaxImage(cgImage: cgImage)
        }
        let finalImage = scaledImageIfNeeded(cgImage: rendered, targetPixelWidth: targetPixelWidth) ?? rendered
        return PicaXPlatformImage.picaxImage(cgImage: finalImage)
    }

    private nonisolated static func imageInfo(from url: URL) -> (epsID: Int, pictureName: String)? {
        let components = url.pathComponents
        guard let photosIndex = components.lastIndex(of: "photos"),
              components.indices.contains(photosIndex + 2),
              let epsID = Int(components[photosIndex + 1]) else {
            return nil
        }

        let pictureName = (components[photosIndex + 2] as NSString).deletingPathExtension
        guard !pictureName.isEmpty else { return nil }
        return (epsID, pictureName)
    }

    private nonisolated static func segmentCount(epsID: Int, pictureName: String) -> Int? {
        if epsID < scrambleID {
            return 0
        }
        if epsID < 268_850 {
            return 10
        }

        let hashInput = "\(epsID)\(pictureName)"
        let digest = Insecure.MD5.hash(data: Data(hashInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let last = digest.utf8.last else { return nil }

        let divisor = epsID > 421_926 ? 8 : 10
        return Int(last % UInt8(divisor)) * 2 + 2
    }

    private nonisolated static func originalCGImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private nonisolated static func reorderedImage(cgImage: CGImage, segmentCount: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let blockHeight = height / segmentCount
        let remainder = height % segmentCount
        guard width > 0, height > 0, blockHeight > 0 else { return cgImage }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = width * 4
        var sourcePixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let didDrawSource = sourcePixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard didDrawSource else { return nil }

        var destinationPixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        sourcePixels.withUnsafeBytes { sourceBuffer in
            destinationPixels.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBase = sourceBuffer.baseAddress,
                      let destinationBase = destinationBuffer.baseAddress else {
                    return
                }

                var destinationY = 0
                for index in stride(from: segmentCount - 1, through: 0, by: -1) {
                    let sourceY = index * blockHeight
                    let currentHeight = blockHeight + (index == segmentCount - 1 ? remainder : 0)

                    for row in 0..<currentHeight {
                        let sourceOffset = (sourceY + row) * bytesPerRow
                        let destinationOffset = (destinationY + row) * bytesPerRow
                        destinationBase
                            .advanced(by: destinationOffset)
                            .copyMemory(from: sourceBase.advanced(by: sourceOffset), byteCount: bytesPerRow)
                    }

                    destinationY += currentHeight
                }
            }
        }

        let data = Data(destinationPixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private nonisolated static func scaledImageIfNeeded(cgImage: CGImage, targetPixelWidth: Int?) -> CGImage? {
        guard let targetPixelWidth,
              targetPixelWidth > 0,
              cgImage.width > targetPixelWidth,
              cgImage.width > 0,
              cgImage.height > 0 else {
            return cgImage
        }

        let scale = CGFloat(targetPixelWidth) / CGFloat(cgImage.width)
        let targetHeight = max(Int((CGFloat(cgImage.height) * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetPixelWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetPixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(targetPixelWidth), height: CGFloat(targetHeight)))
        return context.makeImage()
    }
}

private enum ReaderImageLoadState {
    case loading
    case loaded(PicaXPlatformImage)
    case failed
}

private struct ReaderImagePlaceholder: View {
    var height: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
            ProgressView()
                .tint(.white.opacity(0.72))
        }
        .frame(height: height ?? 280)
        .padding(.horizontal, 10)
    }
}

private struct ReaderImageFailure: View {
    var height: CGFloat? = nil
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
            Text("图片加载失败")
                .font(.footnote)
            Button {
                retry()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .frame(height: height ?? 240)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }
}

enum ReaderSettingsKey {
    static let progressStyle = "settings.reader.progressStyle"
    static let progressPosition = "settings.reader.progressPosition"
    static let showsPageLabel = "settings.reader.showsPageLabel"
    static let progressFollowsUIVisibility = "settings.reader.progressFollowsUIVisibility"
    static let progressTapSelectionEnabled = "settings.reader.progressTapSelectionEnabled"
    static let progressBackgroundOpacity = "settings.reader.progressBackgroundOpacity"
    static let progressBottomInset = "settings.reader.progressBottomInset"
    static let readingMode = "settings.reader.readingMode"
    static let imageSpacing = "settings.reader.imageSpacing"
    static let firstImageTopPadding = "settings.reader.firstImageTopPadding"
    static let lastImageBottomPadding = "settings.reader.lastImageBottomPadding"
    static let preloadImageCount = "settings.reader.preloadImageCount"
    static let pagedPreloadDelay = "settings.reader.pagedPreloadDelay"
    static let imageRetryCount = "settings.reader.imageRetryCount"
    static let imageRetryInterval = "settings.reader.imageRetryInterval"
    static let reducesImageBrightnessInDarkMode = "settings.reader.reducesImageBrightnessInDarkMode"
    static let hidesStatusBar = "settings.reader.hidesStatusBar"
    static let uiToggleMode = "settings.reader.uiToggleMode"
    static let tapPagingEnabled = "settings.reader.tapPagingEnabled"
    static let tapPagingInverted = "settings.reader.tapPagingInverted"
    static let tapPagingEdgePercent = "settings.reader.tapPagingEdgePercent"
    static let tapPagingDistancePercent = "settings.reader.tapPagingDistancePercent"
    static let pinchZoomEnabled = "settings.reader.pinchZoomEnabled"
    static let doubleTapZoomEnabled = "settings.reader.doubleTapZoomEnabled"
    static let doubleTapZoomScale = "settings.reader.doubleTapZoomScale"
    static let longPressZoomEnabled = "settings.reader.longPressZoomEnabled"
    static let longPressZoomScale = "settings.reader.longPressZoomScale"
    static let autoPagingInterval = "settings.reader.autoPagingInterval"
    static let autoPagingDistancePercent = "settings.reader.autoPagingDistancePercent"
    static let autoPagingTurnsChapter = "settings.reader.autoPagingTurnsChapter"
    static let showsChapterCommentsAtEnd = "settings.reader.showsChapterCommentsAtEnd"
    static let showsSystemStatus = "settings.reader.showsSystemStatus"
    static let systemStatusFollowsUIVisibility = "settings.reader.systemStatusFollowsUIVisibility"
    static let systemStatusStyle = "settings.reader.systemStatusStyle"
    static let systemStatusPosition = "settings.reader.systemStatusPosition"
    static let systemStatusBottomInset = "settings.reader.systemStatusBottomInset"
    static let usesProgressGlassBackground = "settings.reader.usesProgressGlassBackground"
    static let usesSystemStatusGlassBackground = "settings.reader.usesSystemStatusGlassBackground"
    static let showsReadingListBookToast = "settings.reader.showsReadingListBookToast"
    static let showsReadingListLoadingToast = "settings.reader.showsReadingListLoadingToast"
    static let readingListAutoAdvancesAtBoundary = "settings.reader.readingListAutoAdvancesAtBoundary"
    static let visibilityDefaultsVersion = "settings.reader.visibilityDefaultsVersion"
}

enum ReaderProgressStyle: String, CaseIterable, Identifiable {
    case circular
    case capsule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circular:
            "圆形"
        case .capsule:
            "胶囊"
        }
    }
}

enum ReaderUIToggleMode: String, CaseIterable, Identifiable {
    case single
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            "单击"
        case .double:
            "双击"
        }
    }
}

enum ReaderReadingMode: String, CaseIterable, Identifiable {
    case topToBottomContinuous
    case topToBottom
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topToBottomContinuous:
            "从上到下（连续）"
        case .topToBottom:
            "从上到下"
        case .leftToRight:
            "从左到右"
        case .rightToLeft:
            "从右到左"
        }
    }

    var description: String {
        switch self {
        case .topToBottomContinuous:
            "竖向连续滚动，所有图片顺序排列。"
        case .topToBottom:
            "单页竖向分页，每次翻到下一张。"
        case .leftToRight:
            "单页横向分页，按左到右方向阅读。"
        case .rightToLeft:
            "单页横向分页，按右到左方向阅读。"
        }
    }
}

enum ReaderProgressPosition: String, CaseIterable, Identifiable, Equatable {
    case leading
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading:
            "左下角"
        case .trailing:
            "右下角"
        }
    }

    var alignment: Alignment {
        switch self {
        case .leading:
            .bottomLeading
        case .trailing:
            .bottomTrailing
        }
    }
}

enum ReaderSystemStatusStyle: String, CaseIterable, Identifiable, Equatable {
    case compact
    case detailed
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            "紧凑"
        case .detailed:
            "详细"
        case .text:
            "文字"
        }
    }

    var bottomClearance: CGFloat {
        switch self {
        case .compact:
            38
        case .detailed:
            48
        case .text:
            28
        }
    }
}

enum ReaderOverlayPosition: String, CaseIterable, Identifiable, Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading:
            "左上角"
        case .topTrailing:
            "右上角"
        case .bottomLeading:
            "左下角"
        case .bottomTrailing:
            "右下角"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading:
            .topLeading
        case .topTrailing:
            .topTrailing
        case .bottomLeading:
            .bottomLeading
        case .bottomTrailing:
            .bottomTrailing
        }
    }

    var edgeInsets: EdgeInsets {
        switch self {
        case .topLeading:
            EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 0)
        case .topTrailing:
            EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 16)
        case .bottomLeading:
            EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 0)
        case .bottomTrailing:
            EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        }
    }

    var isBottom: Bool {
        switch self {
        case .topLeading, .topTrailing:
            false
        case .bottomLeading, .bottomTrailing:
            true
        }
    }
}

struct ReaderProgressOverlay: View {
    let title: String
    let progress: Double
    let style: ReaderProgressStyle
    let showsPageLabel: Bool
    let backgroundOpacity: Double
    let usesGlassBackground: Bool

    @ViewBuilder
    var body: some View {
        switch style {
        case .circular:
            circularBody
        case .capsule:
            capsuleBody
        }
    }

    private var circularBody: some View {
        HStack(spacing: showsPageLabel ? 7 : 0) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(normalizedProgress))
                    .stroke(
                        AngularGradient(
                            colors: [.white.opacity(0.72), .white, .white.opacity(0.86)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(percentText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            if showsPageLabel {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, showsPageLabel ? 10 : 6)
        .padding(.vertical, 5)
        .frame(minWidth: showsPageLabel ? 112 : 44, alignment: .leading)
        .readerCapsuleSurface(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground, fillScale: 0.42)
    }

    private var capsuleBody: some View {
        HStack(spacing: 8) {
            Text(percentText)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)

            if showsPageLabel {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: showsPageLabel ? 158 : 76, alignment: .leading)
        .readerCapsuleSurface(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground, fillScale: 0.38)
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: max(proxy.size.width * CGFloat(normalizedProgress), 8))
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
        }
    }

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentText: String {
        "\(Int((normalizedProgress * 100).rounded()))%"
    }
}

struct ReaderSystemStatusOverlay: View {
    let style: ReaderSystemStatusStyle
    let backgroundOpacity: Double
    let usesGlassBackground: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(date: context.date, battery: ReaderBatterySnapshot.current)
        }
        .onAppear {
            ReaderBatterySnapshot.enableMonitoring()
        }
    }

    @ViewBuilder
    private func content(date: Date, battery: ReaderBatterySnapshot) -> some View {
        switch style {
        case .compact:
            HStack(spacing: 7) {
                Text(timeText(date))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: batteryIcon(battery))
                    .font(.caption2.weight(.semibold))
                Text(batteryText(battery))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .statusBackground(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground)
        case .detailed:
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText(date))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(batteryStateText(battery))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.62))
                }

                batteryRing(battery)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .statusBackground(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground)
        case .text:
            Text("\(timeText(date))  \(batteryText(battery))")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 2)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
        }
    }

    private func batteryRing(_ battery: ReaderBatterySnapshot) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(battery.level))
                .stroke(battery.level <= 0.2 ? .red.opacity(0.88) : .white.opacity(0.82), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((battery.level * 100).rounded()))")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(width: 28, height: 28)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func batteryText(_ battery: ReaderBatterySnapshot) -> String {
        "\(Int((battery.level * 100).rounded()))%"
    }

    private func batteryIcon(_ battery: ReaderBatterySnapshot) -> String {
        if battery.state == .charging || battery.state == .full {
            return "battery.100.bolt"
        }
        switch battery.level {
        case ..<0.18:
            return "battery.0"
        case ..<0.42:
            return "battery.25"
        case ..<0.68:
            return "battery.50"
        case ..<0.9:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private func batteryStateText(_ battery: ReaderBatterySnapshot) -> String {
        switch battery.state {
        case .charging:
            return "充电中"
        case .full:
            return "已充满"
        default:
            return "电量"
        }
    }
}

private struct ReaderBatterySnapshot {
    let level: Double
    let state: BatteryState

    enum BatteryState: Equatable {
        case unplugged
        case charging
        case full
        case unknown
    }

    static func enableMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    static var current: ReaderBatterySnapshot {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel < 0 ? 1 : Double(rawLevel)
        let state: BatteryState
        switch UIDevice.current.batteryState {
        case .charging:
            state = .charging
        case .full:
            state = .full
        case .unplugged:
            state = .unplugged
        default:
            state = .unknown
        }
        return ReaderBatterySnapshot(level: min(max(level, 0), 1), state: state)
        #else
        return ReaderBatterySnapshot(level: 1, state: .unknown)
        #endif
    }
}

private struct ReaderAutoPagingModifier: ViewModifier {
    let isEnabled: Bool
    let interval: Double
    let onTick: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(Timer.publish(every: interval, on: .main, in: .common).autoconnect()) { _ in
                guard isEnabled else { return }
                onTick()
            }
    }
}

private struct ReaderProgressSelectionDialog: View {
    @Environment(\.dismiss) private var dismiss

    let context: ReaderProgressSelectionContext
    let onSelect: (Int) -> Void
    @State private var selectedPage: Int

    init(context: ReaderProgressSelectionContext, onSelect: @escaping (Int) -> Void) {
        self.context = context
        self.onSelect = onSelect
        _selectedPage = State(initialValue: min(max(context.pageIndex + 1, 1), max(context.pageCount, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("选择阅读进度", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text(context.chapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Text("\(selectedPage)/\(max(context.pageCount, 1))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if context.pageCount > 1 {
                Slider(value: selectedPageValue, in: 1...Double(context.pageCount), step: 1)
            }

            Stepper(value: $selectedPage, in: 1...max(context.pageCount, 1)) {
                Text("第 \(selectedPage) 页")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("跳转") {
                    onSelect(selectedPage - 1)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var selectedPageValue: Binding<Double> {
        Binding {
            Double(selectedPage)
        } set: { value in
            selectedPage = min(max(Int(value.rounded()), 1), max(context.pageCount, 1))
        }
    }
}

struct ReaderToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .readerToastGlassBackground()
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    }
}

private extension View {
    @ViewBuilder
    func readerToastGlassBackground() -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self
                .background(.black.opacity(0.34), in: Capsule(style: .continuous))
                .glassEffect(.regular.tint(.black.opacity(0.28)), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .background(.black.opacity(0.38), in: Capsule(style: .continuous))
        }
    }

    func readerAutoPaging(isEnabled: Bool, interval: Double, onTick: @escaping () -> Void) -> some View {
        modifier(ReaderAutoPagingModifier(isEnabled: isEnabled, interval: interval, onTick: onTick))
    }

    @ViewBuilder
    func readerContinuousZoom(
        configuration: ReaderZoomConfiguration,
        resetID: String
    ) -> some View {
        #if os(iOS)
        if configuration.isZoomEnabled {
            ReaderContinuousZoomHost(
                configuration: configuration,
                resetID: resetID
            ) {
                self
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    func readerInteractionGesture(
        size: CGSize,
        mode: ReaderUIToggleMode,
        tapPagingEnabled: Bool,
        tapPagingEdgePercent: Int,
        tapPagingInverted: Bool,
        doubleTapZoomEnabled: Bool,
        readingMode: ReaderReadingMode,
        toggleUI: @escaping () -> Void,
        turnPage: @escaping (ReaderPageTurnDirection) -> Void
    ) -> some View {
        modifier(ReaderInteractionGestureModifier(
            size: size,
            mode: mode,
            tapPagingEnabled: tapPagingEnabled,
            tapPagingEdgePercent: tapPagingEdgePercent,
            tapPagingInverted: tapPagingInverted,
            doubleTapZoomEnabled: doubleTapZoomEnabled,
            readingMode: readingMode,
            toggleUI: toggleUI,
            turnPage: turnPage
        ))
    }

    @ViewBuilder
    func readerConditionalSimultaneousGesture<G: Gesture>(_ gesture: G, enabled: Bool) -> some View {
        if enabled {
            self.simultaneousGesture(gesture)
        } else {
            self
        }
    }

    @ViewBuilder
    func readerConditionalHighPriorityGesture<G: Gesture>(_ gesture: G, enabled: Bool) -> some View {
        if enabled {
            self.highPriorityGesture(gesture)
        } else {
            self
        }
    }

    @ViewBuilder
    func statusBackground(opacity: Double, usesLiquidGlass: Bool, appliesWhenDisabled: Bool = true) -> some View {
        if appliesWhenDisabled || usesLiquidGlass {
            self
                .readerCapsuleSurface(
                    opacity: opacity,
                    usesLiquidGlass: usesLiquidGlass,
                    fillScale: appliesWhenDisabled ? 0.38 : 0,
                    minimumOpacity: appliesWhenDisabled ? 0.18 : 0,
                    strokeOpacity: appliesWhenDisabled ? 0.14 : 0
                )
        } else {
            self
        }
    }

    @ViewBuilder
    func readerCapsuleSurface(
        opacity: Double,
        usesLiquidGlass: Bool,
        fillScale: Double,
        minimumOpacity: Double = 0.18,
        strokeOpacity: Double = 0.16
    ) -> some View {
        if usesLiquidGlass {
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                self
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(max(opacity * 0.18, 0.08)))
                    }
                    .glassEffect(.regular, in: .capsule)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            } else {
                self
                    .readerCapsuleFallbackSurface(
                        opacity: opacity,
                        fillScale: fillScale,
                        minimumOpacity: minimumOpacity,
                        strokeOpacity: strokeOpacity
                    )
            }
        } else {
            self
                .readerCapsuleFallbackSurface(
                    opacity: opacity,
                    fillScale: fillScale,
                    minimumOpacity: minimumOpacity,
                    strokeOpacity: strokeOpacity
                )
        }
    }

    func readerCapsuleFallbackSurface(
        opacity: Double,
        fillScale: Double,
        minimumOpacity: Double,
        strokeOpacity: Double
    ) -> some View {
        self
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(max(opacity * fillScale, minimumOpacity)))
            }
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
    }
}

private struct ReaderChapterCommentsView: View {
    let item: ComicListItem
    let chapter: ComicChapter
    let chapterIndex: Int
    let service: ComicContentService
    let account: PlatformAccount?
    let localCommentsProvider: ((ComicChapter, Int) async -> [ComicComment])?

    @State private var state = ReaderChapterCommentsState.loading
    @State private var currentPage = 1
    @State private var canLoadMore = false
    @State private var isLoadingMore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                    Text("章节评论")
                        .font(.headline)
                    Spacer()
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)

                switch state {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("正在加载评论")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                case .loaded(let comments):
                    if comments.isEmpty {
                        ReaderCommentsEmptyView(title: "暂无章节评论", subtitle: "当前章节还没有可显示的评论。")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(comments) { comment in
                                ReaderCommentRow(comment: comment)
                            }
                        }

                        if canLoadMore {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                if isLoadingMore {
                                    HStack {
                                        ProgressView()
                                            .tint(.white)
                                        Text("正在加载")
                                    }
                                } else {
                                    Label("加载更多评论", systemImage: "chevron.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .disabled(isLoadingMore)
                            .frame(maxWidth: .infinity)
                        }
                    }
                case .failed(let message):
                    ReaderCommentsEmptyView(title: "评论加载失败", subtitle: message)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: loadID) {
            await load()
        }
    }

    private var loadID: String {
        "\(item.platform.id)-\(item.id)-\(chapter.id)-\(chapterIndex)"
    }

    @MainActor
    private func load() async {
        state = .loading
        currentPage = 1
        canLoadMore = false
        isLoadingMore = false
        if let localCommentsProvider {
            let comments = await localCommentsProvider(chapter, chapterIndex)
            state = .loaded(comments)
            return
        }

        do {
            let comments = try await service.loadChapterComments(item: item, chapter: chapter, account: account)
            state = .loaded(comments)
            canLoadMore = supportsPagination && !comments.isEmpty
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore,
              localCommentsProvider == nil,
              canLoadMore,
              case .loaded(let comments) = state else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let pageComments = try await service.loadChapterComments(
                item: item,
                chapter: chapter,
                account: account,
                page: nextPage
            )
            let existingIDs = Set(comments.map(\.id))
            let newComments = pageComments.filter { !existingIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                canLoadMore = false
                return
            }
            currentPage = nextPage
            state = .loaded(comments + newComments)
        } catch {
            canLoadMore = false
        }
    }

    private var supportsPagination: Bool {
        item.platform == .picacg || item.platform == .jmComic
    }
}

private enum ReaderChapterCommentsState {
    case loading
    case loaded([ComicComment])
    case failed(String)
}

private struct ReaderCommentsEmptyView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.horizontal, 24)
    }
}

private struct ReaderCommentRow: View {
    let comment: ComicComment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                CachedRemoteImageView(
                    url: comment.avatarURL,
                    accentColor: .white,
                    contentMode: .fill,
                    maxPixelSize: 128,
                    placeholderSystemImage: "person.crop.circle"
                )
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let timeText = comment.timeText, !timeText.isEmpty {
                        Text(timeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer()
            }

            Text(comment.content)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let likesCount = comment.likesCount {
                    Label("\(likesCount)", systemImage: "heart")
                }
                if let replyCount = comment.replyCount {
                    Label("\(replyCount)", systemImage: "text.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reply.author)
                                .font(.caption.weight(.semibold))
                            Text(reply.content)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.white.opacity(0.76))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ReaderChapterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [ComicChapter]
    let selectedIndex: Int
    let listContext: ComicReaderListContext?
    let onSelectReadingListEntry: (ReadingListEntry) -> Void
    let onSelect: (Int) -> Void
    @State private var selectedTab = ReaderChapterSheetTab.chapters

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(selectedTab.title(hasReadingList: listContext != nil))
                .toolbar {
                    #if os(iOS)
                    if selectedTab == .readingList, let listContext {
                        ToolbarItem(placement: .picaxTopBarLeading) {
                            EditButton()
                                .disabled(listContext.entries.isEmpty)
                        }
                    }
                    #endif

                    ToolbarItem(placement: .picaxTopBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let listContext {
            VStack(spacing: 0) {
                Picker("内容", selection: $selectedTab) {
                    ForEach(ReaderChapterSheetTab.allCases) { tab in
                        Text(tab.title)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                switch selectedTab {
                case .chapters:
                    chapterList
                case .readingList:
                    readingList(listContext)
                }
            }
        } else {
            chapterList
        }
    }

    private var chapterList: some View {
        List {
            Section {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack {
                            ComicChapterRow(chapter: chapter)
                            Spacer()
                            if index == selectedIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .picaxInsetGroupedListStyle()
    }

    private func readingList(_ listContext: ComicReaderListContext) -> some View {
        List {
            if listContext.entries.isEmpty {
                ContentUnavailableView("阅读列表为空", systemImage: "list.bullet.rectangle")
                    .listRowBackground(Color.clear)
            } else {
                Section("阅读列表") {
                    ForEach(listContext.entries) { entry in
                        Button {
                            onSelectReadingListEntry(entry)
                            dismiss()
                        } label: {
                            ReadingListEntryRow(
                                entry: entry,
                                isCurrent: entry.id == listContext.currentEntryID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: listContext.removeEntries)
                }
            }
        }
        .picaxInsetGroupedListStyle()
    }
}

private enum ReaderChapterSheetTab: String, CaseIterable, Identifiable {
    case chapters
    case readingList

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters:
            return "章节"
        case .readingList:
            return "阅读列表"
        }
    }

    func title(hasReadingList: Bool) -> String {
        hasReadingList ? title : "章节"
    }
}

@MainActor
private final class ComicReaderViewModel: ObservableObject {
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

    func scheduleImagePreload(afterPage index: Int, count: Int, delay: Double, targetPixelWidth: Int?) {
        preloadDebounceTask?.cancel()
        guard case .loaded(let images) = state else { return }
        let boundedCount = min(max(count, 0), 12)
        guard boundedCount > 0, index + 1 < images.count else {
            preloadTask?.cancel()
            return
        }

        let startIndex = index + 1
        let endIndex = min(index + boundedCount, images.count - 1)
        let preloadItems = images[startIndex...endIndex]
            .map(\.urlString)
            .map { (urlString: $0, key: preloadKey(urlString: $0, targetPixelWidth: targetPixelWidth)) }
            .filter { !preloadedImageKeys.contains($0.key) }
        let urlStrings = preloadItems.map(\.urlString)
        let preloadKeys = preloadItems.map(\.key)
        guard !urlStrings.isEmpty else { return }

        let chapterID = loadedChapterID
        let boundedDelay = min(max(delay, 0), 5)
        if boundedDelay <= 0 {
            startImagePreload(urlStrings: urlStrings, preloadKeys: preloadKeys, chapterID: chapterID, pageIndex: index, targetPixelWidth: targetPixelWidth)
            return
        }

        preloadDebounceTask = Task { [weak self, urlStrings, preloadKeys, chapterID, index, boundedDelay, targetPixelWidth] in
            let delayNanoseconds = UInt64((boundedDelay * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedChapterID == chapterID, self.currentPageIndex == index else { return }
                self.startImagePreload(urlStrings: urlStrings, preloadKeys: preloadKeys, chapterID: chapterID, pageIndex: index, targetPixelWidth: targetPixelWidth)
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

private enum ReaderLoadState {
    case idle
    case loading
    case loaded([ComicChapterImage])
    case failed(String)
}

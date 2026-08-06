import SwiftUI

enum ReaderChapterEndAction: Equatable {
    case nextChapter
    case nextBook

    var title: String {
        switch self {
        case .nextChapter: "下一章"
        case .nextBook: "下一本"
        }
    }

    var systemImage: String {
        switch self {
        case .nextChapter: "arrow.down.doc"
        case .nextBook: "books.vertical.fill"
        }
    }
}

struct ReaderLoadingContent: View {
    let uiToggleMode: ReaderUIToggleMode
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let doubleTapZoomEnabled: Bool
    let readingMode: ReaderReadingMode
    let onToggleUI: () -> Void

    var body: some View {
        GeometryReader { geometry in
            LoadingStateView(title: "正在加载章节")
                .frame(width: geometry.size.width, height: geometry.size.height)
                .readerInteractionGesture(
                    size: geometry.size,
                    mode: uiToggleMode,
                    tapPagingEnabled: false,
                    tapPagingEdgePercent: tapPagingEdgePercent,
                    tapPagingInverted: tapPagingInverted,
                    doubleTapZoomEnabled: doubleTapZoomEnabled,
                    readingMode: readingMode,
                    toggleUI: onToggleUI,
                    turnPage: { _ in }
                )
        }
        .ignoresSafeArea(.container)
    }
}

struct ReaderLoadFailureContent: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct ReaderChapterMenu: View {
    let chapters: [ComicChapter]
    let selectedIndex: Int
    let navigationTitle: String
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                Button {
                    onSelect(index)
                } label: {
                    if index == selectedIndex {
                        Label(title(for: chapter, at: index), systemImage: "checkmark")
                    } else {
                        Text(title(for: chapter, at: index))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(navigationTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("章节")
    }

    private func title(for chapter: ComicChapter, at index: Int) -> String {
        chapter.title.isEmpty ? "第 \(index + 1) 章" : chapter.title
    }
}

struct ReaderOptionsMenu: View {
    let isAutoPaging: Bool
    @Binding var autoPagingInterval: Double
    let autoPagingIntervalOptions: [Int]
    @Binding var autoPagingDistancePercent: Int
    let autoPagingDistanceOptions: [Int]
    let readingMode: ReaderReadingMode
    @Binding var smoothContinuousAutoPaging: Bool
    @Binding var autoPagingTurnsChapter: Bool
    @Binding var wholeBookContinuousReading: Bool
    let deletesLocalDownloadOnExit: Bool?
    let onToggleAutoPaging: () -> Void
    let onToggleBurnAfterReading: () -> Void
    let onOpenDetail: () -> Void
    let onSelectProgress: () -> Void

    var body: some View {
        Menu {
            Section("自动翻页") {
                Button(action: onToggleAutoPaging) {
                    Label(
                        isAutoPaging ? "停止自动翻页" : "开始自动翻页",
                        systemImage: isAutoPaging ? "timer.circle.fill" : "timer"
                    )
                }

                Menu("翻页间隔") {
                    ForEach(autoPagingIntervalOptions, id: \.self) { seconds in
                        Button {
                            autoPagingInterval = Double(seconds)
                        } label: {
                            if Int(autoPagingInterval.rounded()) == seconds {
                                Label("\(seconds) 秒", systemImage: "checkmark")
                            } else {
                                Text("\(seconds) 秒")
                            }
                        }
                    }
                }

                Menu("翻页距离") {
                    ForEach(autoPagingDistanceOptions, id: \.self) { percent in
                        Button {
                            autoPagingDistancePercent = percent
                        } label: {
                            if autoPagingDistancePercent == percent {
                                Label("\(percent)% 屏幕高度", systemImage: "checkmark")
                            } else {
                                Text("\(percent)% 屏幕高度")
                            }
                        }
                    }
                }
                .disabled(readingMode != .topToBottomContinuous)

                Toggle(isOn: $smoothContinuousAutoPaging) {
                    Label("平滑持续滚动", systemImage: "arrow.down")
                }
                .disabled(readingMode != .topToBottomContinuous)

                Toggle(isOn: $autoPagingTurnsChapter) {
                    Label("自动进入下一章", systemImage: "arrow.down.doc")
                }
                .disabled(wholeBookContinuousReading && readingMode != .pageCurl)
            }

            if let deletesLocalDownloadOnExit {
                Section("本地下载") {
                    Button(action: onToggleBurnAfterReading) {
                        Label(
                            deletesLocalDownloadOnExit ? "关闭阅后即焚" : "开启阅后即焚",
                            systemImage: deletesLocalDownloadOnExit ? "flame.fill" : "flame"
                        )
                    }
                }
            }

            Section {
                Toggle(isOn: $wholeBookContinuousReading) {
                    Label("整卷连续阅读", systemImage: "rectangle.stack.fill")
                }
                .disabled(readingMode == .pageCurl)

                Button(action: onOpenDetail) {
                    Label("打开详情页", systemImage: "info.circle")
                }

                Button(action: onSelectProgress) {
                    Label("选择阅读进度", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
    }
}

struct ReaderChromeOverlayConfiguration {
    let showsReaderUI: Bool
    let isAutoPaging: Bool
    let showsReadingListButton: Bool
    let canMovePreviousBook: Bool
    let canLoadPreviousChapter: Bool
    let canLoadNextChapter: Bool
    let canMoveNextBook: Bool
    let toastMessage: String?
    let chapterEndAction: ReaderChapterEndAction?
    let isChapterEndActionLoading: Bool
    let chapterEndButtonPosition: ReaderOverlayPosition
    let chapterEndButtonHorizontalInset: CGFloat
    let chapterEndButtonVerticalPadding: CGFloat
}

struct ReaderChromeOverlayLayer: View {
    let configuration: ReaderChromeOverlayConfiguration
    let onToggleAutoPaging: () -> Void
    let onShowChapters: () -> Void
    let onShowReadingList: () -> Void
    let onMovePreviousBook: () -> Void
    let onLoadPreviousChapter: () -> Void
    let onLoadNextChapter: () -> Void
    let onMoveNextBook: () -> Void
    let onChapterEndAction: (ReaderChapterEndAction) -> Void

    var body: some View {
        ZStack {
            ReaderBottomChromeOverlay(
                isVisible: configuration.showsReaderUI,
                isAutoPaging: configuration.isAutoPaging,
                showsReadingListButton: configuration.showsReadingListButton,
                canMovePreviousBook: configuration.canMovePreviousBook,
                canLoadPreviousChapter: configuration.canLoadPreviousChapter,
                canLoadNextChapter: configuration.canLoadNextChapter,
                canMoveNextBook: configuration.canMoveNextBook,
                onToggleAutoPaging: onToggleAutoPaging,
                onShowChapters: onShowChapters,
                onShowReadingList: onShowReadingList,
                onMovePreviousBook: onMovePreviousBook,
                onLoadPreviousChapter: onLoadPreviousChapter,
                onLoadNextChapter: onLoadNextChapter,
                onMoveNextBook: onMoveNextBook
            )

            if let toastMessage = configuration.toastMessage {
                ReaderToastView(message: toastMessage)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 86)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let action = configuration.chapterEndAction {
                ReaderChapterEndActionButton(
                    title: action.title,
                    systemImage: action.systemImage,
                    isLoading: configuration.isChapterEndActionLoading
                ) {
                    onChapterEndAction(action)
                }
                .padding(.horizontal, configuration.chapterEndButtonHorizontalInset)
                .padding(
                    .top,
                    configuration.chapterEndButtonPosition.isBottom
                        ? 0
                        : configuration.chapterEndButtonVerticalPadding
                )
                .padding(
                    .bottom,
                    configuration.chapterEndButtonPosition.isBottom
                        ? configuration.chapterEndButtonVerticalPadding
                        : 0
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: configuration.chapterEndButtonPosition.alignment
                )
                .transition(
                    .scale(
                        scale: 0.9,
                        anchor: configuration.chapterEndButtonPosition.anchor
                    )
                    .combined(with: .opacity)
                )
            }
        }
    }
}

struct ReaderAuxiliaryOverlayConfiguration {
    let showsProgress: Bool
    let progressTitle: String
    let progress: Double
    let progressStyle: ReaderProgressStyle
    let showsPageLabel: Bool
    let backgroundOpacity: Double
    let usesProgressGlassBackground: Bool
    let progressPosition: ReaderProgressPosition
    let progressBottomPadding: CGFloat
    let allowsProgressSelection: Bool
    let showsSystemStatus: Bool
    let systemStatusStyle: ReaderSystemStatusStyle
    let usesSystemStatusGlassBackground: Bool
    let systemStatusPosition: ReaderOverlayPosition
    let systemStatusInsets: EdgeInsets
}

struct ReaderAuxiliaryOverlayLayer: View {
    let configuration: ReaderAuxiliaryOverlayConfiguration
    let onSelectProgress: () -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if configuration.showsProgress {
                    progressControl
                        .padding(.horizontal, 16)
                        .padding(.bottom, configuration.progressBottomPadding)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: configuration.progressPosition.alignment
                        )
                }

                if configuration.showsSystemStatus {
                    ReaderSystemStatusOverlay(
                        style: configuration.systemStatusStyle,
                        backgroundOpacity: configuration.backgroundOpacity,
                        usesGlassBackground: configuration.usesSystemStatusGlassBackground
                    )
                    .padding(configuration.systemStatusInsets)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: configuration.systemStatusPosition.alignment
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private var progressControl: some View {
        if configuration.allowsProgressSelection {
            Button(action: onSelectProgress) {
                progressOverlay
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择阅读进度")
        } else {
            progressOverlay
                .allowsHitTesting(false)
        }
    }

    private var progressOverlay: some View {
        ReaderProgressOverlay(
            title: configuration.progressTitle,
            progress: configuration.progress,
            style: configuration.progressStyle,
            showsPageLabel: configuration.showsPageLabel,
            backgroundOpacity: configuration.backgroundOpacity,
            usesGlassBackground: configuration.usesProgressGlassBackground
        )
        .contentShape(Capsule(style: .continuous))
    }
}

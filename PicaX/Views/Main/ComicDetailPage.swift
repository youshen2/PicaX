import Combine
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ComicDetailPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var readLater: ReadLaterService

    let item: ComicListItem
    let service: ComicContentService
    @StateObject private var viewModel: ComicDetailViewModel
    @State private var favoriteContext: FavoriteSheetContext?
    @State private var downloadContext: DownloadSheetContext?
    @State private var isLiking = false
    @State private var isLiked = false
    @State private var likeErrorMessage: String?

    init(item: ComicListItem, service: ComicContentService = ComicContentService()) {
        self.item = item
        self.service = service
        _viewModel = StateObject(wrappedValue: ComicDetailViewModel(item: item, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingComicDetailView(accentColor: item.accentColor)
            case .loaded(let detail):
                ComicDetailContent(detail: detail, service: service) {
                    await load(force: true)
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
        .background(AppColor.groupedBackground)
        .navigationTitle("漫画详情")
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .sheet(item: $favoriteContext) { context in
            FavoriteSelectionSheet(
                item: context.item,
                service: service,
                account: platformAccounts.account(for: context.item.platform)
            )
            .picaxPresentationDetents([.medium, .large])
        }
        .sheet(item: $downloadContext) { context in
            DownloadSelectionSheet(detail: context.detail)
                .picaxPresentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    if let detail = viewModel.loadedDetail {
                        downloadContext = DownloadSheetContext(detail: detail)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .disabled(!canDownloadLoadedDetail)
                .accessibilityLabel("下载")

                if service.supportsLike(platform: item.platform) {
                    Button {
                        Task {
                            await setLikeState(!isLiked)
                        }
                    } label: {
                        likeToolbarContent
                    }
                    .disabled(viewModel.loadedDetail == nil || isLiking)
                    .accessibilityLabel(isLiked ? "取消点赞" : "点赞")
                }

                Button {
                    if let detail = viewModel.loadedDetail {
                        favoriteContext = FavoriteSheetContext(item: detail.item)
                    }
                } label: {
                    Image(systemName: "heart")
                }
                .disabled(viewModel.loadedDetail == nil)
                .accessibilityLabel("收藏")

                Button {
                    readLater.toggle(readLaterItem)
                } label: {
                    readLaterToolbarContent
                }
                .accessibilityLabel(readLater.contains(readLaterItem) ? "移出稍后再读" : "稍后再读")
            }
        }
        .task {
            await load()
        }
        .onReceive(viewModel.$state) { state in
            if case .loaded(let detail) = state, let loadedIsLiked = detail.isLiked {
                isLiked = loadedIsLiked
            }
        }
        .alert("点赞失败", isPresented: likeErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(likeErrorMessage ?? "")
        }
    }

    private func load(force: Bool = false) async {
        let wasLoaded = viewModel.loadedDetail != nil
        await viewModel.load(account: platformAccounts.account(for: item.platform), force: force)
        if (!wasLoaded || force), let detail = viewModel.loadedDetail {
            readingHistory.recordViewed(detail.item)
        }
        if let loadedIsLiked = viewModel.loadedDetail?.isLiked {
            isLiked = loadedIsLiked
        }
    }

    private var canDownloadLoadedDetail: Bool {
        guard let detail = viewModel.loadedDetail else { return false }
        return !detail.chapters.isEmpty
    }

    private var readLaterItem: ComicListItem {
        viewModel.loadedDetail?.item ?? item
    }

    @ViewBuilder
    private var likeToolbarContent: some View {
        if isLiking {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .symbolRenderingMode(isLiked ? .hierarchical : .monochrome)
                .foregroundStyle(isLiked ? item.accentColor : .primary)
                .accessibilityHint(isLiked ? "再次点击取消点赞" : "")
        }
    }

    @ViewBuilder
    private var readLaterToolbarContent: some View {
        let isSaved = readLater.contains(readLaterItem)
        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            .symbolRenderingMode(isSaved ? .hierarchical : .monochrome)
            .foregroundStyle(isSaved ? item.accentColor : .primary)
    }

    private var likeErrorBinding: Binding<Bool> {
        Binding {
            likeErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                likeErrorMessage = nil
            }
        }
    }

    @MainActor
    private func setLikeState(_ newValue: Bool) async {
        guard let detail = viewModel.loadedDetail, !isLiking else { return }
        isLiking = true
        likeErrorMessage = nil
        defer { isLiking = false }

        do {
            try await service.setComicLiked(
                item: detail.item,
                isLiked: newValue,
                account: platformAccounts.account(for: detail.item.platform)
            )
            isLiked = newValue
            await viewModel.updateLikeState(newValue, account: platformAccounts.account(for: detail.item.platform))
        } catch where error.isTaskCancellation {
            return
        } catch {
            likeErrorMessage = error.localizedDescription
        }
    }
}

private struct ComicDetailContent: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(DetailSettingsKey.chapterSortOrder) private var chapterSortOrder = ComicDetailChapterSortOrder.ascending.rawValue
    @AppStorage(DetailSettingsKey.showsChaptersAsSection) private var showsChaptersAsSection = false
    @AppStorage(DetailSettingsKey.contentOrder) private var contentOrderRaw = ComicDetailContentSectionKind.defaultRawValue
    @AppStorage(DownloadSettingsKey.recordsDownloadedReadingHistory) private var recordsDownloadedReadingHistory = true
    let detail: ComicDetailInfo
    let service: ComicContentService
    @State private var commentSheet: CommentSheetContext?
    @State private var readerTarget: ComicReaderTarget?
    @State private var localReaderRequest: DownloadedComicReaderRequest?
    @State private var selectedTag: ComicTagReference?
    @State private var relatedDetailRequest: ComicListDetailRequest?
    @State private var relatedReaderRequest: ComicListReaderRequest?
    @Namespace private var navigationTransitionNamespace
    let onRefresh: () async -> Void

    var body: some View {
        Group {
            List {
                Section {
                    ComicDetailHeader(
                        detail: detail,
                        showsChapterButton: !showsChaptersAsSection,
                        canOpenLocalReader: downloadedRecord?.chapters.isEmpty == false
                    ) { target in
                        readerTarget = target
                    } onOpenLocalReader: {
                        openDownloadedReader()
                    }
                        .padding(.vertical, 4)
                }

                ForEach(contentOrder) { section in
                    contentSection(for: section)
                }
            }
            .picaxInsetGroupedListStyle()
            .refreshable {
                await onRefresh()
            }
        }
        .picaxSensitiveImageContent(detail.item.coverURL != nil)
        .picaxNavigationDestination(item: $readerTarget) { target in
            ComicReaderPage(
                detail: detail,
                initialChapterIndex: target.chapterIndex,
                ignoresHistoryProgress: target.ignoresProgress,
                service: service
            )
        }
        .picaxNavigationDestination(item: $localReaderRequest) { request in
            ComicReaderPage(
                detail: request.detail,
                initialChapterIndex: request.initialChapterIndex,
                initialPageIndex: request.initialPageIndex,
                ignoresHistoryProgress: request.ignoresHistoryProgress,
                recordsReadingHistory: request.recordsReadingHistory,
                service: service,
                localChapterImageProvider: { _, chapterIndex in
                    guard request.localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                    return await downloadService.localChapterImages(for: request.record, chapterIndex: request.localChapterIndexes[chapterIndex])
                },
                localChapterCommentsProvider: { _, chapterIndex in
                    guard request.localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                    return await downloadService.localChapterComments(for: request.record, chapterIndex: request.localChapterIndexes[chapterIndex])
                },
                historyChapterIndexResolver: { chapterIndex in
                    guard request.localChapterIndexes.indices.contains(chapterIndex) else { return chapterIndex }
                    return request.localChapterIndexes[chapterIndex]
                }
            )
        }
        .picaxNavigationDestination(item: $selectedTag) { tag in
            ComicTagComicsPage(tag: tag, service: service)
        }
        .picaxComicDetailDestination(
            item: $relatedDetailRequest,
            in: navigationTransitionNamespace,
            service: service
        )
        .picaxNavigationDestination(item: $relatedReaderRequest) { request in
            ComicReaderPage(
                detail: request.detail,
                initialChapterIndex: 0,
                ignoresHistoryProgress: request.ignoresHistoryProgress,
                service: service
            )
        }
        .sheet(item: $commentSheet) { context in
            ComicCommentsSheet(
                item: context.item,
                service: service,
                account: platformAccounts.account(for: context.item.platform)
            )
            .picaxPresentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
    }

    private func hasReadingProgress(for item: ComicListItem) -> Bool {
        readingHistory.hasReadingProgress(for: item)
    }

    private var downloadedRecord: DownloadRecord? {
        downloadService.record(for: detail.item)
    }

    private func openDownloadedReader() {
        guard let record = downloadedRecord else { return }
        let downloadedChapters = record.chapters.sorted { $0.index < $1.index }
        guard !downloadedChapters.isEmpty else { return }

        let localChapterIndexes = downloadedChapters.map(\.index)
        let progress = readingHistory.record(for: record.item)?.progress
        let initialChapterIndex: Int
        let initialPageIndex: Int
        if let progress,
           (progress.status == .reading || progress.status == .finished),
           let compactIndex = localChapterIndexes.firstIndex(of: progress.chapterIndex) {
            initialChapterIndex = compactIndex
            initialPageIndex = progress.pageIndex
        } else {
            initialChapterIndex = 0
            initialPageIndex = 0
        }

        localReaderRequest = DownloadedComicReaderRequest(
            record: record,
            detail: localDetail(for: record, downloadedChapters: downloadedChapters),
            localChapterIndexes: localChapterIndexes,
            initialChapterIndex: initialChapterIndex,
            initialPageIndex: initialPageIndex,
            ignoresHistoryProgress: true,
            recordsReadingHistory: recordsDownloadedReadingHistory
        )
    }

    private func localDetail(for record: DownloadRecord, downloadedChapters: [DownloadedChapterRecord]) -> ComicDetailInfo {
        let sourceDetail = record.detail ?? detail
        var localDetail = ComicDetailInfo(
            item: sourceDetail.item,
            description: sourceDetail.description,
            tagGroups: sourceDetail.tagGroups,
            chapters: downloadedChapters.map(\.chapter),
            related: sourceDetail.related,
            updatedText: sourceDetail.updatedText
        )
        localDetail.isLiked = sourceDetail.isLiked
        localDetail.uploader = sourceDetail.uploader
        return localDetail
    }

    private var sortedChapterDisplayItems: [ComicChapterDisplayItem] {
        ComicChapterDisplayItem.items(from: detail.chapters, sortOrder: selectedChapterSortOrder)
    }

    private var selectedChapterSortOrder: ComicDetailChapterSortOrder {
        ComicDetailChapterSortOrder(rawValue: chapterSortOrder) ?? .ascending
    }

    private var contentOrder: [ComicDetailContentSectionKind] {
        ComicDetailContentSectionKind.normalizedOrder(from: contentOrderRaw)
    }

    @ViewBuilder
    private func contentSection(for section: ComicDetailContentSectionKind) -> some View {
        switch section {
        case .comments:
            if detail.item.supportsComments {
                Section {
                    Button {
                        commentSheet = CommentSheetContext(item: detail.item)
                    } label: {
                        Label("查看评论", systemImage: "text.bubble")
                    }
                }
            }

        case .actions:
            if detail.item.copyAction != nil {
                Section("操作") {
                    ComicCopyActionButton(item: detail.item)
                }
            }

        case .chapters:
            if showsChaptersAsSection, !detail.chapters.isEmpty {
                Section {
                    ForEach(sortedChapterDisplayItems) { item in
                        Button {
                            readerTarget = ComicReaderTarget(chapterIndex: item.originalIndex, ignoresProgress: true)
                        } label: {
                            ComicChapterRow(chapter: item.chapter)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    ComicChaptersSectionHeader(
                        chapterCount: detail.chapters.count,
                        sortOrder: $chapterSortOrder
                    )
                }
            }

        case .description:
            if !detail.description.isEmpty {
                Section("简介") {
                    Text(detail.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

        case .uploader:
            if let uploader = detail.uploader {
                Section("上传者") {
                    ComicUploaderInfoRow(uploader: uploader, accentColor: detail.item.accentColor) { tag in
                        selectedTag = tag
                    }
                }
            }

        case .information:
            Section("信息") {
                ComicInfoLine(title: "来源", value: detail.item.platformTitle)
                if let authorText = detail.selectableAuthorText {
                    ComicInfoLine(title: "作者", value: authorText)
                }
                if let pageText = detail.item.pageText {
                    ComicInfoLine(title: "页数", value: pageText)
                }
                if let updatedText = detail.updatedText, !updatedText.isEmpty {
                    ComicInfoLine(title: "更新", value: updatedText)
                }
                ComicInfoLine(title: "编号", value: detail.item.target, monospaced: true)
            }

        case .tags:
            ForEach(detail.tagGroups) { group in
                Section(group.title) {
                    FlowTagLinks(tags: group.tags, color: detail.item.accentColor) { tag in
                        selectedTag = tag
                    }
                    .padding(.vertical, 4)
                }
            }

        case .related:
            if !detail.related.isEmpty {
                Section("相关推荐") {
                    ForEach(Array(detail.related.prefix(6))) { comic in
                        ComicListActionLink(
                            item: comic,
                            service: service,
                            hasReadingProgress: hasReadingProgress(for: comic),
                            comicDetailTransitionNamespace: navigationTransitionNamespace,
                            openDetail: { relatedDetailRequest = ComicListDetailRequest(item: $0) },
                            openReader: { relatedReaderRequest = $0 }
                        )
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct ComicUploaderInfoRow: View {
    let uploader: ComicUploaderInfo
    let accentColor: Color
    let onSelect: (ComicTagReference) -> Void

    var body: some View {
        Button {
            if let tag = uploader.tag {
                onSelect(tag)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    CachedRemoteImageView(url: uploader.avatarURL, accentColor: accentColor, contentMode: .fill, maxPixelSize: 128)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    if let frameURL = uploader.frameURL {
                        CachedRemoteImageView(url: frameURL, accentColor: accentColor, contentMode: .fit, maxPixelSize: 160)
                            .frame(width: 62, height: 62)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(uploader.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(uploader.levelText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let slogan = uploader.slogan, !slogan.isEmpty {
                        Text(slogan)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if uploader.tag != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(uploader.tag == nil)
    }
}

private extension ComicDetailInfo {
    var selectableAuthorText: String? {
        let authorTitles = tagGroups
            .first { group in
                let title = group.title.lowercased()
                return title.contains("作者") || title.contains("artist")
            }?
            .tags
            .map(\.title) ?? []
        let uniqueAuthors = uniqueNonEmpty(authorTitles)
        if !uniqueAuthors.isEmpty {
            return uniqueAuthors.joined(separator: "、")
        }

        switch item.platform {
        case .picacg, .jmComic, .nhentai, .hitomi:
            let subtitle = item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return subtitle.isEmpty ? nil : subtitle
        case .eHentai, .htManga:
            return nil
        }
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

private struct ComicDetailHeader: View {
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @AppStorage(DetailSettingsKey.usesCoverAccent) private var usesCoverAccent = true
    let detail: ComicDetailInfo
    let showsChapterButton: Bool
    let canOpenLocalReader: Bool
    let onOpenReader: (ComicReaderTarget) -> Void
    let onOpenLocalReader: () -> Void
    @State private var showsCoverPreview = false
    @State private var showsChapters = false
    @State private var coverColor: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                showsCoverPreview = true
            } label: {
                ComicCoverView(url: detail.item.coverURL, accentColor: detail.item.accentColor, width: 102, height: 136)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(titleText)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.item.subtitle.isEmpty {
                        Text(detail.item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(detail.item.platformTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pageText = detail.item.pageText {
                        Text(pageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let readingProgressText {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: readingProgressSystemImage)
                                Text(readingProgressText)
                                    .lineLimit(1)
                                if let readingProgressPercentText {
                                    Text(readingProgressPercentText)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(detail.item.accentColor)

                            if let readingProgressFraction {
                                ProgressView(value: readingProgressFraction)
                                    .tint(detail.item.accentColor)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    let accentColor = usesCoverAccent ? (coverColor ?? detail.item.accentColor) : detail.item.accentColor

                    Button {
                        onOpenReader(ComicReaderTarget(chapterIndex: 0, ignoresProgress: false))
                    } label: {
                        Text(readButtonTitle)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(readButtonColor(accentColor), in: Capsule())
                    .glassProminentIfAvailable(tint: readButtonColor(accentColor))
                    .disabled(detail.chapters.isEmpty)

                    if canOpenLocalReader {
                        Button(action: onOpenLocalReader) {
                            Image(systemName: "internaldrive")
                                .font(.headline)
                                .frame(width: 44, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                        .background(accentColor.opacity(0.16), in: Circle())
                        .accessibilityLabel("从本地阅读")
                        .help("从本地阅读")
                    }

                    if showsChapterButton {
                        Button {
                            showsChapters = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.headline)
                                .frame(width: 44, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                        .background(accentColor.opacity(0.16), in: Circle())
                        .disabled(detail.chapters.isEmpty)
                        .accessibilityLabel("章节")
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copy(titleText)
            } label: {
                Label("复制标题", systemImage: "doc.on.doc")
            }

            Button {
                onOpenReader(ComicReaderTarget(chapterIndex: 0, ignoresProgress: true))
            } label: {
                Label("忽略阅读进度", systemImage: "arrow.counterclockwise")
            }
            .disabled(detail.chapters.isEmpty)
        }
        .sheet(isPresented: $showsCoverPreview) {
            ZoomableCoverPreview(url: detail.item.coverURL, accentColor: detail.item.accentColor)
        }
        .sheet(isPresented: $showsChapters) {
            ChapterListSheet(chapters: detail.chapters) { index in
                showsChapters = false
                onOpenReader(ComicReaderTarget(chapterIndex: index, ignoresProgress: true))
            }
                .picaxPresentationDetents([.medium, .large])
        }
        .task(id: "\(detail.item.coverURLString)-\(usesCoverAccent)") {
            guard usesCoverAccent else {
                coverColor = nil
                return
            }
            coverColor = await CoverColorSampler.averageColor(url: detail.item.coverURL)
        }
    }

    private var historyProgress: ReadingProgress? {
        readingHistory.record(for: detail.item)?.progress
    }

    private var hasReadingProgress: Bool {
        guard let historyProgress else { return false }
        return historyProgress.status == .reading || historyProgress.status == .finished
    }

    private var readButtonTitle: String {
        if detail.chapters.isEmpty {
            return "加载章节中"
        }
        return hasReadingProgress ? "继续阅读" : "阅读"
    }

    private var readingProgressText: String? {
        guard let record = readingHistory.record(for: detail.item), record.isReadingRecord else { return nil }
        return record.progressText
    }

    private var readingProgressSystemImage: String {
        historyProgress?.status == .finished ? "checkmark.circle.fill" : "book.circle"
    }

    private var readingProgressPercentText: String? {
        guard let readingProgressFraction else { return nil }
        return "\(Int((readingProgressFraction * 100).rounded()))%"
    }

    private var readingProgressFraction: Double? {
        guard let progress = historyProgress else { return nil }
        switch progress.status {
        case .viewed:
            return nil
        case .finished:
            return 1
        case .reading:
            return readingProgressFraction(for: progress)
        }
    }

    private var titleText: String {
        detail.item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private func readButtonColor(_ accentColor: Color) -> Color {
        detail.chapters.isEmpty ? accentColor.opacity(0.38) : accentColor
    }

    private func readingProgressFraction(for progress: ReadingProgress) -> Double? {
        let currentPageFraction: Double
        if progress.totalPages > 0 {
            currentPageFraction = Double(min(max(progress.pageIndex + 1, 0), progress.totalPages)) / Double(progress.totalPages)
        } else {
            currentPageFraction = 0
        }

        if progress.totalChapters > 0 {
            let completedChapters = progress.readChapterIndexes.subtracting([progress.chapterIndex]).count
            return min(max((Double(completedChapters) + currentPageFraction) / Double(progress.totalChapters), 0), 1)
        }

        guard progress.totalPages > 0 else { return nil }
        return min(max(currentPageFraction, 0), 1)
    }
}

private struct ComicReaderTarget: Identifiable, Hashable {
    let chapterIndex: Int
    let ignoresProgress: Bool
    var id: String { "\(chapterIndex)-\(ignoresProgress)" }
}

private struct FavoriteSheetContext: Identifiable {
    let item: ComicListItem
    var id: String { "\(item.platform.id)-\(item.id)" }
}

private struct DownloadSheetContext: Identifiable {
    let detail: ComicDetailInfo
    var id: String { "\(detail.item.platform.id)-\(detail.item.id)" }
}

private struct CommentSheetContext: Identifiable {
    let item: ComicListItem
    var id: String { "\(item.platform.id)-\(item.id)" }
}

private struct ChapterListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DetailSettingsKey.chapterSortOrder) private var chapterSortOrder = ComicDetailChapterSortOrder.ascending.rawValue
    let chapters: [ComicChapter]
    var onSelect: ((Int) -> Void)?

    var body: some View {
        PicaxNavigationContainer {
            List {
                Section {
                    ForEach(sortedChapterDisplayItems) { item in
                        if let onSelect {
                            Button {
                                onSelect(item.originalIndex)
                            } label: {
                                ComicChapterRow(chapter: item.chapter)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ComicChapterRow(chapter: item.chapter)
                        }
                    }
                } header: {
                    ComicChaptersSectionHeader(
                        chapterCount: chapters.count,
                        sortOrder: $chapterSortOrder
                    )
                }
            }
            .picaxInsetGroupedListStyle()
            .navigationTitle("章节")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
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

    private var sortedChapterDisplayItems: [ComicChapterDisplayItem] {
        ComicChapterDisplayItem.items(from: chapters, sortOrder: selectedChapterSortOrder)
    }

    private var selectedChapterSortOrder: ComicDetailChapterSortOrder {
        ComicDetailChapterSortOrder(rawValue: chapterSortOrder) ?? .ascending
    }
}

private struct ComicChapterDisplayItem: Identifiable {
    let chapter: ComicChapter
    let originalIndex: Int

    var id: String {
        "\(originalIndex)-\(chapter.id)"
    }

    static func items(from chapters: [ComicChapter], sortOrder: ComicDetailChapterSortOrder) -> [ComicChapterDisplayItem] {
        let items = chapters.enumerated().map { index, chapter in
            ComicChapterDisplayItem(chapter: chapter, originalIndex: index)
        }

        switch sortOrder {
        case .ascending:
            return items
        case .descending:
            return Array(items.reversed())
        }
    }
}

private struct ComicChaptersSectionHeader: View {
    let chapterCount: Int
    @Binding var sortOrder: String

    var body: some View {
        HStack {
            Text("章节")
            Text("\(chapterCount)")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Menu {
                Picker("章节排序", selection: $sortOrder) {
                    ForEach(ComicDetailChapterSortOrder.allCases) { order in
                        Label(order.title, systemImage: order.systemImage)
                            .tag(order.rawValue)
                    }
                }
            } label: {
                Image(systemName: selectedSortOrder.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("章节排序")
        }
    }

    private var selectedSortOrder: ComicDetailChapterSortOrder {
        ComicDetailChapterSortOrder(rawValue: sortOrder) ?? .ascending
    }
}

struct ComicChapterRow: View {
    let chapter: ComicChapter

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(.subheadline)
                if let subtitle = chapter.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ComicInfoLine: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FlowTagLinks: View {
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    let tags: [ComicTagReference]
    let color: Color
    let onSelect: (ComicTagReference) -> Void
    @State private var blockingFeedback: BlockingKeywordFeedback?
    @State private var selectedBlockingTag: ComicTagReference?

    var body: some View {
        Group {
            if tags.isEmpty {
                Text("无标签")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        FlowTagLinkButton(tag: tag, color: color) {
                            onSelect(tag)
                        } onBlock: {
                            selectedBlockingTag = tag
                        }
                    }
                }
            }
        }
        .confirmationDialog("标签操作", isPresented: blockingDialogBinding, titleVisibility: .visible) {
            if let selectedBlockingTag {
                Button("添加屏蔽词") {
                    blockingFeedback = blockingKeywords.add(tag: selectedBlockingTag)
                    self.selectedBlockingTag = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(selectedBlockingTag?.title ?? "")
        }
        .alert(item: $blockingFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var blockingDialogBinding: Binding<Bool> {
        Binding {
            selectedBlockingTag != nil
        } set: { isPresented in
            if !isPresented {
                selectedBlockingTag = nil
            }
        }
    }
}

private struct FlowTagLinkButton: View {
    let tag: ComicTagReference
    let color: Color
    let onSelect: () -> Void
    let onBlock: () -> Void

    var body: some View {
        Text(tag.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .gesture(
                ExclusiveGesture(LongPressGesture(minimumDuration: 0.45), TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first:
                            onBlock()
                        case .second:
                            onSelect()
                        }
                    }
            )
            .accessibilityLabel(tag.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onSelect()
            }
            .accessibilityAction(named: "添加屏蔽词") {
                onBlock()
            }
    }
}

private struct ComicCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ComicListItem
    let service: ComicContentService
    let account: PlatformAccount?
    @StateObject private var viewModel: ComicCommentsViewModel
    @State private var composeContext: CommentComposeContext?

    init(item: ComicListItem, service: ComicContentService, account: PlatformAccount?) {
        self.item = item
        self.service = service
        self.account = account
        _viewModel = StateObject(wrappedValue: ComicCommentsViewModel(item: item, service: service, account: account))
    }

    var body: some View {
        PicaxNavigationContainer {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView(title: "正在加载评论")
                case .loaded(let comments):
                    if comments.isEmpty {
                        ContentUnavailableView("暂无评论", systemImage: "text.bubble")
                    } else {
                        List {
                            ForEach(comments) { comment in
                                ComicCommentRow(comment: comment)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await viewModel.load(force: true)
                        }
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await viewModel.load(force: true) }
                        }
                    }
                }
            }
            .navigationTitle("评论")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                    if service.supportsCommentPosting(platform: item.platform) {
                        Button {
                            composeContext = CommentComposeContext(item: item)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("写评论")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(item: $composeContext) { _ in
                CommentComposeSheet(viewModel: viewModel)
                    .picaxPresentationDetents([.medium])
                    .interactiveDismissDisabled(viewModel.isPosting)
            }
        }
    }
}

private struct CommentComposeContext: Identifiable {
    let item: ComicListItem
    var id: String { "\(item.platform.id)-\(item.id)-compose" }
}

private struct CommentComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ComicCommentsViewModel

    var body: some View {
        PicaxNavigationContainer {
            List {
                Section {
                    commentEditor
                }
            }
            .picaxInsetGroupedListStyle()
            .navigationTitle("写评论")
            .picaxNavigationBarTitleDisplayModeInline()
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        let posted = await viewModel.post()
                        if posted {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isPosting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("发送")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isPosting || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(viewModel.isPosting)
                    .accessibilityLabel("关闭")
                }
            }
        }
    }

    @ViewBuilder
    private var commentEditor: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextField("写评论", text: $viewModel.draft, axis: .vertical)
                .lineLimit(4...10)
                .disabled(viewModel.isPosting)
        } else {
            TextEditor(text: $viewModel.draft)
                .frame(minHeight: 96, maxHeight: 220)
                .disabled(viewModel.isPosting)
        }
    }
}

struct FavoriteSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ComicListItem
    let service: ComicContentService
    let account: PlatformAccount?
    @State private var localFolders: [LocalFavoriteFolder] = []
    @State private var platformFolders: [PlatformFavoriteFolder] = []
    @State private var selectedTarget: FavoriteSelectionTarget?
    @State private var isLoadingPlatformFolders = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: ComicListItem, service: ComicContentService, account: PlatformAccount?) {
        self.item = item
        self.service = service
        self.account = account
    }

    var body: some View {
        PicaxNavigationContainer {
            favoriteList
            .picaxInsetGroupedListStyle()
            .navigationTitle("选择收藏夹")
            .picaxNavigationBarTitleDisplayModeInline()
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .task {
                await loadFolders()
            }
            .alert("收藏失败", isPresented: favoriteErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var favoriteList: some View {
        List {
            localFoldersSection

            if service.supportsPlatformFavorite(platform: item.platform) {
                platformFoldersSection
            }
        }
    }

    private var localFoldersSection: some View {
        Section {
            ForEach(localFolders) { folder in
                localFolderRow(folder)
            }
        } header: {
            Text("本地收藏夹")
        }
    }

    private var platformFoldersSection: some View {
        Section {
            platformFoldersContent
        } header: {
            Text("平台收藏夹")
        } footer: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var platformFoldersContent: some View {
        if account == nil {
            ContentUnavailableView("未登录", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("登录后可添加到平台收藏"))
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } else if isLoadingPlatformFolders {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在加载收藏夹")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            ForEach(platformFolders) { folder in
                platformFolderRow(folder)
            }
        }
    }

    private func localFolderRow(_ folder: LocalFavoriteFolder) -> some View {
        let target = FavoriteSelectionTarget.local(folder)
        return FavoriteTargetRow(
            title: folder.title,
            subtitle: folder.subtitle,
            systemImage: "folder",
            accentColor: .orange,
            isSelected: selectedTarget?.id == target.id
        ) {
            selectedTarget = target
        }
    }

    private func platformFolderRow(_ folder: PlatformFavoriteFolder) -> some View {
        let target = FavoriteSelectionTarget.platform(folder)
        return FavoriteTargetRow(
            title: folder.title,
            subtitle: folder.subtitle,
            systemImage: item.platform.systemImage,
            accentColor: item.accentColor,
            isSelected: selectedTarget?.id == target.id
        ) {
            selectedTarget = target
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                await save()
            }
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("添加到收藏")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSaving || selectedTarget == nil)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            errorMessage != nil && !isLoadingPlatformFolders
        } set: { isPresented in
            if !isPresented {
                errorMessage = nil
            }
        }
    }

    private func loadFolders() async {
        localFolders = service.localFolders
        if selectedTarget == nil, let first = localFolders.first {
            selectedTarget = .local(first)
        }

        guard service.supportsPlatformFavorite(platform: item.platform), account != nil else {
            return
        }

        isLoadingPlatformFolders = true
        defer { isLoadingPlatformFolders = false }

        do {
            platformFolders = try await service.loadPlatformFavoriteFolders(item: item, account: account)
        } catch {
            errorMessage = error.localizedDescription
            platformFolders = []
        }
    }

    private func save() async {
        guard let selectedTarget, !isSaving else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            switch selectedTarget {
            case .local(let folder):
                service.addLocalFavorite(item: item, folder: folder)
            case .platform(let folder):
                try await service.addPlatformFavorite(item: item, folder: folder, account: account)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FavoriteTargetRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private enum FavoriteSelectionTarget: Identifiable, Hashable {
    case local(LocalFavoriteFolder)
    case platform(PlatformFavoriteFolder)

    var id: String {
        switch self {
        case .local(let folder):
            "local-\(folder.id)"
        case .platform(let folder):
            "platform-\(folder.platform.id)-\(folder.id)"
        }
    }
}

private struct ComicCommentRow: View {
    let comment: ComicComment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                CachedRemoteImageView(
                    url: comment.avatarURL,
                    accentColor: .secondary,
                    contentMode: .fill,
                    maxPixelSize: 128,
                    placeholderSystemImage: "person.crop.circle"
                )
                .frame(width: 42, height: 42)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                    if let timeText = comment.timeText, !timeText.isEmpty {
                        Text(timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Text(comment.content)
                .font(.subheadline)
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
            .foregroundStyle(.secondary)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reply.author)
                                .font(.caption.weight(.semibold))
                            Text(reply.content)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(AppColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ZoomableCoverPreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL?
    let accentColor: Color
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        PicaxNavigationContainer {
            ZStack {
                Color.black.ignoresSafeArea()
                CachedRemoteImageView(url: url, accentColor: accentColor, contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture.simultaneously(with: dragGesture))
                    .onTapGesture(count: 2) {
                        resetZoom()
                    }
                    .padding()
            }
            .picaxSensitiveImageContent(url != nil)
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("关闭")
                }
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 {
                    resetZoom()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

private struct LoadingComicDetailView: View {
    let accentColor: Color

    var body: some View {
        LoadingStateView(title: "正在加载详情")
    }
}

@MainActor
private final class ComicDetailViewModel: ObservableObject {
    @Published private(set) var state: ComicDetailLoadState = .idle

    var loadedDetail: ComicDetailInfo? {
        if case .loaded(let detail) = state {
            return detail
        }
        return nil
    }

    private let item: ComicListItem
    private let service: ComicContentService
    private var refreshTask: Task<Void, Never>?

    init(item: ComicListItem, service: ComicContentService) {
        self.item = item
        self.service = service
    }

    deinit {
        refreshTask?.cancel()
    }

    func load(account: PlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force {
            return
        }

        refreshTask?.cancel()

        if !force, let cachedDetail = await ComicDetailCacheService.detail(for: item, account: account) {
            state = .loaded(cachedDetail)
            refreshTask = Task { [weak self] in
                await self?.loadFromNetwork(account: account, showsLoading: false)
            }
            return
        }

        await loadFromNetwork(account: account, showsLoading: loadedDetail == nil)
    }

    private func loadFromNetwork(account: PlatformAccount?, showsLoading: Bool) async {
        if showsLoading {
            state = .loading
        }

        do {
            let detail = try await service.loadDetail(item: item, account: account)
            try Task.checkCancellation()
            state = .loaded(detail)
            await ComicDetailCacheService.store(detail, account: account)
        } catch where error.isTaskCancellation {
            return
        } catch {
            if showsLoading {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func updateLikeState(_ isLiked: Bool, account: PlatformAccount?) async {
        guard var detail = loadedDetail else { return }
        detail.isLiked = isLiked
        state = .loaded(detail)
        await ComicDetailCacheService.store(detail, account: account)
    }
}

@MainActor
private final class ComicCommentsViewModel: ObservableObject {
    @Published private(set) var state: ComicCommentsLoadState = .idle
    @Published var draft = ""
    @Published private(set) var isPosting = false

    private let item: ComicListItem
    private let service: ComicContentService
    private let account: PlatformAccount?

    init(item: ComicListItem, service: ComicContentService, account: PlatformAccount?) {
        self.item = item
        self.service = service
        self.account = account
    }

    func load(force: Bool = false) async {
        if case .loaded = state, !force {
            return
        }

        if !force {
            state = .loading
        }
        do {
            let comments = try await service.loadComments(item: item, account: account)
            state = .loaded(comments)
        } catch where error.isTaskCancellation {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func post() async -> Bool {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isPosting else {
            return false
        }

        isPosting = true
        defer { isPosting = false }

        do {
            try await service.postComment(item: item, content: content, account: account)
            draft = ""
            await load(force: true)
            return true
        } catch where error.isTaskCancellation {
            return false
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }
}

private enum ComicDetailLoadState {
    case idle
    case loading
    case loaded(ComicDetailInfo)
    case failed(String)
}

private enum ComicCommentsLoadState {
    case idle
    case loading
    case loaded([ComicComment])
    case failed(String)
}

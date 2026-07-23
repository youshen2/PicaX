import Combine
import SwiftUI

struct ComicListSection: View {
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @EnvironmentObject private var blockingKeywords: BlockingKeywordService
    @EnvironmentObject private var readLater: ReadLaterService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ComicListSettingsKey.layoutMode) private var layoutMode = ComicListLayoutMode.list.rawValue
    @AppStorage(ReadFilterSettingsKey.hidesReadComicsInLists) private var hidesReadComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hidesReadLaterComicsInLists) private var hidesReadLaterComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hiddenProgressThreshold) private var hiddenProgressThreshold = 100
    @AppStorage(ComicListSettingsKey.showsReadingProgress) private var showsListReadingProgress = true
    @AppStorage(ComicListSettingsKey.showsFavoriteState) private var showsListFavoriteState = true
    @AppStorage(ComicListSettingsKey.showsTags) private var showsListTags = true
    @AppStorage(ComicListSettingsKey.maxVisibleTags) private var maxVisibleTags = 5
    @AppStorage(ComicListSettingsKey.showsPopularity) private var showsListPopularity = true

    let comics: [ComicListItem]
    let service: ComicContentService
    var isLoadingMore = false
    var hasMore = false
    var appliesBlocking = true
    var appliesReadProgressFilter = true
    var appliesReadLaterFilter = true
    var showsReadAll = false
    var readAllTitle = "阅读列表"
    var readAllComics: [ComicListItem]?
    var isPreparingReadAll = false
    var readAllAction: (() -> Void)?
    var loadMore: (() -> Void)?
    @State private var detailRequest: ComicListDetailRequest?
    @State private var readerRequest: ComicListReaderRequest?
    @State private var readingListRequest: ReadingListRequest?
    @State private var renderedComicCount = Self.initialRenderedComicCount
    @State private var renderSnapshot = ComicListRenderSnapshot.empty
    @State private var tagDisplayVersion = 0
    @State private var lastWaterfallPaginationTrigger: ComicWaterfallPaginationTrigger?
    @Namespace private var waterfallScrollCoordinateSpace
    @Namespace private var navigationTransitionNamespace

    private static let initialRenderedComicCount = 48
    private static let renderedComicPageSize = 48
    private static let waterfallSpacing: CGFloat = 12
    private static let waterfallHorizontalPadding: CGFloat = 16
    private static let waterfallBottomLoadThreshold: CGFloat = 80

    var body: some View {
        Group {
            comicList
        }
        .picaxComicDetailDestination(
            item: $detailRequest,
            in: navigationTransitionNamespace,
            service: service
        )
        .picaxNavigationDestination(item: $readerRequest) { request in
            ComicReaderPage(
                detail: request.detail,
                initialChapterIndex: 0,
                ignoresHistoryProgress: request.ignoresHistoryProgress,
                service: service
            )
        }
        .picaxNavigationDestination(item: $readingListRequest) { request in
            ReadingListReaderPage(request: request, service: service)
        }
    }

    private var comicList: some View {
        let request = makeSnapshotRequest()
        let snapshot = renderSnapshot
        let snapshotIsCurrent = snapshot.key == request.key
        let keepsStaleSnapshot = !snapshotIsCurrent && snapshot.canDisplayWhileRebuilding(for: request)
        let usesSnapshot = snapshotIsCurrent || keepsStaleSnapshot
        let visibleComics = usesSnapshot ? snapshot.visibleComics : []
        let readingRecordsByID = usesSnapshot ? snapshot.readingRecordsByID : [:]
        let displayTagsByID = usesSnapshot ? snapshot.displayTagsByID : [:]
        let totalVisibleCount = visibleComics.count
        let displayCount = renderedCount(for: totalVisibleCount)
        let displayedRows = makeDisplayedRows(
            from: visibleComics,
            count: displayCount,
            readingRecordsByID: readingRecordsByID,
            displayTagsByID: displayTagsByID
        )
        let readingListComics = readAllComics ?? (usesSnapshot ? visibleComics : [])
        let lastDisplayedComicID = displayedRows.last?.id
        let isPreparingSnapshot = !snapshotIsCurrent && !comics.isEmpty
        let activeLayoutMode = ComicListLayoutMode(rawValue: layoutMode) ?? .list

        return Group {
            if activeLayoutMode == .waterfall {
                waterfallList(
                    displayedRows: displayedRows,
                    readingListComics: readingListComics,
                    totalVisibleCount: totalVisibleCount,
                    isPreparingSnapshot: isPreparingSnapshot,
                    snapshotIsCurrent: snapshotIsCurrent
                )
            } else {
                standardList(
                    displayedRows: displayedRows,
                    readingListComics: readingListComics,
                    lastDisplayedComicID: lastDisplayedComicID,
                    totalVisibleCount: totalVisibleCount,
                    isPreparingSnapshot: isPreparingSnapshot,
                    snapshotIsCurrent: snapshotIsCurrent
                )
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .picaxSensitiveImageContent(!displayedRows.isEmpty)
        .task(id: request.key) {
            await rebuildRenderSnapshot(for: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .picaxNhentaiTagNamesDidChange)) { _ in
            tagDisplayVersion &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .picaxEhTagTranslationsDidChange)) { _ in
            tagDisplayVersion &+= 1
        }
    }

    private func standardList(
        displayedRows: [ComicListDisplayedRow],
        readingListComics: [ComicListItem],
        lastDisplayedComicID: String?,
        totalVisibleCount: Int,
        isPreparingSnapshot: Bool,
        snapshotIsCurrent: Bool
    ) -> some View {
        List {
            Section {
                if showsReadAll, !readingListComics.isEmpty {
                    readAllButton(comics: readingListComics)
                }

                if isPreparingSnapshot, displayedRows.isEmpty {
                    PreparingComicListSnapshotRow()
                }

                if snapshotIsCurrent, totalVisibleCount == 0, !comics.isEmpty {
                    hiddenResultsView
                        .listRowBackground(Color.clear)
                }

                ForEach(displayedRows) { row in
                    comicActionLink(
                        for: row,
                        layoutMode: .list,
                        lastDisplayedComicID: lastDisplayedComicID,
                        totalVisibleCount: totalVisibleCount
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
                }

                paginationFooter(
                    displayedRows: displayedRows,
                    totalVisibleCount: totalVisibleCount,
                    isPreparingSnapshot: isPreparingSnapshot,
                    snapshotIsCurrent: snapshotIsCurrent
                )
            }
        }
        .picaxInsetGroupedListStyle()
    }

    private func waterfallList(
        displayedRows: [ComicListDisplayedRow],
        readingListComics: [ComicListItem],
        totalVisibleCount: Int,
        isPreparingSnapshot: Bool,
        snapshotIsCurrent: Bool
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.waterfallSpacing) {
                    if showsReadAll, !readingListComics.isEmpty {
                        readAllButton(comics: readingListComics)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                AppColor.secondaryGroupedBackground,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }

                    if isPreparingSnapshot, displayedRows.isEmpty {
                        PreparingComicListSnapshotRow()
                    }

                    if snapshotIsCurrent, totalVisibleCount == 0, !comics.isEmpty {
                        hiddenResultsView
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    waterfallGrid(
                        displayedRows: displayedRows,
                        availableWidth: max(
                            geometry.size.width - Self.waterfallHorizontalPadding * 2,
                            0
                        ),
                        totalVisibleCount: totalVisibleCount
                    )

                    waterfallPaginationFooter(
                        displayedRows: displayedRows,
                        isPreparingSnapshot: isPreparingSnapshot,
                        snapshotIsCurrent: snapshotIsCurrent
                    )
                }
                .padding(.horizontal, Self.waterfallHorizontalPadding)
                .padding(.vertical, Self.waterfallSpacing)
            }
            .coordinateSpace(name: waterfallScrollCoordinateSpace)
            .background(AppColor.groupedBackground)
            .onPreferenceChange(ComicWaterfallBottomPreferenceKey.self) { bottomPosition in
                handleWaterfallBottomPosition(
                    bottomPosition,
                    viewportHeight: geometry.size.height,
                    displayedRows: displayedRows,
                    totalVisibleCount: totalVisibleCount,
                    isPreparingSnapshot: isPreparingSnapshot,
                    snapshotIsCurrent: snapshotIsCurrent
                )
            }
            .onDisappear {
                lastWaterfallPaginationTrigger = nil
            }
        }
    }

    @ViewBuilder
    private func waterfallGrid(
        displayedRows: [ComicListDisplayedRow],
        availableWidth: CGFloat,
        totalVisibleCount: Int
    ) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                waterfallGridContent(
                    displayedRows: displayedRows,
                    availableWidth: availableWidth,
                    totalVisibleCount: totalVisibleCount
                )
            }
        } else {
            waterfallGridContent(
                displayedRows: displayedRows,
                availableWidth: availableWidth,
                totalVisibleCount: totalVisibleCount
            )
        }
    }

    private func waterfallGridContent(
        displayedRows: [ComicListDisplayedRow],
        availableWidth: CGFloat,
        totalVisibleCount: Int
    ) -> some View {
        let columnCount = waterfallColumnCount(availableWidth: availableWidth)
        let columnWidth = waterfallColumnWidth(
            availableWidth: availableWidth,
            columnCount: columnCount
        )
        let columns = makeWaterfallColumns(
            rows: displayedRows,
            columnCount: columnCount,
            columnWidth: columnWidth
        )

        return HStack(alignment: .top, spacing: Self.waterfallSpacing) {
            ForEach(columns) { column in
                LazyVStack(spacing: Self.waterfallSpacing) {
                    ForEach(column.entries) { entry in
                        comicActionLink(
                            for: entry.row,
                            layoutMode: .waterfall,
                            lastDisplayedComicID: nil,
                            totalVisibleCount: totalVisibleCount
                        )
                        .accessibilitySortPriority(Double(displayedRows.count - entry.sourceIndex))
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waterfallColumnCount(availableWidth: CGFloat) -> Int {
        let minimumWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 280 : 160
        let fittingCount = Int(
            (availableWidth + Self.waterfallSpacing)
                / (minimumWidth + Self.waterfallSpacing)
        )
        return max(fittingCount, 1)
    }

    private func waterfallColumnWidth(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        let spacingWidth = CGFloat(max(columnCount - 1, 0)) * Self.waterfallSpacing
        return max((availableWidth - spacingWidth) / CGFloat(max(columnCount, 1)), 0)
    }

    private func makeWaterfallColumns(
        rows: [ComicListDisplayedRow],
        columnCount: Int,
        columnWidth: CGFloat
    ) -> [ComicWaterfallColumn] {
        var columns = (0..<columnCount).map {
            ComicWaterfallColumn(id: $0, entries: [])
        }
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for (sourceIndex, row) in rows.enumerated() {
            let targetColumn = columnHeights.indices.min {
                columnHeights[$0] < columnHeights[$1]
            } ?? 0
            let hasExistingCard = !columns[targetColumn].entries.isEmpty
            columns[targetColumn].entries.append(
                ComicWaterfallEntry(row: row, sourceIndex: sourceIndex)
            )
            if hasExistingCard {
                columnHeights[targetColumn] += Self.waterfallSpacing
            }
            columnHeights[targetColumn] += estimatedWaterfallCardHeight(
                for: row,
                columnWidth: columnWidth
            )
        }

        return columns
    }

    private func estimatedWaterfallCardHeight(
        for row: ComicListDisplayedRow,
        columnWidth: CGFloat
    ) -> CGFloat {
        let coverHeight = columnWidth * 112 / 82
        let contentWidth = max(columnWidth - 24, 1)
        var contentHeight: CGFloat = 25
        var sectionCount = 1

        contentHeight += estimatedTextLineCount(
            row.item.title,
            availableWidth: contentWidth,
            averageCharacterWidth: 9,
            maximumLines: 2
        ) * 19

        if !row.item.subtitle.isEmpty {
            sectionCount += 1
            contentHeight += estimatedTextLineCount(
                row.item.subtitle,
                availableWidth: contentWidth,
                averageCharacterWidth: 8,
                maximumLines: 2
            ) * 16
        }

        if hasWaterfallMetadata(for: row) {
            sectionCount += 1
            contentHeight += 17
        }

        let visibleTags = row.displayTags ?? row.item.tags
        if showsListTags, !visibleTags.isEmpty {
            sectionCount += 1
            contentHeight += 24
        }

        contentHeight += CGFloat(sectionCount - 1) * 8
        return coverHeight + contentHeight
    }

    private func estimatedTextLineCount(
        _ text: String,
        availableWidth: CGFloat,
        averageCharacterWidth: CGFloat,
        maximumLines: Int
    ) -> CGFloat {
        let charactersPerLine = max(Int(availableWidth / averageCharacterWidth), 1)
        let estimatedLines = max(
            (text.count + charactersPerLine - 1) / charactersPerLine,
            1
        )
        return CGFloat(min(estimatedLines, maximumLines))
    }

    private func hasWaterfallMetadata(for row: ComicListDisplayedRow) -> Bool {
        row.item.pageText != nil
            || row.readingProgressText != nil
            || (showsListPopularity && row.item.likesCount != nil)
            || (showsListFavoriteState && row.item.favoriteDate != nil)
    }

    private var hiddenResultsView: some View {
        ContentUnavailableView(
            "已隐藏全部结果",
            systemImage: "eye.slash",
            description: Text("当前列表内容命中了屏蔽词、阅读进度或稍后再读过滤，可在设置中调整。")
        )
    }

    private func readAllButton(comics: [ComicListItem]) -> some View {
        Button {
            if let readAllAction {
                readAllAction()
            } else {
                readingListRequest = ReadingListRequest(
                    title: readAllTitle,
                    entries: comics.map(ReadingListEntry.online)
                )
            }
        } label: {
            if isPreparingReadAll {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在准备阅读列表")
                }
            } else {
                Label("阅读全部", systemImage: "play.circle")
            }
        }
        .disabled(isPreparingReadAll)
    }

    private func comicActionLink(
        for row: ComicListDisplayedRow,
        layoutMode: ComicListLayoutMode,
        lastDisplayedComicID: String?,
        totalVisibleCount: Int
    ) -> some View {
        ComicListActionLink(
            item: row.item,
            service: service,
            layoutMode: layoutMode,
            hasReadingProgress: row.hasReadingProgress,
            readingProgressText: row.readingProgressText,
            displayTags: row.displayTags,
            showsFavoriteState: showsListFavoriteState,
            showsTags: showsListTags,
            maxVisibleTags: maxVisibleTags,
            showsPopularity: showsListPopularity,
            comicDetailTransitionNamespace: navigationTransitionNamespace,
            openDetail: { detailRequest = ComicListDetailRequest(item: $0) },
            openReader: { readerRequest = $0 }
        ) {
            if row.id == lastDisplayedComicID {
                revealOrLoadMore(totalVisibleCount: totalVisibleCount)
            }
        }
    }

    @ViewBuilder
    private func waterfallPaginationFooter(
        displayedRows: [ComicListDisplayedRow],
        isPreparingSnapshot: Bool,
        snapshotIsCurrent: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if isPreparingSnapshot, !displayedRows.isEmpty {
                if isLoadingMore {
                    LoadingMoreRow()
                } else {
                    PreparingComicListSnapshotRow()
                }
            } else if snapshotIsCurrent, isLoadingMore {
                LoadingMoreRow()
            }

            Color.clear
                .frame(height: 1)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ComicWaterfallBottomPreferenceKey.self,
                            value: geometry.frame(in: .named(waterfallScrollCoordinateSpace)).minY
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private func paginationFooter(
        displayedRows: [ComicListDisplayedRow],
        totalVisibleCount: Int,
        isPreparingSnapshot: Bool,
        snapshotIsCurrent: Bool
    ) -> some View {
        if isPreparingSnapshot, !displayedRows.isEmpty {
            if isLoadingMore {
                LoadingMoreRow()
            } else {
                PreparingComicListSnapshotRow()
            }
        } else if !snapshotIsCurrent {
            EmptyView()
        } else if isLoadingMore {
            LoadingMoreRow()
        } else if canRevealMoreLocalComics(totalVisibleCount: totalVisibleCount) {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    revealMoreLocalComics(totalVisibleCount: totalVisibleCount)
                }
        } else if hasMore {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    loadMore?()
                }
        }
    }

    private func handleWaterfallBottomPosition(
        _ bottomPosition: CGFloat,
        viewportHeight: CGFloat,
        displayedRows: [ComicListDisplayedRow],
        totalVisibleCount: Int,
        isPreparingSnapshot: Bool,
        snapshotIsCurrent: Bool
    ) {
        let isNearBottom = bottomPosition.isFinite
            && bottomPosition <= viewportHeight + Self.waterfallBottomLoadThreshold

        guard isNearBottom else {
            if snapshotIsCurrent,
               !isPreparingSnapshot,
               !isLoadingMore,
               lastWaterfallPaginationTrigger != nil {
                lastWaterfallPaginationTrigger = nil
            }
            return
        }

        guard snapshotIsCurrent,
              !isPreparingSnapshot,
              !isLoadingMore,
              !displayedRows.isEmpty else {
            return
        }

        let action: ComicWaterfallPaginationTrigger.Action
        if canRevealMoreLocalComics(totalVisibleCount: totalVisibleCount) {
            action = .revealLocal
        } else if hasMore {
            action = .loadRemote
        } else {
            return
        }

        let trigger = ComicWaterfallPaginationTrigger(
            action: action,
            firstComicID: displayedRows.first?.id,
            lastComicID: displayedRows.last?.id,
            displayedCount: displayedRows.count,
            totalVisibleCount: totalVisibleCount
        )
        guard trigger != lastWaterfallPaginationTrigger else { return }
        lastWaterfallPaginationTrigger = trigger

        switch action {
        case .revealLocal:
            revealMoreLocalComics(totalVisibleCount: totalVisibleCount)
        case .loadRemote:
            loadMore?()
        }
    }

    private func makeSnapshotRequest() -> ComicListSnapshotRequest {
        let readingRecordsByID = readingHistory.activeReadingRecordsByID
        let readLaterIDs = readLater.allRecordIDs
        let blockingMatcher = blockingKeywords.commonKeywordMatcher
        return ComicListSnapshotRequest(
            key: ComicListSnapshotKey(
                comics: comics,
                readingRecordsRevision: readingHistory.snapshotRevision,
                readLaterRevision: readLater.snapshotRevision,
                blockingMatcher: blockingMatcher,
                appliesBlocking: appliesBlocking,
                appliesReadProgressFilter: appliesReadProgressFilter,
                appliesReadLaterFilter: appliesReadLaterFilter,
                hidesReadComicsInLists: hidesReadComicsInLists,
                hidesReadLaterComicsInLists: hidesReadLaterComicsInLists,
                hiddenProgressThreshold: hiddenProgressThreshold,
                tagDisplayVersion: tagDisplayVersion
            ),
            comics: comics,
            readingRecordsByID: readingRecordsByID,
            readLaterIDs: readLaterIDs,
            blockingMatcher: blockingMatcher,
            appliesBlocking: appliesBlocking,
            appliesReadProgressFilter: appliesReadProgressFilter,
            appliesReadLaterFilter: appliesReadLaterFilter,
            hidesReadComicsInLists: hidesReadComicsInLists,
            hidesReadLaterComicsInLists: hidesReadLaterComicsInLists,
            hiddenProgressThreshold: hiddenProgressThreshold
        )
    }

    @MainActor
    private func rebuildRenderSnapshot(for request: ComicListSnapshotRequest) async {
        let buildTask = Task.detached(priority: .userInitiated) {
            try ComicListRenderSnapshot.make(for: request)
        }

        do {
            let snapshot = try await withTaskCancellationHandler {
                try await buildTask.value
            } onCancel: {
                buildTask.cancel()
            }
            guard !Task.isCancelled else { return }
            updateRenderedComicCount(oldSnapshot: renderSnapshot, newSnapshot: snapshot)
            renderSnapshot = snapshot
            service.warmNhentaiTagNameCache(for: snapshot.visibleComics)
        } catch where error.isTaskCancellation {
            return
        } catch {
            return
        }
    }

    private func makeDisplayedRows(
        from visibleComics: [ComicListItem],
        count: Int,
        readingRecordsByID: [String: ReadingHistoryRecord],
        displayTagsByID: [String: [String]]
    ) -> [ComicListDisplayedRow] {
        let displayCount = min(max(count, 0), visibleComics.count)
        var rows: [ComicListDisplayedRow] = []
        rows.reserveCapacity(displayCount)

        for comic in visibleComics.prefix(displayCount) {
            let readingRecord = readingRecordsByID[comic.readingHistoryID]
            rows.append(
                ComicListDisplayedRow(
                    item: comic,
                    hasReadingProgress: readingRecord != nil,
                    readingProgressText: showsListReadingProgress ? readingRecord?.progressText : nil,
                    displayTags: displayTagsByID[comic.readingHistoryID]
                )
            )
        }
        return rows
    }

    private func renderedCount(for totalVisibleCount: Int) -> Int {
        min(max(renderedComicCount, 0), totalVisibleCount)
    }

    private func canRevealMoreLocalComics(totalVisibleCount: Int) -> Bool {
        renderedCount(for: totalVisibleCount) < totalVisibleCount
    }

    private func revealOrLoadMore(totalVisibleCount: Int) {
        if canRevealMoreLocalComics(totalVisibleCount: totalVisibleCount) {
            revealMoreLocalComics(totalVisibleCount: totalVisibleCount)
        } else if hasMore {
            loadMore?()
        }
    }

    private func revealMoreLocalComics(totalVisibleCount: Int) {
        guard renderedComicCount < totalVisibleCount else { return }
        renderedComicCount = min(totalVisibleCount, renderedComicCount + Self.renderedComicPageSize)
    }

    private func updateRenderedComicCount(oldSnapshot: ComicListRenderSnapshot, newSnapshot: ComicListRenderSnapshot) {
        let oldIdentity = oldSnapshot.contentIdentity
        let newIdentity = newSnapshot.contentIdentity
        let minimumRenderedCount = min(Self.initialRenderedComicCount, max(newIdentity.totalCount, 1))
        if oldSnapshot.key.canPreserveRenderedCount(afterRebuildingFor: newSnapshot.key) {
            renderedComicCount = min(max(renderedComicCount, minimumRenderedCount), newIdentity.totalCount)
            return
        }

        let leadingContentChanged = oldIdentity.leadingCount != newIdentity.leadingCount
            || oldIdentity.leadingHash != newIdentity.leadingHash
        let contentShrank = newIdentity.totalCount < oldIdentity.totalCount

        if leadingContentChanged || contentShrank {
            renderedComicCount = minimumRenderedCount
        } else if renderedComicCount > newIdentity.totalCount {
            renderedComicCount = max(minimumRenderedCount, newIdentity.totalCount)
        } else if renderedComicCount < minimumRenderedCount {
            renderedComicCount = minimumRenderedCount
        }
    }

}

private struct LoadingMoreRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在加载更多")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
    }
}

private struct PreparingComicListSnapshotRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在整理列表")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
    }
}

enum ComicListItemIdentity: Sendable {
    case id
    case readingHistoryID
    case platformAndID
}

struct ComicListUniqueResult: Sendable {
    let items: [ComicListItem]
    let loadedIDs: Set<String>
}

enum ComicListBackgroundProcessing {
    nonisolated static func localFavorites(folderID: String) async throws -> [ComicListItem] {
        try await run {
            try Task.checkCancellation()
            return LocalFavoritesStore().items(folderID: folderID)
        }
    }

    nonisolated static func filteredFavorites(from comics: [ComicListItem], keyword rawKeyword: String) async throws -> [ComicListItem] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return comics }

        return try await run {
            var result: [ComicListItem] = []
            result.reserveCapacity(comics.count)
            for (index, comic) in comics.enumerated() {
                if index.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                if comicMatches(comic, keyword: keyword) {
                    result.append(comic)
                }
            }
            return result
        }
    }

    nonisolated static func loadedIDs(from items: [ComicListItem], identity: ComicListItemIdentity) async throws -> Set<String> {
        try await run {
            var ids = Set<String>()
            ids.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 128) {
                    try Task.checkCancellation()
                }
                ids.insert(key(for: item, identity: identity))
            }
            return ids
        }
    }

    nonisolated static func uniqueItems(
        from items: [ComicListItem],
        loadedIDs: Set<String>,
        identity: ComicListItemIdentity
    ) async throws -> ComicListUniqueResult {
        try await run {
            var nextIDs = loadedIDs
            var uniqueItems: [ComicListItem] = []
            uniqueItems.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                guard nextIDs.insert(key(for: item, identity: identity)).inserted else { continue }
                uniqueItems.append(item)
            }
            return ComicListUniqueResult(items: uniqueItems, loadedIDs: nextIDs)
        }
    }

    nonisolated static func interleavedUniqueItems(
        from groups: [[ComicListItem]],
        loadedIDs: Set<String>,
        identity: ComicListItemIdentity
    ) async throws -> ComicListUniqueResult {
        try await run {
            let maxCount = groups.map(\.count).max() ?? 0
            guard maxCount > 0 else {
                return ComicListUniqueResult(items: [], loadedIDs: loadedIDs)
            }

            var nextIDs = loadedIDs
            var uniqueItems: [ComicListItem] = []
            uniqueItems.reserveCapacity(groups.reduce(0) { $0 + $1.count })

            for index in 0..<maxCount {
                if index.isMultiple(of: 16) {
                    try Task.checkCancellation()
                }
                for group in groups where group.indices.contains(index) {
                    let item = group[index]
                    guard nextIDs.insert(key(for: item, identity: identity)).inserted else { continue }
                    uniqueItems.append(item)
                }
            }

            return ComicListUniqueResult(items: uniqueItems, loadedIDs: nextIDs)
        }
    }

    private nonisolated static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) {
            try operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func key(for item: ComicListItem, identity: ComicListItemIdentity) -> String {
        switch identity {
        case .id:
            item.id
        case .readingHistoryID:
            item.readingHistoryID
        case .platformAndID:
            "\(item.platform.id)-\(item.id)"
        }
    }

    private nonisolated static func comicMatches(_ comic: ComicListItem, keyword: String) -> Bool {
        comic.title.localizedCaseInsensitiveContains(keyword)
            || comic.subtitle.localizedCaseInsensitiveContains(keyword)
            || comic.id.localizedCaseInsensitiveContains(keyword)
            || comic.platformTitle.localizedCaseInsensitiveContains(keyword)
            || (comic.pageText?.localizedCaseInsensitiveContains(keyword) ?? false)
            || comic.metadataText.localizedCaseInsensitiveContains(keyword)
            || comic.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
    }
}

struct ComicListActionLink: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var readLater: ReadLaterService

    let item: ComicListItem
    let service: ComicContentService
    var layoutMode = ComicListLayoutMode.list
    var hasReadingProgress = false
    var readingProgressText: String?
    var displayTags: [String]?
    var showsFavoriteState = true
    var showsTags = true
    var maxVisibleTags = 5
    var showsPopularity = true
    let comicDetailTransitionNamespace: Namespace.ID
    let openDetail: (ComicListItem) -> Void
    let openReader: (ComicListReaderRequest) -> Void
    var onAppear: (() -> Void)?

    @State private var favoriteContext: ComicListFavoriteContext?
    @State private var isPreparingReader = false
    @State private var errorMessage: String?

    var body: some View {
        contextMenuSource
            .onAppear {
                onAppear?()
            }
            .sheet(item: $favoriteContext) { context in
                FavoriteSelectionSheet(
                    item: context.item,
                    service: service,
                    account: platformAccounts.account(for: context.item.platform)
                )
                .picaxPresentationDetents([.medium, .large])
            }
            .alert("打开失败", isPresented: readerErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .disabled(isPreparingReader)
    }

    @ViewBuilder
    private var contextMenuSource: some View {
        if layoutMode == .waterfall {
            if #available(iOS 16, macOS 13, visionOS 1, *) {
                actionButton
                    .contextMenu {
                        contextMenuItems
                    } preview: {
                        waterfallContextMenuPreview
                    }
            } else {
                actionButton
                    .contextMenu {
                        contextMenuItems
                    }
            }
        } else {
            actionButton
                .contextMenu {
                    contextMenuItems
                }
        }
    }

    private var actionButton: some View {
        Button {
            openDetail(item)
        } label: {
            actionLabel
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
#if os(iOS) || os(visionOS)
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(
                cornerRadius: layoutMode == .waterfall ? 18 : 8,
                style: .continuous
            )
        )
#endif
    }

    @ViewBuilder
    private var actionLabel: some View {
        if layoutMode == .waterfall {
            ComicListWaterfallCard(
                item: item,
                readingProgressText: readingProgressText,
                displayTags: displayTags,
                showsFavoriteState: showsFavoriteState,
                showsTags: showsTags,
                maxVisibleTags: maxVisibleTags,
                showsPopularity: showsPopularity,
                coverTransitionSource: ComicDetailTransitionSource(
                    item: item,
                    namespace: comicDetailTransitionNamespace
                )
            )
            .equatable()
        } else {
            ComicListRow(
                item: item,
                readingProgressText: readingProgressText,
                displayTags: displayTags,
                showsFavoriteState: showsFavoriteState,
                showsTags: showsTags,
                maxVisibleTags: maxVisibleTags,
                showsPopularity: showsPopularity
            )
            .equatable()
            .picaxComicDetailTransitionSource(
                id: ComicDetailTransitionID(item),
                in: comicDetailTransitionNamespace
            )
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            openDetail(item)
        } label: {
            Label("查看详情", systemImage: "info.circle")
        }

        Button {
            prepareReader(ignoresHistoryProgress: !hasReadingProgress)
        } label: {
            Label(readActionTitle, systemImage: "book")
        }

        if hasReadingProgress {
            Button {
                prepareReader(ignoresHistoryProgress: true)
            } label: {
                Label("从头阅读", systemImage: "arrow.counterclockwise")
            }
        }

        Button {
            favoriteContext = ComicListFavoriteContext(item: item)
        } label: {
            Label("收藏", systemImage: "heart")
        }

        Button {
            readLater.toggle(item)
        } label: {
            Label(readLaterActionTitle, systemImage: readLaterActionImage)
        }
    }

    private var waterfallContextMenuPreview: some View {
        ComicListWaterfallCard(
            item: item,
            readingProgressText: readingProgressText,
            displayTags: displayTags,
            showsFavoriteState: showsFavoriteState,
            showsTags: showsTags,
            maxVisibleTags: maxVisibleTags,
            showsPopularity: showsPopularity,
            usesOpaqueSurface: true
        )
        .equatable()
        .frame(width: 280)
    }

    private var readActionTitle: String {
        hasReadingProgress ? "继续阅读" : "从头阅读"
    }

    private var readLaterActionTitle: String {
        readLater.contains(item) ? "移出稍后再读" : "稍后再读"
    }

    private var readLaterActionImage: String {
        readLater.contains(item) ? "bookmark.slash" : "bookmark"
    }

    private var readerErrorBinding: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                errorMessage = nil
            }
        }
    }

    @MainActor
    private func prepareReader(ignoresHistoryProgress: Bool) {
        guard !isPreparingReader else { return }
        isPreparingReader = true
        errorMessage = nil
        let account = platformAccounts.account(for: item.platform)
        Task { @MainActor in
            defer { isPreparingReader = false }
            do {
                let detail = try await service.loadDetail(item: item, account: account)
                openReader(ComicListReaderRequest(detail: detail, ignoresHistoryProgress: ignoresHistoryProgress))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ComicListFavoriteContext: Identifiable {
    let item: ComicListItem
    var id: String { "\(item.platform.id)-\(item.id)" }
}

struct ComicListDetailRequest: Identifiable, Hashable {
    let id = UUID()
    let item: ComicListItem

    static func == (lhs: ComicListDetailRequest, rhs: ComicListDetailRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ComicListReaderRequest: Identifiable, Hashable {
    let id = UUID()
    let detail: ComicDetailInfo
    let ignoresHistoryProgress: Bool

    static func == (lhs: ComicListReaderRequest, rhs: ComicListReaderRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ComicListRow: View, Equatable {
    let item: ComicListItem
    var readingProgressText: String?
    var displayTags: [String]?
    var showsFavoriteState = true
    var showsTags = true
    var maxVisibleTags = 5
    var showsPopularity = true

    static func == (lhs: ComicListRow, rhs: ComicListRow) -> Bool {
        lhs.item == rhs.item
            && lhs.readingProgressText == rhs.readingProgressText
            && lhs.displayTags == rhs.displayTags
            && lhs.showsFavoriteState == rhs.showsFavoriteState
            && lhs.showsTags == rhs.showsTags
            && lhs.maxVisibleTags == rhs.maxVisibleTags
            && lhs.showsPopularity == rhs.showsPopularity
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ComicCoverView(url: item.coverURL, accentColor: item.accentColor, width: 82, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(item.platformTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.accentColor, in: Capsule())
                }

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ComicListHorizontalContentRow {
                    HStack(spacing: 8) {
                        if let pageText = item.pageText {
                            ComicListMetaPill(text: pageText)
                        }
                        if let readingProgressText {
                            ComicListMetaPill(text: readingProgressText, systemImage: "book")
                        }
                        if showsPopularity, item.likesCount != nil {
                            ComicListMetaPill(text: item.metadataText)
                        }
                        if showsFavoriteState, item.favoriteDate != nil {
                            ComicListMetaPill(text: item.favoriteDateText, systemImage: "star.fill")
                        }
                    }
                }

                if showsTags, !visibleTags.isEmpty {
                    ComicListTagRow(tags: visibleTags, limit: visibleTagLimit, accentColor: item.accentColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(AppColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var visibleTagLimit: Int {
        min(max(maxVisibleTags, 1), 10)
    }

    private var visibleTags: [String] {
        displayTags ?? item.tags
    }
}

private struct ComicListWaterfallCard: View, Equatable {
    private static let cornerRadius: CGFloat = 18

    let item: ComicListItem
    var readingProgressText: String?
    var displayTags: [String]?
    var showsFavoriteState = true
    var showsTags = true
    var maxVisibleTags = 5
    var showsPopularity = true
    var usesOpaqueSurface = false
    var coverTransitionSource: ComicDetailTransitionSource? = nil
    @State private var coverTint: Color?

    static func == (lhs: ComicListWaterfallCard, rhs: ComicListWaterfallCard) -> Bool {
        lhs.item == rhs.item
            && lhs.readingProgressText == rhs.readingProgressText
            && lhs.displayTags == rhs.displayTags
            && lhs.showsFavoriteState == rhs.showsFavoriteState
            && lhs.showsTags == rhs.showsTags
            && lhs.maxVisibleTags == rhs.maxVisibleTags
            && lhs.showsPopularity == rhs.showsPopularity
            && lhs.usesOpaqueSurface == rhs.usesOpaqueSurface
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(82.0 / 112.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    transitionCover
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.52)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 72)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(item.platformTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.42), in: Capsule(style: .continuous))
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hasMetadata {
                    ComicListHorizontalContentRow {
                        HStack(spacing: 10) {
                            if let pageText = item.pageText {
                                metadataLabel(pageText, systemImage: "doc.text")
                            }
                            if let readingProgressText {
                                metadataLabel(readingProgressText, systemImage: "book")
                            }
                            if showsPopularity, item.likesCount != nil {
                                metadataLabel(item.metadataText, systemImage: "heart")
                            }
                            if showsFavoriteState, item.favoriteDate != nil {
                                metadataLabel(item.favoriteDateText, systemImage: "star.fill")
                            }
                        }
                    }
                }

                if showsTags, !visibleTags.isEmpty {
                    ComicListTagRow(tags: visibleTags, limit: visibleTagLimit, accentColor: item.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 13)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background {
            if usesOpaqueSurface {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(AppColor.secondaryGroupedBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                            .fill(resolvedTint.opacity(0.1))
                    }
            }
        }
        .glassCardIfAvailable(
            tint: resolvedTint,
            cornerRadius: Self.cornerRadius,
            isEnabled: !usesOpaqueSurface
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .task(id: item.coverURLString) {
            coverTint = nil
            let sampledColor = await CoverColorSampler.averageColor(url: item.coverURL)
            guard !Task.isCancelled else { return }
            coverTint = sampledColor
        }
    }

    @ViewBuilder
    private var transitionCover: some View {
        let cover = ComicCoverView(
            url: item.coverURL,
            accentColor: item.accentColor,
            cornerRadius: 0,
            showsBorder: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let coverTransitionSource {
            cover.picaxComicDetailTransitionSource(
                id: coverTransitionSource.id,
                in: coverTransitionSource.namespace
            )
        } else {
            cover
        }
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var hasMetadata: Bool {
        item.pageText != nil
            || readingProgressText != nil
            || (showsPopularity && item.likesCount != nil)
            || (showsFavoriteState && item.favoriteDate != nil)
    }

    private var visibleTagLimit: Int {
        min(max(maxVisibleTags, 1), 10)
    }

    private var visibleTags: [String] {
        displayTags ?? item.tags
    }

    private var resolvedTint: Color {
        coverTint ?? item.accentColor
    }
}

private struct ComicListSnapshotKey: Hashable, Sendable {
    nonisolated private static let sourcePrefixLimit = 128

    let comicsCount: Int
    let comicsHash: Int
    let sourcePrefix: [ComicListSourceItemIdentity]
    let readingRecordsRevision: Int
    let readLaterRevision: Int
    let blockingFingerprint: Int
    let appliesBlocking: Bool
    let appliesReadProgressFilter: Bool
    let appliesReadLaterFilter: Bool
    let hidesReadComicsInLists: Bool
    let hidesReadLaterComicsInLists: Bool
    let hiddenProgressThreshold: Int
    let tagDisplayVersion: Int

    static let empty = ComicListSnapshotKey(
        comicsCount: 0,
        comicsHash: 0,
        sourcePrefix: [],
        readingRecordsRevision: 0,
        readLaterRevision: 0,
        blockingFingerprint: 0,
        appliesBlocking: false,
        appliesReadProgressFilter: false,
        appliesReadLaterFilter: false,
        hidesReadComicsInLists: false,
        hidesReadLaterComicsInLists: false,
        hiddenProgressThreshold: 0,
        tagDisplayVersion: 0
    )

    init(
        comics: [ComicListItem],
        readingRecordsRevision: Int,
        readLaterRevision: Int,
        blockingMatcher: BlockingKeywordMatcher,
        appliesBlocking: Bool,
        appliesReadProgressFilter: Bool,
        appliesReadLaterFilter: Bool,
        hidesReadComicsInLists: Bool,
        hidesReadLaterComicsInLists: Bool,
        hiddenProgressThreshold: Int,
        tagDisplayVersion: Int
    ) {
        let filtersReadProgress = appliesReadProgressFilter && hidesReadComicsInLists
        let filtersReadLater = appliesReadLaterFilter && hidesReadLaterComicsInLists
        comicsCount = comics.count
        comicsHash = Self.comicsHash(comics)
        sourcePrefix = Self.sourcePrefix(for: comics)
        self.readingRecordsRevision = readingRecordsRevision
        self.readLaterRevision = filtersReadLater ? readLaterRevision : 0
        blockingFingerprint = appliesBlocking ? blockingMatcher.fingerprint : 0
        self.appliesBlocking = appliesBlocking
        self.appliesReadProgressFilter = appliesReadProgressFilter
        self.appliesReadLaterFilter = appliesReadLaterFilter
        self.hidesReadComicsInLists = filtersReadProgress
        self.hidesReadLaterComicsInLists = filtersReadLater
        self.hiddenProgressThreshold = filtersReadProgress ? hiddenProgressThreshold : 0
        self.tagDisplayVersion = tagDisplayVersion
    }

    private init(
        comicsCount: Int,
        comicsHash: Int,
        sourcePrefix: [ComicListSourceItemIdentity],
        readingRecordsRevision: Int,
        readLaterRevision: Int,
        blockingFingerprint: Int,
        appliesBlocking: Bool,
        appliesReadProgressFilter: Bool,
        appliesReadLaterFilter: Bool,
        hidesReadComicsInLists: Bool,
        hidesReadLaterComicsInLists: Bool,
        hiddenProgressThreshold: Int,
        tagDisplayVersion: Int
    ) {
        self.comicsCount = comicsCount
        self.comicsHash = comicsHash
        self.sourcePrefix = sourcePrefix
        self.readingRecordsRevision = readingRecordsRevision
        self.readLaterRevision = readLaterRevision
        self.blockingFingerprint = blockingFingerprint
        self.appliesBlocking = appliesBlocking
        self.appliesReadProgressFilter = appliesReadProgressFilter
        self.appliesReadLaterFilter = appliesReadLaterFilter
        self.hidesReadComicsInLists = hidesReadComicsInLists
        self.hidesReadLaterComicsInLists = hidesReadLaterComicsInLists
        self.hiddenProgressThreshold = hiddenProgressThreshold
        self.tagDisplayVersion = tagDisplayVersion
    }

    nonisolated func canRetainDisplayedRows(whileRebuilding requestKey: ComicListSnapshotKey) -> Bool {
        guard comicsCount > 0 else { return false }
        if hasSameSourceContent(as: requestKey) {
            return true
        }

        guard appliesBlocking == requestKey.appliesBlocking,
              appliesReadProgressFilter == requestKey.appliesReadProgressFilter,
              appliesReadLaterFilter == requestKey.appliesReadLaterFilter,
              hidesReadComicsInLists == requestKey.hidesReadComicsInLists,
              hidesReadLaterComicsInLists == requestKey.hidesReadLaterComicsInLists,
              hiddenProgressThreshold == requestKey.hiddenProgressThreshold,
              blockingFingerprint == requestKey.blockingFingerprint else {
            return false
        }

        if appliesReadProgressFilter,
           hidesReadComicsInLists,
           readingRecordsRevision != requestKey.readingRecordsRevision {
            return false
        }

        if appliesReadLaterFilter,
           hidesReadLaterComicsInLists,
           readLaterRevision != requestKey.readLaterRevision {
            return false
        }

        let keepsAppendedContent = requestKey.comicsCount > comicsCount
            && requestKey.sourcePrefix.starts(with: sourcePrefix)
        let keepsSameContent = requestKey.comicsCount == comicsCount
            && requestKey.comicsHash == comicsHash
            && requestKey.sourcePrefix == sourcePrefix
        return keepsAppendedContent || keepsSameContent
    }

    nonisolated func canPreserveRenderedCount(afterRebuildingFor requestKey: ComicListSnapshotKey) -> Bool {
        hasSameSourceContent(as: requestKey)
    }

    private nonisolated func hasSameSourceContent(as other: ComicListSnapshotKey) -> Bool {
        comicsCount == other.comicsCount
            && comicsHash == other.comicsHash
            && sourcePrefix == other.sourcePrefix
    }

    private nonisolated static func comicsHash(_ comics: [ComicListItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(comics.count)
        for comic in comics {
            hasher.combine(comic.id)
            hasher.combine(comic.platform.rawValue)
            hasher.combine(comic.title)
            hasher.combine(comic.subtitle)
            hasher.combine(comic.coverURLString)
            hasher.combine(comic.pageCount)
            hasher.combine(comic.likesCount)
            hasher.combine(comic.favoriteDate?.timeIntervalSinceReferenceDate)
            hasher.combine(comic.tags.count)
            for tag in comic.tags {
                hasher.combine(tag)
            }
        }
        return hasher.finalize()
    }

    private nonisolated static func sourcePrefix(for comics: [ComicListItem]) -> [ComicListSourceItemIdentity] {
        comics.prefix(sourcePrefixLimit).map(ComicListSourceItemIdentity.init)
    }

}

private struct ComicListSourceItemIdentity: Hashable, Sendable {
    let platform: ComicPlatform
    let id: String
    let title: String
    let subtitle: String
    let coverURLString: String
    let tags: [String]
    let pageCount: Int?
    let likesCount: Int?
    let favoriteDate: Date?

    nonisolated init(item: ComicListItem) {
        platform = item.platform
        id = item.id
        title = item.title
        subtitle = item.subtitle
        coverURLString = item.coverURLString
        tags = item.tags
        pageCount = item.pageCount
        likesCount = item.likesCount
        favoriteDate = item.favoriteDate
    }

    nonisolated static func == (lhs: ComicListSourceItemIdentity, rhs: ComicListSourceItemIdentity) -> Bool {
        lhs.platform.rawValue == rhs.platform.rawValue
            && lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.coverURLString == rhs.coverURLString
            && lhs.tags == rhs.tags
            && lhs.pageCount == rhs.pageCount
            && lhs.likesCount == rhs.likesCount
            && lhs.favoriteDate == rhs.favoriteDate
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(platform.rawValue)
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(subtitle)
        hasher.combine(coverURLString)
        hasher.combine(tags)
        hasher.combine(pageCount)
        hasher.combine(likesCount)
        hasher.combine(favoriteDate)
    }
}

private struct ComicListSnapshotRequest: Sendable {
    let key: ComicListSnapshotKey
    let comics: [ComicListItem]
    let readingRecordsByID: [String: ReadingHistoryRecord]
    let readLaterIDs: Set<String>
    let blockingMatcher: BlockingKeywordMatcher
    let appliesBlocking: Bool
    let appliesReadProgressFilter: Bool
    let appliesReadLaterFilter: Bool
    let hidesReadComicsInLists: Bool
    let hidesReadLaterComicsInLists: Bool
    let hiddenProgressThreshold: Int
}

private struct ComicListRenderSnapshot: Sendable {
    let key: ComicListSnapshotKey
    let visibleComics: [ComicListItem]
    let readingRecordsByID: [String: ReadingHistoryRecord]
    let displayTagsByID: [String: [String]]
    let contentIdentity: ComicListContentIdentity

    static let empty = ComicListRenderSnapshot(
        key: .empty,
        visibleComics: [],
        readingRecordsByID: [:],
        displayTagsByID: [:],
        contentIdentity: .empty
    )

    nonisolated func canDisplayWhileRebuilding(for request: ComicListSnapshotRequest) -> Bool {
        key.canRetainDisplayedRows(whileRebuilding: request.key)
    }

    nonisolated static func make(for request: ComicListSnapshotRequest) throws -> ComicListRenderSnapshot {
        var visibleComics: [ComicListItem] = []
        visibleComics.reserveCapacity(request.comics.count)

        for (index, comic) in request.comics.enumerated() {
            if index.isMultiple(of: 64), Task.isCancelled {
                throw CancellationError()
            }
            if request.appliesBlocking, request.blockingMatcher.blockedKeyword(for: comic) != nil {
                continue
            }
            if request.appliesReadProgressFilter,
               shouldHideReadComic(
                    comic,
                    record: request.readingRecordsByID[comic.readingHistoryID],
                    hidesReadComicsInLists: request.hidesReadComicsInLists,
                    hiddenProgressThreshold: request.hiddenProgressThreshold
               ) {
                continue
            }
            if request.appliesReadLaterFilter,
               request.hidesReadLaterComicsInLists,
               request.readLaterIDs.contains(comic.readingHistoryID) {
                continue
            }
            visibleComics.append(comic)
        }

        return ComicListRenderSnapshot(
            key: request.key,
            visibleComics: visibleComics,
            readingRecordsByID: request.readingRecordsByID,
            displayTagsByID: ComicListTagDisplayResolver.displayTagsByID(for: visibleComics),
            contentIdentity: makeContentIdentity(for: visibleComics)
        )
    }

    private nonisolated static func makeContentIdentity(for visibleComics: [ComicListItem]) -> ComicListContentIdentity {
        let prefixCount = min(48, visibleComics.count)
        var hasher = Hasher()
        hasher.combine(prefixCount)
        for comic in visibleComics.prefix(prefixCount) {
            hasher.combine(comic.readingHistoryID)
        }
        return ComicListContentIdentity(
            totalCount: visibleComics.count,
            leadingCount: prefixCount,
            leadingHash: hasher.finalize()
        )
    }

    private nonisolated static func shouldHideReadComic(
        _ comic: ComicListItem,
        record: ReadingHistoryRecord?,
        hidesReadComicsInLists: Bool,
        hiddenProgressThreshold: Int
    ) -> Bool {
        guard hidesReadComicsInLists else { return false }
        guard let progress = record?.progress,
              progress.status != .viewed else {
            return false
        }

        let threshold = min(max(hiddenProgressThreshold, 0), 100)
        let progressPercent: Int
        if progress.status == .finished {
            progressPercent = 100
        } else if progress.totalPages > 0 {
            let currentPage = min(max(progress.pageIndex + 1, 0), progress.totalPages)
            progressPercent = min(max(Int((Double(currentPage) / Double(progress.totalPages) * 100).rounded()), 0), 100)
        } else {
            progressPercent = progress.pageIndex > 0 ? 100 : 0
        }
        return progressPercent >= threshold
    }
}

private struct ComicListDisplayedRow: Identifiable {
    let item: ComicListItem
    let hasReadingProgress: Bool
    let readingProgressText: String?
    let displayTags: [String]?

    var id: String {
        item.readingHistoryID
    }
}

private struct ComicWaterfallBottomPreferenceKey: PreferenceKey {
    static var defaultValue = CGFloat.greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ComicWaterfallPaginationTrigger: Equatable {
    enum Action: Equatable {
        case revealLocal
        case loadRemote
    }

    let action: Action
    let firstComicID: String?
    let lastComicID: String?
    let displayedCount: Int
    let totalVisibleCount: Int
}

private struct ComicWaterfallColumn: Identifiable {
    let id: Int
    var entries: [ComicWaterfallEntry]
}

private struct ComicWaterfallEntry: Identifiable {
    let row: ComicListDisplayedRow
    let sourceIndex: Int

    var id: String {
        row.id
    }
}

private enum ComicListTagDisplayResolver {
    nonisolated static func displayTagsByID(for comics: [ComicListItem]) -> [String: [String]] {
        let nhentaiCache = PicaXSQLiteStore.loadNhentaiTagNames(ids: nhentaiTagIDs(in: comics))
        var result: [String: [String]] = [:]

        for (index, comic) in comics.enumerated() {
            if index.isMultiple(of: 64), Task.isCancelled {
                break
            }
            let displayTags = displayTags(for: comic, nhentaiCache: nhentaiCache)
            if displayTags != comic.tags {
                result[comic.readingHistoryID] = displayTags
            }
        }
        return result
    }

    private nonisolated static func displayTags(
        for comic: ComicListItem,
        nhentaiCache: [Int: StoredNhentaiTagName]
    ) -> [String] {
        let tags = comic.tags.compactMap { tag in
            displayTitle(for: tag, platform: comic.platform, nhentaiCache: nhentaiCache)
        }
        guard tags.isEmpty,
              comic.platform == .nhentai,
              comic.tags.contains(where: { nhentaiTagID(from: $0) != nil }) else {
            return tags
        }
        return ["正在解析标签"]
    }

    private nonisolated static func nhentaiTagIDs(in comics: [ComicListItem]) -> [Int] {
        var ids: [Int] = []
        for comic in comics where comic.platform == .nhentai {
            ids.append(contentsOf: comic.tags.compactMap(nhentaiTagID(from:)))
        }
        return ids
    }

    private nonisolated static func displayTitle(
        for tag: String,
        platform: ComicPlatform,
        nhentaiCache: [Int: StoredNhentaiTagName]
    ) -> String? {
        switch platform {
        case .nhentai:
            if let id = nhentaiTagID(from: tag) {
                guard let record = nhentaiCache[id] else { return nil }
                return NhentaiTagSuggestionService.translatedTitle(forTagName: record.name, group: record.group)
            }
            if let scopedTag = scopedTag(from: tag) {
                return NhentaiTagSuggestionService.translatedTitle(
                    forTagName: scopedTag.value,
                    group: scopedTag.namespace
                )
            }
            return NhentaiTagSuggestionService.translatedTitle(forTagName: tag)
        case .eHentai:
            if let scopedTag = scopedTag(from: tag) {
                return EhTagTranslationService.translatedTagTitle(
                    title: scopedTag.value,
                    query: tag,
                    namespace: scopedTag.namespace
                )
            }
            return EhTagTranslationService.translatedAnyTagTitle(tag)
        case .hitomi:
            return EhTagTranslationService.translatedAnyTagTitle(tag)
        case .picacg, .jmComic, .htManga:
            return tag
        }
    }

    private nonisolated static func nhentaiTagID(from tag: String) -> Int? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("tag:") else { return nil }
        return Int(trimmed.dropFirst("tag:".count))
    }

    private nonisolated static func scopedTag(from tag: String) -> (namespace: String, value: String)? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.firstIndex(of: ":") else { return nil }
        let namespace = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !namespace.isEmpty, !value.isEmpty else { return nil }
        return (namespace, value)
    }
}

private struct ComicListContentIdentity: Equatable, Sendable {
    let totalCount: Int
    let leadingCount: Int
    let leadingHash: Int

    static let empty = ComicListContentIdentity(totalCount: 0, leadingCount: 0, leadingHash: 0)
}

private struct ComicListHorizontalContentRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComicListTagRow: View {
    let tags: [String]
    let limit: Int
    let accentColor: Color

    var body: some View {
        ComicListHorizontalContentRow {
            tagRow(limit: visibleLimit)
        }
    }

    private var visibleLimit: Int {
        min(max(limit, 1), tags.count)
    }

    private func tagRow(limit: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<min(tags.count, limit), id: \.self) { index in
                Text(tags[index])
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct ComicListMetaPill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.background.opacity(0.65), in: Capsule())
    }
}

struct ComicCoverView: View {
    let url: URL?
    let accentColor: Color
    var width: CGFloat?
    var height: CGFloat?
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var storesInCache = true

    var body: some View {
        CachedRemoteImageView(url: url, accentColor: accentColor, contentMode: .fill, storesInCache: storesInCache, maxPixelSize: 512)
            .frame(width: width, height: height)
            .frame(
                maxWidth: width == nil ? .infinity : nil,
                maxHeight: height == nil ? .infinity : nil
            )
            .clipped()
        .background(AppColor.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .picaxSensitiveImageContent(url != nil)
    }
}

struct LoadingComicListView: View {
    let accentColor: Color

    var body: some View {
        LoadingStateView(title: "正在加载漫画", showsBackground: false)
    }
}

enum ComicSearchTarget: Hashable, Identifiable {
    case aggregate([ComicPlatform])
    case platform(ComicPlatform)

    static var defaultAggregate: ComicSearchTarget {
        .aggregate(ComicPlatform.allCases)
    }

    var id: String {
        switch self {
        case .aggregate(let platforms):
            "aggregate-\(Self.normalizedPlatforms(platforms).map(\.id).joined(separator: "-"))"
        case .platform(let platform):
            platform.id
        }
    }

    var title: String {
        switch self {
        case .aggregate(let platforms):
            let normalized = Self.normalizedPlatforms(platforms)
            if normalized.count == ComicPlatform.allCases.count {
                return "多平台聚合"
            }
            return "\(normalized.count) 个平台聚合"
        case .platform(let platform):
            return platform.title
        }
    }

    var systemImage: String {
        switch self {
        case .aggregate:
            "square.grid.2x2"
        case .platform(let platform):
            platform.systemImage
        }
    }

    var accentColor: Color {
        switch self {
        case .aggregate:
            .blue
        case .platform(let platform):
            platform.accentColor
        }
    }

    var platforms: [ComicPlatform] {
        switch self {
        case .aggregate(let platforms):
            Self.normalizedPlatforms(platforms)
        case .platform(let platform):
            [platform]
        }
    }

    var isAggregate: Bool {
        if case .aggregate = self { return true }
        return false
    }

    var platformSummary: String {
        switch self {
        case .aggregate(let platforms):
            Self.normalizedPlatforms(platforms).map(\.title).joined(separator: "、")
        case .platform(let platform):
            platform.title
        }
    }

    private static func normalizedPlatforms(_ platforms: [ComicPlatform]) -> [ComicPlatform] {
        let selected = Set(platforms)
        let normalized = ComicPlatform.allCases.filter { selected.contains($0) }
        return normalized.isEmpty ? ComicPlatform.allCases : normalized
    }

    static func configuredDefault(defaults: UserDefaults = .standard) -> ComicSearchTarget {
        let mode = SearchDefaultTargetMode(rawValue: defaults.string(forKey: SearchSettingsKey.defaultTargetMode) ?? "") ?? .platform
        switch mode {
        case .platform:
            let platformID = defaults.string(forKey: SearchSettingsKey.defaultPlatform) ?? ComicPlatform.picacg.rawValue
            return .platform(ComicPlatform(rawValue: platformID) ?? .picacg)
        case .aggregate:
            let platformIDs = defaults.string(forKey: SearchSettingsKey.defaultAggregatePlatforms) ?? Self.defaultAggregatePlatformIDs
            let platforms = platformIDs
                .split(separator: ",")
                .compactMap { ComicPlatform(rawValue: String($0)) }
            return .aggregate(platforms)
        }
    }

    private static var defaultAggregatePlatformIDs: String {
        ComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    }
}

struct ComicSearchPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var searchHistory: SearchHistoryService
    @AppStorage(SearchSettingsKey.focusesSearchFieldOnOpen) private var focusesSearchFieldOnOpen = false
    @AppStorage(SearchSettingsKey.enablesSearchSuggestions) private var enablesSearchSuggestions = true
    @AppStorage(SearchSettingsKey.suggestionSelectionBehavior) private var suggestionSelectionBehavior = SearchSuggestionSelectionBehavior.fill.rawValue
    @AppStorage(SearchSettingsKey.defaultTargetMode) private var defaultTargetMode = SearchDefaultTargetMode.platform.rawValue
    @AppStorage(SearchSettingsKey.defaultPlatform) private var defaultSearchPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage(SearchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = ComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    let service: ComicContentService
    private let usesConfiguredDefaultTarget: Bool
    private let recordsInitialSearchInHistory: Bool
    private let hidesTabBar: Bool
    @StateObject private var viewModel: ComicSearchViewModel
    @State private var query: String
    @State private var selectedSearchTarget: ComicSearchTarget
    @State private var aggregatePlatforms = Set(ComicPlatform.allCases)
    @State private var searchOptions = ComicSearchAdvancedOptions()
    @State private var showsAdvancedOptions = false
    @State private var hiddenTagSuggestionsQuery: String?
    @State private var searchSubmitSuppressionGeneration = 0
    @State private var suppressedSearchSubmitGeneration: Int?
    @State private var searchCancelRestorationCandidate: String?
    @State private var searchClearGeneration = 0
    @FocusState private var isSearchFocused: Bool

    init(
        initialQuery: String = "",
        platform: ComicPlatform? = nil,
        recordsInitialSearchInHistory: Bool = true,
        hidesTabBar: Bool = true,
        service: ComicContentService = ComicContentService()
    ) {
        self.service = service
        self.usesConfiguredDefaultTarget = platform == nil
        self.recordsInitialSearchInHistory = recordsInitialSearchInHistory
        self.hidesTabBar = hidesTabBar
        let initialTarget = platform.map(ComicSearchTarget.platform) ?? ComicSearchTarget.configuredDefault()
        _query = State(initialValue: initialQuery)
        _selectedSearchTarget = State(initialValue: initialTarget)
        if case .aggregate = initialTarget {
            let platforms = initialTarget.platforms
            _aggregatePlatforms = State(initialValue: Set(platforms))
        }
        _viewModel = StateObject(wrappedValue: ComicSearchViewModel(service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                if searchHistory.isEnabled, !searchHistory.records.isEmpty {
                    SearchHistoryListView(
                        records: searchHistory.records,
                        onSelect: applyHistory,
                        onDelete: searchHistory.remove
                    )
                } else {
                    ContentUnavailableView("搜索漫画", systemImage: "magnifyingglass", description: Text("输入关键词、作者或标签开始搜索"))
                }
            case .loading:
                LoadingComicListView(accentColor: selectedSearchTarget.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无结果", systemImage: "magnifyingglass", description: Text("换个关键词或平台试试"))
                } else {
                    ComicListSection(
                        comics: comics,
                        service: service,
                        isLoadingMore: viewModel.isLoadingMore,
                        hasMore: viewModel.hasMore,
                        loadMore: {
                            Task {
                                await loadMore()
                            }
                        }
                    )
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("搜索失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await search(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("搜索")
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar(hidesTabBar)
        .searchable(
            text: $query,
            placement: .picaxNavigationSearch,
            prompt: "搜索漫画、作者、标签"
        )
        .picaxSearchSuggestions {
            tagSuggestions
        }
        .picaxSearchFocused($isSearchFocused)
        .picaxOnChange(of: query) { oldValue, newValue in
            handleSearchQueryChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: isSearchFocused) { newValue in
            handleSearchFocusChange(isFocused: newValue)
        }
        .onSubmit(of: .search) {
            if suppressedSearchSubmitGeneration != nil {
                suppressedSearchSubmitGeneration = nil
                return
            }
            Task { await search(force: true) }
        }
        .onChange(of: selectedSearchTarget) { _ in
            guard viewModel.hasSearched else { return }
            Task { await search(force: true) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    showsAdvancedOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .foregroundStyle(isSearchOptionsCustomized ? selectedSearchTarget.accentColor : .primary)
                .accessibilityLabel("高级选项")

                ComicSearchTargetMenu(
                    selectedTarget: selectedSearchTarget,
                    aggregatePlatforms: aggregatePlatforms,
                    onSelectTarget: { selectedSearchTarget = $0 },
                    onToggleAggregatePlatform: toggleAggregatePlatform
                )
                .equatable()

                Button {
                    Task { await search(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.trimmedKeyword(query).isEmpty)
                .accessibilityLabel("刷新")
            }
        }
        .sheet(isPresented: $showsAdvancedOptions) {
            ComicSearchAdvancedOptionsSheet(target: selectedSearchTarget, options: $searchOptions) {
                guard viewModel.hasSearched else { return }
                Task { await search(force: true) }
            }
        }
        .task {
            applyConfiguredDefaultTargetIfNeeded()
            if focusesSearchFieldOnOpen, viewModel.trimmedKeyword(query).isEmpty {
                isSearchFocused = true
            }
            guard !viewModel.hasSearched, !viewModel.trimmedKeyword(query).isEmpty else { return }
            await search(force: true, recordsHistory: recordsInitialSearchInHistory)
        }
    }

    private func search(force: Bool = false, recordsHistory: Bool = true) async {
        let trimmedKeyword = viewModel.trimmedKeyword(query)
        guard !trimmedKeyword.isEmpty else { return }
        query = trimmedKeyword
        hiddenTagSuggestionsQuery = trimmedKeyword
        isSearchFocused = false
        if recordsHistory {
            searchHistory.record(keyword: trimmedKeyword, target: selectedSearchTarget)
        }
        await viewModel.search(
            target: selectedSearchTarget,
            keyword: trimmedKeyword,
            accounts: searchAccounts,
            options: searchOptions,
            force: force
        )
    }

    private func loadMore() async {
        await viewModel.loadMore(accounts: searchAccounts)
    }

    private func handleSearchQueryChange(oldValue: String, newValue: String) {
        if hiddenTagSuggestionsQuery != nil, newValue != hiddenTagSuggestionsQuery {
            hiddenTagSuggestionsQuery = nil
        }

        if newValue.isEmpty, !oldValue.isEmpty {
            searchCancelRestorationCandidate = oldValue
            searchClearGeneration += 1
            let generation = searchClearGeneration

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard searchClearGeneration == generation else { return }

                if !query.isEmpty {
                    searchCancelRestorationCandidate = nil
                } else if !isSearchFocused {
                    restoreQueryClearedBySearchCancel(generation: generation)
                } else {
                    searchCancelRestorationCandidate = nil
                }
            }
        } else if !newValue.isEmpty {
            searchCancelRestorationCandidate = nil
            searchClearGeneration += 1
        }
    }

    private func handleSearchFocusChange(isFocused: Bool) {
        guard !isFocused, query.isEmpty else { return }
        restoreQueryClearedBySearchCancel(generation: searchClearGeneration)
    }

    private func restoreQueryClearedBySearchCancel(generation: Int) {
        guard searchClearGeneration == generation,
              let candidate = searchCancelRestorationCandidate,
              query.isEmpty else {
            searchCancelRestorationCandidate = nil
            return
        }

        searchCancelRestorationCandidate = nil
        searchClearGeneration += 1
        query = candidate
    }

    private var searchAccounts: [ComicPlatform: PlatformAccount] {
        Dictionary(uniqueKeysWithValues: ComicPlatform.allCases.compactMap { platform in
            platformAccounts.account(for: platform).map { (platform, $0) }
        })
    }

    private var isSearchOptionsCustomized: Bool {
        selectedSearchTarget.platforms.contains { searchOptions.isCustomized(for: $0) }
    }

    private var configuredDefaultSearchTarget: ComicSearchTarget {
        switch SearchDefaultTargetMode(rawValue: defaultTargetMode) ?? .platform {
        case .platform:
            .platform(ComicPlatform(rawValue: defaultSearchPlatformID) ?? .picacg)
        case .aggregate:
            .aggregate(
                defaultAggregatePlatformIDs
                    .split(separator: ",")
                    .compactMap { ComicPlatform(rawValue: String($0)) }
            )
        }
    }

    private func applyConfiguredDefaultTargetIfNeeded() {
        guard usesConfiguredDefaultTarget, !viewModel.hasSearched else { return }
        let target = configuredDefaultSearchTarget
        selectedSearchTarget = target
        if case .aggregate = target {
            let platforms = target.platforms
            aggregatePlatforms = Set(platforms)
        }
    }

    private func toggleAggregatePlatform(_ platform: ComicPlatform) {
        var nextPlatforms = aggregatePlatforms
        if nextPlatforms.contains(platform) {
            guard nextPlatforms.count > 1 else { return }
            nextPlatforms.remove(platform)
        } else {
            nextPlatforms.insert(platform)
        }

        aggregatePlatforms = nextPlatforms
        selectedSearchTarget = .aggregate(ComicPlatform.allCases.filter { nextPlatforms.contains($0) })
    }

    private func applyHistory(_ record: SearchHistoryRecord) {
        query = record.keyword
        selectedSearchTarget = record.target.searchTarget
        if let aggregatePlatformSet = record.target.aggregatePlatformSet {
            aggregatePlatforms = aggregatePlatformSet
        }
        Task {
            await search(force: true)
        }
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        if hiddenTagSuggestionsQuery != query,
           enablesSearchSuggestions,
           selectedSearchTarget == .platform(.eHentai) {
            let suggestions = EhTagTranslationService.suggestions(for: query)
            if !suggestions.isEmpty {
                Section("E-Hentai 标签") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            applyTagSuggestion(
                                query: suggestion.query,
                                tag: suggestion.tag,
                                translatedTitle: suggestion.translatedTitle
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.query)
                                Text("\(suggestion.translatedTitle) · \(suggestion.namespaceTitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else if hiddenTagSuggestionsQuery != query,
                  enablesSearchSuggestions,
                  selectedSearchTarget == .platform(.nhentai) {
            let suggestions = NhentaiTagSuggestionService.suggestions(for: query)
            if !suggestions.isEmpty {
                Section("NHentai 标签") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            applyTagSuggestion(
                                query: suggestion.query,
                                tag: suggestion.tag,
                                translatedTitle: suggestion.translatedTitle
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.query)
                                Text("\(suggestion.translatedTitle) · \(suggestion.groupTitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyTagSuggestion(query suggestionQuery: String, tag: String, translatedTitle: String) {
        switch selectedSuggestionSelectionBehavior {
        case .fill:
            searchSubmitSuppressionGeneration += 1
            let suppressionGeneration = searchSubmitSuppressionGeneration
            suppressedSearchSubmitGeneration = suppressionGeneration
            query = query.replacingLastSearchFragment(
                with: "\(suggestionQuery) ",
                suggestionTag: tag,
                translatedTitle: translatedTitle
            )
            Task { @MainActor in
                await Task.yield()
                isSearchFocused = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                if suppressedSearchSubmitGeneration == suppressionGeneration {
                    suppressedSearchSubmitGeneration = nil
                }
            }
        case .search:
            query = suggestionQuery
            isSearchFocused = false
            Task {
                await search(force: true)
            }
        }
    }

    private var selectedSuggestionSelectionBehavior: SearchSuggestionSelectionBehavior {
        SearchSuggestionSelectionBehavior(rawValue: suggestionSelectionBehavior) ?? .fill
    }
}

private struct ComicSearchTargetMenu: View, Equatable {
    let selectedTarget: ComicSearchTarget
    let aggregatePlatforms: Set<ComicPlatform>
    let onSelectTarget: (ComicSearchTarget) -> Void
    let onToggleAggregatePlatform: (ComicPlatform) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedTarget == rhs.selectedTarget
            && lhs.aggregatePlatforms == rhs.aggregatePlatforms
    }

    var body: some View {
        Menu {
            Section("聚合搜索") {
                Button {
                    onSelectTarget(aggregateSearchTarget)
                } label: {
                    if selectedTarget.isAggregate {
                        Label(aggregateSearchTarget.title, systemImage: "checkmark")
                    } else {
                        Label(aggregateSearchTarget.title, systemImage: aggregateSearchTarget.systemImage)
                    }
                }

                ForEach(ComicPlatform.allCases) { platform in
                    Button {
                        onToggleAggregatePlatform(platform)
                    } label: {
                        Label(
                            platform.title,
                            systemImage: aggregatePlatforms.contains(platform) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }

            Divider()

            Section("单平台") {
                ForEach(ComicPlatform.allCases) { platform in
                    let target = ComicSearchTarget.platform(platform)
                    Button {
                        onSelectTarget(target)
                    } label: {
                        if selectedTarget == target {
                            Label(platform.title, systemImage: "checkmark")
                        } else {
                            Label(platform.title, systemImage: platform.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedTarget.systemImage)
        }
        .accessibilityLabel("选择平台")
    }

    private var aggregateSearchTarget: ComicSearchTarget {
        .aggregate(ComicPlatform.allCases.filter { aggregatePlatforms.contains($0) })
    }
}

private extension String {
    func replacingLastSearchFragment(with replacement: String, suggestionTag: String, translatedTitle: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return replacement }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let wordsToRemove = matchedTrailingWordCount(
            words: words,
            suggestionTag: suggestionTag,
            translatedTitle: translatedTitle
        )
        var prefixEnd = trimmed.endIndex

        for _ in 0..<wordsToRemove {
            while prefixEnd > trimmed.startIndex, trimmed[trimmed.index(before: prefixEnd)].isWhitespace {
                prefixEnd = trimmed.index(before: prefixEnd)
            }
            while prefixEnd > trimmed.startIndex, !trimmed[trimmed.index(before: prefixEnd)].isWhitespace {
                prefixEnd = trimmed.index(before: prefixEnd)
            }
        }

        let prefix = String(trimmed[..<prefixEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? replacement : "\(prefix) \(replacement)"
    }

    private func matchedTrailingWordCount(words: [String], suggestionTag: String, translatedTitle: String) -> Int {
        let maxWordCount = min(words.count, max(suggestionTag.split(separator: " ").count, 1))
        let normalizedTag = suggestionTag.lowercased()
        let normalizedTranslation = translatedTitle.lowercased()

        for count in stride(from: maxWordCount, through: 1, by: -1) {
            let fragment = words.suffix(count).joined(separator: " ").lowercased()
            let comparableFragment = fragment.suggestionComparableFragment
            guard !comparableFragment.isEmpty else { continue }
            if normalizedTag.hasPrefix(comparableFragment) || normalizedTranslation.hasPrefix(comparableFragment) {
                return count
            }
        }
        return 1
    }

    private var suggestionComparableFragment: String {
        guard let separatorIndex = lastIndex(of: ":") else { return self }
        return String(self[index(after: separatorIndex)...])
    }
}

private struct SearchHistoryListView: View {
    let records: [SearchHistoryRecord]
    let onSelect: (SearchHistoryRecord) -> Void
    let onDelete: (SearchHistoryRecord) -> Void

    var body: some View {
        List {
            Section("搜索历史") {
                ForEach(records) { record in
                    Button {
                        onSelect(record)
                    } label: {
                        SearchHistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
    }
}

private struct SearchHistoryRow: View {
    let record: SearchHistoryRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.keyword)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(record.subtitle) · \(record.searchedAtText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: record.target.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 4)
    }
}

private struct ComicSearchAdvancedOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: ComicSearchTarget
    @Binding var options: ComicSearchAdvancedOptions
    let onApply: () -> Void

    var body: some View {
        PicaxNavigationContainer {
            Form {
                if configurablePlatforms.isEmpty {
                    ContentUnavailableView("暂无高级选项", systemImage: "slider.horizontal.3", description: Text("\(target.title) 当前没有可用的搜索筛选项"))
                } else {
                    if target.isAggregate {
                        Section {
                            Text("聚合搜索会使用已选平台各自的搜索选项，并把结果合并展示。当前平台：\(target.platformSummary)。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(configurablePlatforms) { platform in
                        searchOptionsSection(for: platform)
                    }
                }
            }
            .navigationTitle("高级选项")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        resetTargetPlatforms()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }

    private var configurablePlatforms: [ComicPlatform] {
        target.platforms.filter { !$0.searchSortChoices.isEmpty || $0 == .nhentai }
    }

    private func searchOptionsSection(for platform: ComicPlatform) -> some View {
        Section(platform.title) {
            if !platform.searchSortChoices.isEmpty {
                Picker("排序", selection: sortSelection(for: platform)) {
                    ForEach(platform.searchSortChoices) { choice in
                        Text(choice.title).tag(choice.value)
                    }
                }
                .pickerStyle(.inline)
            }

            if platform == .nhentai {
                Picker("语言", selection: $options.nhentaiLanguage) {
                    Text("不限").tag(ComicSearchLanguage?.none)
                    ForEach(ComicSearchLanguage.allCases) { language in
                        Text(language.title).tag(Optional(language))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }

    private func sortSelection(for platform: ComicPlatform) -> Binding<String> {
        Binding {
            options.sortValue(for: platform)
        } set: { value in
            options.setSortValue(value, for: platform)
        }
    }

    private func resetTargetPlatforms() {
        for platform in target.platforms {
            reset(platform)
        }
    }

    private func reset(_ platform: ComicPlatform) {
        switch platform {
        case .picacg:
            options.picacgSort = "dd"
        case .nhentai:
            options.nhentaiSort = "date"
            options.nhentaiLanguage = nil
        case .jmComic:
            options.jmComicSort = "mr"
        case .eHentai, .htManga, .hitomi:
            break
        }
    }
}

struct ComicTagComicsPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    let tag: ComicTagReference
    let service: ComicContentService
    @StateObject private var viewModel: ComicTagComicsViewModel

    init(tag: ComicTagReference, service: ComicContentService = ComicContentService()) {
        self.tag = tag
        self.service = service
        _viewModel = StateObject(wrappedValue: ComicTagComicsViewModel(tag: tag, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingComicListView(accentColor: tag.platform.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无漫画", systemImage: "tag", description: Text("这个标签没有返回漫画"))
                } else {
                    ComicListSection(
                        comics: comics,
                        service: service,
                        isLoadingMore: viewModel.isLoadingMore,
                        hasMore: viewModel.hasMore,
                        loadMore: {
                            Task {
                                await loadMore()
                            }
                        }
                    )
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
        .navigationTitle(tag.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .picaxTopBarTrailing) {
                Button {
                    Task {
                        await load(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await load()
        }
    }

    private func load(force: Bool = false) async {
        await viewModel.load(account: platformAccounts.account(for: tag.platform), force: force)
    }

    private func loadMore() async {
        await viewModel.loadMore(account: platformAccounts.account(for: tag.platform))
    }
}

@MainActor
private final class ComicTagComicsViewModel: ObservableObject {
    @Published private(set) var state: ComicTagComicsLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false

    private let tag: ComicTagReference
    private let service: ComicContentService
    private var currentPage = 0
    private var loadedIDs = Set<String>()

    init(tag: ComicTagReference, service: ComicContentService) {
        self.tag = tag
        self.service = service
    }

    func load(account: PlatformAccount?, force: Bool = false) async {
        if case .loaded = state, !force {
            return
        }

        state = .loading
        currentPage = 0
        loadedIDs.removeAll()
        hasMore = false
        isLoadingMore = false
        do {
            let comics = try await service.loadTagComics(tag: tag, account: account, page: 1)
            let nextLoadedIDs = try await ComicListBackgroundProcessing.loadedIDs(from: comics, identity: .id)
            currentPage = 1
            loadedIDs = nextLoadedIDs
            hasMore = !comics.isEmpty
            state = .loaded(comics)
        } catch where error.isTaskCancellation {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore(account: PlatformAccount?) async {
        guard hasMore, !isLoadingMore, case .loaded(let comics) = state else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let newComics = try await service.loadTagComics(tag: tag, account: account, page: nextPage)
            let uniqueResult = try await ComicListBackgroundProcessing.uniqueItems(
                from: newComics,
                loadedIDs: loadedIDs,
                identity: .id
            )
            currentPage = nextPage
            loadedIDs = uniqueResult.loadedIDs
            hasMore = !newComics.isEmpty && !uniqueResult.items.isEmpty
            guard !uniqueResult.items.isEmpty else { return }
            state = .loaded(comics + uniqueResult.items)
        } catch where error.isTaskCancellation {
            return
        } catch {
            hasMore = false
        }
    }
}

private enum ComicTagComicsLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

@MainActor
private final class ComicSearchViewModel: ObservableObject {
    @Published private(set) var state: ComicSearchLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var hasSearched = false

    private let service: ComicContentService
    private var currentPage = 0
    private var currentPages: [ComicPlatform: Int] = [:]
    private var platformHasMore: [ComicPlatform: Bool] = [:]
    private var loadedIDs = Set<String>()
    private var currentTarget: ComicSearchTarget?
    private var currentKeyword = ""
    private var currentOptions = ComicSearchAdvancedOptions()

    init(service: ComicContentService) {
        self.service = service
    }

    func trimmedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(
        target: ComicSearchTarget,
        keyword: String,
        accounts: [ComicPlatform: PlatformAccount],
        options: ComicSearchAdvancedOptions,
        force: Bool = false
    ) async {
        let trimmed = trimmedKeyword(keyword)
        guard !trimmed.isEmpty else {
            reset()
            return
        }
        if case .loaded = state, !force, currentTarget == target, currentKeyword == trimmed, currentOptions == options {
            return
        }

        state = .loading
        hasSearched = true
        hasMore = false
        isLoadingMore = false
        currentPage = 0
        currentPages.removeAll()
        platformHasMore.removeAll()
        loadedIDs.removeAll()
        currentTarget = target
        currentKeyword = trimmed
        currentOptions = options

        var groups: [[ComicListItem]] = []
        var failures: [String] = []
        for platform in target.platforms {
            do {
                let comics = try await service.searchComics(
                    platform: platform,
                    keyword: trimmed,
                    account: accounts[platform],
                    page: 1,
                    options: options
                )
                currentPages[platform] = 1
                platformHasMore[platform] = !comics.isEmpty
                groups.append(comics)
            } catch {
                guard !error.isTaskCancellation else {
                    return
                }
                currentPages[platform] = 0
                platformHasMore[platform] = false
                failures.append("\(platform.title): \(error.localizedDescription)")
            }
        }

        currentPage = 1
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
        loadedIDs = uniqueResult.loadedIDs
        let comics = uniqueResult.items
        hasMore = platformHasMore.values.contains(true)
        if !comics.isEmpty || failures.count < target.platforms.count {
            state = .loaded(comics)
        } else {
            state = .failed(failures.joined(separator: "\n"))
        }
    }

    func loadMore(accounts: [ComicPlatform: PlatformAccount]) async {
        guard hasMore, !isLoadingMore, case .loaded(let comics) = state, let target = currentTarget, !currentKeyword.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        var groups: [[ComicListItem]] = []
        for platform in target.platforms where platformHasMore[platform] == true {
            do {
                let nextPage = (currentPages[platform] ?? currentPage) + 1
                let newComics = try await service.searchComics(
                    platform: platform,
                    keyword: currentKeyword,
                    account: accounts[platform],
                    page: nextPage,
                    options: currentOptions
                )
                currentPages[platform] = nextPage
                platformHasMore[platform] = !newComics.isEmpty
                groups.append(newComics)
            } catch {
                guard !error.isTaskCancellation else {
                    return
                }
                platformHasMore[platform] = false
            }
        }

        currentPage += 1
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
        loadedIDs = uniqueResult.loadedIDs
        let uniqueComics = uniqueResult.items
        hasMore = platformHasMore.values.contains(true)
        guard !uniqueComics.isEmpty else {
            if !hasMore {
                state = .loaded(comics)
            }
            return
        }
        state = .loaded(comics + uniqueComics)
    }

    private func reset() {
        state = .idle
        isLoadingMore = false
        hasMore = false
        currentPage = 0
        currentPages.removeAll()
        platformHasMore.removeAll()
        loadedIDs.removeAll()
        currentTarget = nil
        currentKeyword = ""
        currentOptions = ComicSearchAdvancedOptions()
    }

}

private enum ComicSearchLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

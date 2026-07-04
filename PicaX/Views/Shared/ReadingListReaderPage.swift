import SwiftUI

struct ReadingListEntry: Identifiable, Hashable {
    let id: String
    let item: ComicListItem
    let downloadedRecord: DownloadRecord?
    let presetDetail: ComicDetailInfo?
    let coverURL: URL?
    let localChapterIndexes: [Int]?

    nonisolated static func online(_ item: ComicListItem) -> ReadingListEntry {
        ReadingListEntry(
            id: item.readingHistoryID,
            item: item,
            downloadedRecord: nil,
            presetDetail: nil,
            coverURL: URL.picaxResolved(from: item.coverURLString),
            localChapterIndexes: nil
        )
    }

    static func downloaded(_ record: DownloadRecord, coverURL: URL?) -> ReadingListEntry {
        let chapters = record.chapters.sorted { $0.index < $1.index }
        let detail = localDetail(for: record, downloadedChapters: chapters)
        return ReadingListEntry(
            id: "download-\(record.id)",
            item: record.item,
            downloadedRecord: record,
            presetDetail: detail,
            coverURL: coverURL,
            localChapterIndexes: chapters.map(\.index)
        )
    }

    static func == (lhs: ReadingListEntry, rhs: ReadingListEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated private static func fallbackTagGroups(for item: ComicListItem) -> [ComicTagGroup] {
        guard !item.tags.isEmpty else { return [] }
        return [
            ComicTagGroup(
                title: "标签",
                tags: item.tags.map {
                    ComicTagReference(title: $0, query: $0, platform: item.platform, urlString: nil)
                }
            )
        ]
    }

    private static func localDetail(for record: DownloadRecord, downloadedChapters: [DownloadedChapterRecord]) -> ComicDetailInfo {
        if let detail = record.detail {
            var localDetail = ComicDetailInfo(
                item: detail.item,
                description: detail.description,
                tagGroups: detail.tagGroups,
                chapters: downloadedChapters.map(\.chapter),
                related: detail.related,
                updatedText: detail.updatedText
            )
            localDetail.isLiked = detail.isLiked
            localDetail.uploader = detail.uploader
            return localDetail
        }
        return ComicDetailInfo(
            item: record.item,
            description: record.item.subtitle,
            tagGroups: fallbackTagGroups(for: record.item),
            chapters: downloadedChapters.map(\.chapter),
            related: [],
            updatedText: nil
        )
    }
}

struct ReadingListRequest: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let entries: [ReadingListEntry]
    let startIndex: Int

    init(title: String, entries: [ReadingListEntry], startIndex: Int = 0) {
        self.title = title
        self.entries = entries
        self.startIndex = min(max(startIndex, 0), max(entries.count - 1, 0))
    }

    static func == (lhs: ReadingListRequest, rhs: ReadingListRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ComicReaderListContext {
    let title: String
    let entries: [ReadingListEntry]
    let currentEntryID: String?
    let currentIndex: Int
    let totalCount: Int
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let selectEntry: (ReadingListEntry) -> Void
    let removeEntries: (IndexSet) -> Void
    let movePrevious: () -> Void
    let moveNext: () -> Void
}

struct ReadingListReaderPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(ReaderSettingsKey.showsReadingListLoadingToast) private var showsReadingListLoadingToast = true

    let request: ReadingListRequest
    let service: ComicContentService

    @State private var entries: [ReadingListEntry]
    @State private var currentEntryID: String?
    @State private var loadedEntry: LoadedReadingListEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingBookToastTitle: String?

    init(request: ReadingListRequest, service: ComicContentService) {
        self.request = request
        self.service = service
        _entries = State(initialValue: request.entries)
        _currentEntryID = State(initialValue: request.entries.indices.contains(request.startIndex) ? request.entries[request.startIndex].id : nil)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("阅读列表为空", systemImage: "list.bullet.rectangle", description: Text("阅读列表中的漫画已全部移除。"))
            } else if let loadedEntry {
                reader(for: loadedEntry)
                    .overlay(alignment: .bottom) {
                        if showsLoadingToast {
                            ReaderToastView(message: "加载中……")
                                .padding(.horizontal, 24)
                                .padding(.bottom, 86)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .allowsHitTesting(false)
                        }
                    }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("打开失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task { await loadCurrentEntry(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                LoadingStateView(title: "正在准备阅读")
            }
        }
        .animation(.easeInOut(duration: 0.16), value: showsLoadingToast)
        .navigationTitle(request.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .task(id: currentEntryID) {
            await loadCurrentEntry()
        }
    }

    private func reader(for loadedEntry: LoadedReadingListEntry) -> some View {
        let entry = loadedEntry.entry
        let imageProvider: ((ComicChapter, Int) async -> [ComicChapterImage])?
        let commentsProvider: ((ComicChapter, Int) async -> [ComicComment])?
        let historyChapterIndexResolver: (Int) -> Int
        if let record = entry.downloadedRecord {
            imageProvider = { _, chapterIndex in
                guard let localChapterIndexes = entry.localChapterIndexes,
                      localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                let localChapterIndex = localChapterIndexes[chapterIndex]
                return await downloadService.localChapterImages(for: record, chapterIndex: localChapterIndex)
            }
            commentsProvider = { _, chapterIndex in
                guard let localChapterIndexes = entry.localChapterIndexes,
                      localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                let localChapterIndex = localChapterIndexes[chapterIndex]
                return await downloadService.localChapterComments(for: record, chapterIndex: localChapterIndex)
            }
            historyChapterIndexResolver = { chapterIndex in
                guard let localChapterIndexes = entry.localChapterIndexes,
                      localChapterIndexes.indices.contains(chapterIndex) else { return chapterIndex }
                return localChapterIndexes[chapterIndex]
            }
        } else {
            imageProvider = nil
            commentsProvider = nil
            historyChapterIndexResolver = { $0 }
        }

        return ComicReaderPage(
            detail: loadedEntry.detail,
            initialChapterIndex: 0,
            initialPageIndex: 0,
            ignoresHistoryProgress: true,
            service: service,
            localChapterImageProvider: imageProvider,
            localChapterCommentsProvider: commentsProvider,
            historyChapterIndexResolver: historyChapterIndexResolver,
            listContext: listContext(for: loadedEntry.entryID),
            initialToastMessage: pendingBookToastTitle
        )
        .id(loadedEntry.entryID)
    }

    private var showsLoadingToast: Bool {
        showsReadingListLoadingToast && isLoading && loadedEntry?.entryID != currentEntryID
    }

    private var currentIndex: Int? {
        guard let currentEntryID else { return nil }
        return entries.firstIndex { $0.id == currentEntryID }
    }

    private func listContext(for entryID: String?) -> ComicReaderListContext {
        let index = entryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? currentIndex ?? 0
        return ComicReaderListContext(
            title: request.title,
            entries: entries,
            currentEntryID: entryID,
            currentIndex: index,
            totalCount: entries.count,
            canMovePrevious: !isLoading && index > 0,
            canMoveNext: !isLoading && index + 1 < entries.count,
            selectEntry: selectEntry,
            removeEntries: removeEntries,
            movePrevious: movePrevious,
            moveNext: moveNext
        )
    }

    @MainActor
    private func loadCurrentEntry(force: Bool = false) async {
        guard let activeEntryID = currentEntryID,
              let entry = entries.first(where: { $0.id == activeEntryID }) else {
            loadedEntry = nil
            errorMessage = entries.isEmpty ? nil : "阅读列表中的当前漫画不存在。"
            return
        }
        if !force, loadedEntry?.entryID == activeEntryID {
            return
        }

        let previousLoadedEntry = loadedEntry
        isLoading = true
        errorMessage = nil
        do {
            let detail: ComicDetailInfo
            if let presetDetail = entry.presetDetail {
                detail = presetDetail
            } else {
                detail = try await service.loadDetail(
                    item: entry.item,
                    account: platformAccounts.account(for: entry.item.platform)
                )
            }
            loadedEntry = LoadedReadingListEntry(entry: entry, detail: detail)
        } catch {
            if let previousLoadedEntry {
                currentEntryID = previousLoadedEntry.entryID
                pendingBookToastTitle = nil
            } else {
                errorMessage = error.localizedDescription
                loadedEntry = nil
            }
        }
        isLoading = false
    }

    private func selectEntry(_ entry: ReadingListEntry) {
        guard !isLoading else { return }
        if currentEntryID != entry.id {
            pendingBookToastTitle = entry.item.title
        }
        currentEntryID = entry.id
    }

    private func movePrevious() {
        guard !isLoading else { return }
        guard let currentIndex, currentIndex > 0 else { return }
        let entry = entries[currentIndex - 1]
        pendingBookToastTitle = entry.item.title
        currentEntryID = entry.id
    }

    private func moveNext() {
        guard !isLoading else { return }
        guard let currentIndex, currentIndex + 1 < entries.count else { return }
        let entry = entries[currentIndex + 1]
        pendingBookToastTitle = entry.item.title
        currentEntryID = entry.id
    }

    private func removeEntries(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        let removingCurrent = offsets.contains(currentIndex ?? -1)
        let oldCurrentIndex = currentIndex
        entries.remove(atOffsets: offsets)

        guard !entries.isEmpty else {
            currentEntryID = nil
            loadedEntry = nil
            return
        }

        if removingCurrent {
            let targetIndex = min(oldCurrentIndex ?? 0, entries.count - 1)
            currentEntryID = entries[targetIndex].id
        } else if let activeEntryID = currentEntryID,
                  !entries.contains(where: { $0.id == activeEntryID }) {
            currentEntryID = entries[min(oldCurrentIndex ?? 0, entries.count - 1)].id
        }
    }
}

private struct LoadedReadingListEntry {
    let entry: ReadingListEntry
    let detail: ComicDetailInfo

    var entryID: String { entry.id }
}

struct ReadingListEntryRow: View {
    let entry: ReadingListEntry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ComicCoverView(url: entry.coverURL ?? entry.item.coverURL, accentColor: entry.item.accentColor, width: 46, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(entry.item.subtitle.isEmpty ? entry.item.platformTitle : entry.item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(entry.item.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

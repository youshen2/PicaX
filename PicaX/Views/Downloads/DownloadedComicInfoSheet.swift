import SwiftUI

struct DownloadedComicInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadService: DownloadService
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    @AppStorage(DownloadSettingsKey.recordsDownloadedReadingHistory) private var recordsDownloadedReadingHistory = true

    let record: DownloadRecord
    let service: ComicContentService
    let openReader: (DownloadedComicReaderRequest) -> Void
    let openSearch: (DownloadedComicSearchRequest) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        DownloadedComicInfoHeader(record: record, coverURL: localCoverURL)
                    }

                    if localDetail.item.copyAction != nil {
                        Section("操作") {
                            ComicCopyActionButton(item: localDetail.item)
                        }
                    }

                    Section("章节") {
                        ForEach(Array(downloadedChapterRecords.enumerated()), id: \.element.id) { index, chapter in
                            Button {
                                openLocalReader(chapterIndex: index, pageIndex: 0)
                            } label: {
                                DownloadedChapterRow(chapter: chapter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .picaxInsetGroupedListStyle()
                .background(AppColor.groupedBackground)

                DownloadedComicInfoFooter(
                    record: record,
                    service: service,
                    readTitle: primaryReadTitle,
                    canRead: !record.chapters.isEmpty,
                    read: {
                        openPrimaryReader()
                    },
                    openSearch: { tag in
                        openSearch(DownloadedComicSearchRequest(tag: tag))
                        dismiss()
                    }
                )
            }
            .navigationTitle("已下载")
            .picaxNavigationBarTitleDisplayModeInline()
            .picaxSensitiveImageContent(localCoverURL != nil)
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

    private var localCoverURL: URL? {
        downloadService.localCoverURL(for: record) ?? record.item.coverURL
    }

    private var localDetail: ComicDetailInfo {
        if let detail = record.detail {
            var localDetail = ComicDetailInfo(
                item: detail.item,
                description: detail.description,
                tagGroups: detail.tagGroups,
                chapters: downloadedChapterRecords.map(\.chapter),
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
            tagGroups: fallbackTagGroups,
            chapters: downloadedChapterRecords.map(\.chapter),
            related: [],
            updatedText: nil
        )
    }

    private var downloadedChapterRecords: [DownloadedChapterRecord] {
        record.chapters.sorted { $0.index < $1.index }
    }

    private var localChapterIndexes: [Int] {
        downloadedChapterRecords.map(\.index)
    }

    private var fallbackTagGroups: [ComicTagGroup] {
        guard !record.item.tags.isEmpty else { return [] }
        return [
            ComicTagGroup(
                title: "标签",
                tags: record.item.tags.map {
                    ComicTagReference(title: $0, query: $0, platform: record.item.platform, urlString: nil)
                }
            )
        ]
    }

    private var historyProgress: ReadingProgress? {
        readingHistory.record(for: record.item)?.progress
    }

    private var readableProgress: ReadingProgress? {
        guard let historyProgress,
              historyProgress.status == .reading || historyProgress.status == .finished,
              record.downloadedChapterIndexes.contains(historyProgress.chapterIndex) else {
            return nil
        }
        return historyProgress
    }

    private var primaryReadTitle: String {
        readableProgress == nil ? "从头开始" : "继续阅读"
    }

    private func openPrimaryReader() {
        if let readableProgress {
            let chapterIndex = compactChapterIndex(for: readableProgress.chapterIndex) ?? 0
            openLocalReader(
                chapterIndex: chapterIndex,
                pageIndex: readableProgress.pageIndex
            )
        } else {
            openLocalReader(chapterIndex: 0, pageIndex: 0)
        }
    }

    private func openLocalReader(chapterIndex: Int, pageIndex: Int) {
        let detail = localDetail
        let boundedIndex = min(max(chapterIndex, 0), max(detail.chapters.count - 1, 0))
        openReader(DownloadedComicReaderRequest(
            record: record,
            detail: detail,
            localChapterIndexes: localChapterIndexes,
            initialChapterIndex: boundedIndex,
            initialPageIndex: max(pageIndex, 0),
            ignoresHistoryProgress: true,
            recordsReadingHistory: recordsDownloadedReadingHistory
        ))
        dismiss()
    }

    private func compactChapterIndex(for originalIndex: Int) -> Int? {
        localChapterIndexes.firstIndex(of: originalIndex)
    }
}

struct DownloadedComicReaderRequest: Identifiable, Hashable {
    let id = UUID()
    let record: DownloadRecord
    let detail: ComicDetailInfo
    let localChapterIndexes: [Int]
    let initialChapterIndex: Int
    let initialPageIndex: Int
    let ignoresHistoryProgress: Bool
    let recordsReadingHistory: Bool

    static func == (lhs: DownloadedComicReaderRequest, rhs: DownloadedComicReaderRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct DownloadedComicInfoHeader: View {
    let record: DownloadRecord
    let coverURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: coverURL, accentColor: record.item.accentColor, width: 74, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.item.title)
                    .font(.headline)
                    .lineLimit(3)

                if !record.item.subtitle.isEmpty {
                    Text(record.item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(record.detailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.item.accentColor)

                Text(record.directoryName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DownloadedChapterRow: View {
    let chapter: DownloadedChapterRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.chapter.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(chapter.pageCount) 页 · \(Self.byteFormatter.string(fromByteCount: chapter.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct DownloadedComicInfoFooter: View {
    let record: DownloadRecord
    let service: ComicContentService
    let readTitle: String
    let canRead: Bool
    let read: () -> Void
    let openSearch: (ComicTagReference) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            buttons
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var buttons: some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    detailLink
                        .buttonStyle(.glass)

                    Button(action: read) {
                        buttonLabel(readTitle)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canRead)
                }
            }
        } else {
            HStack(spacing: 12) {
                detailLink
                    .buttonStyle(.bordered)

                Button(action: read) {
                    buttonLabel(readTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRead)
            }
        }
    }

    private var detailLink: some View {
        NavigationLink {
            DownloadedComicDetailPage(record: record, service: service) { tag in
                openSearch(tag)
            }
                .picaxHidesTabBar()
        } label: {
            buttonLabel("查看详情")
        }
        .contextMenu {
            NavigationLink {
                ComicDetailPage(item: record.item, service: service)
                    .picaxHidesTabBar()
            } label: {
                Label("联网详情", systemImage: "network")
            }
        }
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity)
    }
}

struct DownloadedComicSearchRequest: Identifiable, Hashable {
    let id = UUID()
    let tag: ComicTagReference

    static func == (lhs: DownloadedComicSearchRequest, rhs: DownloadedComicSearchRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

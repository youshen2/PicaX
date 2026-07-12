import SwiftUI

struct HomeReadLaterHeader: View {
    let service: ComicContentService

    var body: some View {
        HStack {
            Text("稍后再读")
            Spacer()
            NavigationLink {
                ReadLaterListPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                Image(systemName: "chevron.right.circle")
                    .imageScale(.medium)
            }
            .accessibilityLabel("查看全部稍后再读")
        }
    }
}

struct HomeReadLaterCard: View {
    let records: [ReadLaterRecord]
    let service: ComicContentService

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("暂无稍后再读", systemImage: "bookmark")
                        .font(.headline)
                    Text("长按漫画列表条目，或在漫画详情页加入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(records) { record in
                            NavigationLink {
                                ComicDetailPage(item: record.item, service: service)
                                    .picaxHidesTabBar()
                            } label: {
                                ReadLaterCardItem(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

struct HomeReadLaterEntryLink: View {
    let service: ComicContentService

    var body: some View {
        NavigationLink {
            ReadLaterListPage(service: service)
                .picaxHidesTabBar()
        } label: {
            ToolRow(
                title: "稍后再读",
                subtitle: "查看待阅读漫画",
                systemImage: "bookmark"
            )
        }
    }
}

private struct ReadLaterCardItem: View {
    let record: ReadLaterRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 92, height: 124)

            Text(record.item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 92, alignment: .leading)

            Text(record.addedAtText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
        }
        .frame(width: 92, alignment: .topLeading)
    }
}

struct ReadLaterListPage: View {
    @EnvironmentObject private var readLater: ReadLaterService
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false

    let service: ComicContentService
    @State private var readingListRequest: ReadingListRequest?
    @State private var showsClearConfirmation = false
    @State private var downloadFeedback: ReadLaterDownloadFeedback?

    var body: some View {
        List {
            if readLater.records.isEmpty {
                ContentUnavailableView("暂无稍后再读", systemImage: "bookmark", description: Text("长按漫画列表条目，或在漫画详情页加入"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    LazyLocalForEach(items: readLater.records, initialCount: 48, pageSize: 48) { record in
                        NavigationLink {
                            ComicDetailPage(item: record.item, service: service)
                                .picaxHidesTabBar()
                        } label: {
                            ReadLaterRow(record: record, downloadStatusText: downloadStatusText(for: record.item))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                readLater.remove(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("左滑可删除单条记录。")
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .picaxSensitiveImageContent(!readLater.records.isEmpty)
        .navigationTitle("稍后再读")
        .picaxNavigationDestination(item: $readingListRequest) { request in
            ReadingListReaderPage(request: request, service: service)
        }
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    readAll()
                } label: {
                    Image(systemName: "play.circle")
                }
                .accessibilityLabel("阅读全部稍后再读")
                .disabled(readLater.records.isEmpty)

                Button {
                    downloadAll()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("下载全部稍后再读")
                .disabled(readLater.records.isEmpty)

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("清空稍后再读")
                .disabled(readLater.records.isEmpty)
            }
        }
        .alert("清空稍后再读？", isPresented: $showsClearConfirmation) {
            Button("清空", role: .destructive) {
                readLater.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会清空稍后再读列表，不会影响历史记录、收藏或下载。")
        }
        .alert(item: $downloadFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func readAll() {
        let entries = readLater.records.map { ReadingListEntry.online($0.item) }
        guard !entries.isEmpty else { return }
        readingListRequest = ReadingListRequest(title: "稍后再读", entries: entries)
    }

    private func downloadAll() {
        var summary = ReadLaterDownloadSummary()
        for record in readLater.records {
            let result = downloadService.enqueue(
                item: record.item,
                downloadsComments: downloadsCommentsByDefault && record.item.supportsComments
            )
            summary.record(result)
        }
        downloadFeedback = summary.feedback(total: readLater.records.count)
    }

    private func downloadStatusText(for item: ComicListItem) -> String? {
        if downloadService.task(for: item) != nil {
            return "已在下载队列"
        }
        if let record = downloadService.record(for: item),
           record.totalChapterCount > 0,
           record.chapters.count >= record.totalChapterCount {
            return "已下载完成"
        }
        return nil
    }
}

private struct ReadLaterRow: View {
    let record: ReadLaterRecord
    let downloadStatusText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 64, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(record.item.platformTitle) · 编号 \(record.item.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(record.detailTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let downloadStatusText {
                    Text(downloadStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(record.item.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReadLaterDownloadFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ReadLaterDownloadSummary {
    var queuedBooks = 0
    var alreadyDownloadingBooks = 0
    var alreadyDownloadedBooks = 0
    var emptySelectionBooks = 0

    mutating func record(_ result: DownloadEnqueueResult) {
        switch result {
        case .queued:
            queuedBooks += 1
        case .alreadyDownloading:
            alreadyDownloadingBooks += 1
        case .alreadyDownloaded:
            alreadyDownloadedBooks += 1
        case .emptySelection:
            emptySelectionBooks += 1
        }
    }

    func feedback(total: Int) -> ReadLaterDownloadFeedback {
        let title = queuedBooks > 0 ? "已加入下载队列" : "没有新的下载"
        var parts: [String] = []
        if queuedBooks > 0 {
            parts.append("已加入 \(queuedBooks) 本漫画，章节会在任务开始时解析。")
        }
        if alreadyDownloadingBooks > 0 {
            parts.append("\(alreadyDownloadingBooks) 本已有下载任务。")
        }
        if alreadyDownloadedBooks > 0 {
            parts.append("\(alreadyDownloadedBooks) 本已下载完成。")
        }
        if emptySelectionBooks > 0 {
            parts.append("\(emptySelectionBooks) 本没有可加入的章节。")
        }
        if parts.isEmpty {
            parts.append(total > 0 ? "当前列表没有需要下载的章节。" : "稍后再读列表为空。")
        }
        return ReadLaterDownloadFeedback(title: title, message: parts.joined(separator: "\n"))
    }
}

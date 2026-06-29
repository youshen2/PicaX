import SwiftUI

struct WatchDownloadsPage: View {
    @EnvironmentObject private var downloadService: WatchDownloadService

    var body: some View {
        List {
            if !downloadService.tasks.isEmpty {
                Section("下载队列") {
                    ForEach(downloadService.tasks) { task in
                        WatchDownloadTaskRow(task: task)
                            .swipeActions {
                                if task.status == .paused {
                                    Button {
                                        downloadService.resume(task)
                                    } label: {
                                        Label("继续", systemImage: "play")
                                    }
                                } else {
                                    Button {
                                        downloadService.pause(task)
                                    } label: {
                                        Label("暂停", systemImage: "pause")
                                    }
                                }
                                if task.status == .failed {
                                    Button {
                                        downloadService.retry(task)
                                    } label: {
                                        Label("重试", systemImage: "arrow.clockwise")
                                    }
                                }
                            }
                    }
                }
            }

            Section("已下载") {
                if downloadService.records.isEmpty {
                    WatchEmptyRow(title: "暂无下载", systemImage: "arrow.down.circle")
                } else {
                    ForEach(downloadService.records) { record in
                        NavigationLink {
                            WatchDownloadedComicPage(record: record)
                        } label: {
                            WatchDownloadedComicRow(
                                record: record,
                                coverURL: downloadService.localCoverURL(for: record)
                            )
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets where downloadService.records.indices.contains(index) {
                            downloadService.remove(downloadService.records[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("下载")
    }
}

private struct WatchDownloadTaskRow: View {
    let task: WatchDownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WatchValueRow(
                title: task.detail.item.title,
                subtitle: task.statusText,
                systemImage: "arrow.down.circle"
            )
            ProgressView(value: task.progress)
        }
    }
}

struct WatchDownloadedComicPage: View {
    @EnvironmentObject private var downloadService: WatchDownloadService

    let record: WatchDownloadRecord

    var body: some View {
        List {
            Section("漫画") {
                WatchDownloadedComicRow(
                    record: record,
                    coverURL: downloadService.localCoverURL(for: record)
                )

                if let historyRecord = WatchReadingHistoryStore().record(for: record.item),
                   let chapterRecord = sortedChapters.first(where: { $0.index == historyRecord.progress.chapterIndex }) {
                    NavigationLink {
                        WatchReaderPage(
                            item: record.item,
                            chapter: chapterRecord.chapter,
                            chapterIndex: chapterRecord.index,
                            totalChapters: record.totalChapterCount,
                            initialPageIndex: historyRecord.progress.pageIndex,
                            downloadedRecord: record,
                            chapters: sortedChapters.map(\.chapter),
                            chapterIndexes: sortedChapters.map(\.index)
                        )
                    } label: {
                        Label("继续阅读", systemImage: "book")
                    }
                }
            }

            Section("章节") {
                ForEach(sortedChapters) { chapter in
                    NavigationLink {
                        WatchReaderPage(
                            item: record.item,
                            chapter: chapter.chapter,
                            chapterIndex: chapter.index,
                            totalChapters: record.totalChapterCount,
                            downloadedRecord: record,
                            chapters: sortedChapters.map(\.chapter),
                            chapterIndexes: sortedChapters.map(\.index)
                        )
                    } label: {
                        WatchValueRow(
                            title: chapter.chapter.title,
                            subtitle: "\(chapter.pageCount) 页",
                            systemImage: "book.pages"
                        )
                    }
                }
            }
        }
        .navigationTitle(record.item.title)
    }

    private var sortedChapters: [WatchDownloadedChapterRecord] {
        record.chapters.sorted { $0.index < $1.index }
    }
}

private struct WatchDownloadedComicRow: View {
    let record: WatchDownloadRecord
    let coverURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            WatchCoverThumbnail(url: coverURL ?? record.item.coverURL, width: 38, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(record.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

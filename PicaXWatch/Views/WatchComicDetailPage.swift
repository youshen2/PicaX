import SwiftUI

struct WatchComicDetailPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @EnvironmentObject private var downloadService: WatchDownloadService
    @StateObject private var viewModel = WatchComicDetailViewModel()

    let item: WatchComicItem

    var body: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                Section {
                    ProgressView()
                }
            case .failed(let message):
                Section {
                    WatchValueRow(title: "加载失败", subtitle: message, systemImage: "exclamationmark.triangle", tint: .orange)
                }
            case .loaded(let detail):
                headerSection(detail)
                if !detail.description.isEmpty {
                    Section("简介") {
                        Text(detail.description)
                            .font(.caption)
                    }
                }
                if !detail.metadata.isEmpty || detail.updatedText != nil {
                    Section("信息") {
                        if let updatedText = detail.updatedText {
                            WatchValueRow(title: "更新", subtitle: updatedText, systemImage: "clock")
                        }
                        ForEach(detail.metadata) { row in
                            WatchValueRow(title: row.title, subtitle: row.value, systemImage: "info.circle")
                        }
                    }
                }
                if !detail.chapters.isEmpty {
                    Section("章节") {
                        Button {
                            downloadService.enqueue(detail: detail, chapterIndexes: Array(detail.chapters.indices))
                        } label: {
                            Label("下载全部章节", systemImage: "arrow.down.circle")
                        }

                        ForEach(Array(detail.chapters.enumerated()), id: \.element.id) { index, chapter in
                            NavigationLink {
                                WatchReaderPage(
                                    item: detail.item,
                                    chapter: chapter,
                                    chapterIndex: index,
                                    totalChapters: detail.chapters.count,
                                    chapters: detail.chapters
                                )
                            } label: {
                                WatchValueRow(
                                    title: chapter.title,
                                    subtitle: chapter.subtitle ?? "可阅读章节",
                                    systemImage: "book.pages"
                                )
                            }
                            .swipeActions {
                                Button {
                                    downloadService.enqueue(detail: detail, chapterIndexes: [index])
                                } label: {
                                    Label("下载", systemImage: "arrow.down")
                                }
                            }
                        }
                    }
                }
                ForEach(detail.tagGroups) { group in
                    Section(group.title) {
                        ForEach(group.tags.prefix(12)) { tag in
                            NavigationLink {
                                WatchSearchPage(initialQuery: tag.query, platform: tag.platform)
                            } label: {
                                WatchValueRow(title: tag.title, subtitle: tag.query, systemImage: "tag")
                            }
                        }
                    }
                }
                if !detail.related.isEmpty {
                    Section("相关") {
                        ForEach(detail.related.prefix(6)) { item in
                            NavigationLink {
                                WatchComicDetailPage(item: item)
                            } label: {
                                WatchComicRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
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

    @ViewBuilder
    private func headerSection(_ detail: WatchComicDetailInfo) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink {
                    WatchCoverPreviewPage(item: detail.item)
                } label: {	
                    WatchCoverThumbnail(url: detail.item.coverURL, width: 48, height: 64)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.item.title)
                        .font(.headline)
                        .lineLimit(3)
                    Text(detail.item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(detail.item.platform.title)
                        .font(.caption2)
                        .foregroundStyle(detail.item.platform.watchColor)
                }
            }

            Button {
                if accountSyncStore.isLocalFavorite(detail.item) {
                    accountSyncStore.removeLocalFavorite(detail.item)
                } else {
                    accountSyncStore.addLocalFavorite(detail.item)
                }
            } label: {
                Label(
                    accountSyncStore.isLocalFavorite(detail.item) ? "取消本地收藏" : "加入本地收藏",
                    systemImage: accountSyncStore.isLocalFavorite(detail.item) ? "heart.slash" : "heart"
                )
            }

            if let record = WatchReadingHistoryStore().record(for: detail.item),
               detail.chapters.indices.contains(record.progress.chapterIndex) {
                let chapter = detail.chapters[record.progress.chapterIndex]
                NavigationLink {
                    WatchReaderPage(
                        item: detail.item,
                        chapter: chapter,
                        chapterIndex: record.progress.chapterIndex,
                        totalChapters: detail.chapters.count,
                        initialPageIndex: record.progress.pageIndex,
                        chapters: detail.chapters
                    )
                } label: {
                    Label("继续阅读", systemImage: "book")
                }
            }

            if let firstChapter = detail.chapters.first {
                NavigationLink {
                    WatchReaderPage(
                        item: detail.item,
                        chapter: firstChapter,
                        chapterIndex: 0,
                        totalChapters: detail.chapters.count,
                        initialPageIndex: 0,
                        chapters: detail.chapters
                    )
                } label: {
                    Label("从头开始", systemImage: "play.circle")
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        await viewModel.load(
            item: item,
            account: accountSyncStore.snapshot.account(for: item.platform),
            force: force
        )
    }
}

private struct WatchCoverPreviewPage: View {
    let item: WatchComicItem

    var body: some View {
        ScrollView {
            WatchCoverPreviewImage(url: item.coverURL)
                .padding(.vertical, 8)
        }
        .navigationTitle("封面")
    }
}

private struct WatchCoverPreviewImage: View {
    let url: URL?

    var body: some View {
        Group {
            if url != nil {
                WatchRemoteImageView(url: url, contentMode: .fit, placeholderFont: .largeTitle)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.largeTitle)
            Text("封面不可用")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 32)
    }
}

#Preview {
    NavigationStack {
        WatchComicDetailPage(
            item: WatchComicItem(
                id: "preview",
                platform: .picacg,
                title: "Preview Comic",
                subtitle: "Author",
                coverURLString: nil,
                tags: ["tag"],
                pageCount: 12,
                favoriteDate: nil
            )
        )
    }
    .environmentObject(WatchAccountSyncStore.preview)
    .environmentObject(WatchDownloadService())
}

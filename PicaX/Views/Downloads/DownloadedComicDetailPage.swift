import SwiftUI

struct DownloadedComicDetailPage: View {
    @EnvironmentObject private var downloadService: DownloadService
    let record: DownloadRecord
    let service: ComicContentService
    let openSearch: (ComicTagReference) -> Void
    @State private var commentSheet: DownloadedLocalCommentSheetContext?

    var body: some View {
        let downloadedChaptersByIndex = record.chapters.reduce(into: [Int: DownloadedChapterRecord]()) { result, chapter in
            result[chapter.index] = chapter
        }

        List {
            Section {
                DownloadedComicLocalHeader(record: record, coverURL: localCoverURL)
                    .padding(.vertical, 4)
            }

            if record.item.supportsComments {
                Section {
                    Button {
                        commentSheet = DownloadedLocalCommentSheetContext(item: record.item, comments: localComments)
                    } label: {
                        Label("查看评论", systemImage: "text.bubble")
                    }
                }
            }

            Section("操作") {
                NavigationLink {
                    ComicDetailPage(item: record.item, service: service)
                        .picaxHidesTabBar()
                } label: {
                    Label("打开联网详情页", systemImage: "network")
                }

                if copyItem.copyAction != nil {
                    ComicCopyActionButton(item: copyItem)
                }
            }

            if !localDescription.isEmpty {
                Section("简介") {
                    Text(localDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("信息") {
                LabeledContent("来源", value: record.item.platformTitle)
                if let pageText = record.item.pageText {
                    LabeledContent("页数", value: pageText)
                }
                if let updatedText = localDetail?.updatedText, !updatedText.isEmpty {
                    LabeledContent("更新", value: updatedText)
                }
                LabeledContent("编号", value: record.item.target)
            }

            ForEach(localTagGroups) { group in
                if !group.tags.isEmpty {
                    Section(group.title) {
                        FlowTagLinks(tags: group.tags, color: record.item.accentColor) { tag in
                            openSearch(tag)
                        }
                            .padding(.vertical, 4)
                    }
                }
            }

            Section("章节") {
                ForEach(Array(localChapters.enumerated()), id: \.element.id) { index, chapter in
                    DownloadedLocalChapterRow(
                        chapter: chapter,
                        downloadedChapter: downloadedChaptersByIndex[index],
                        accentColor: record.item.accentColor
                    )
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .picaxSensitiveImageContent(localCoverURL != nil)
        .navigationTitle("本地详情")
        .picaxNavigationBarTitleDisplayModeInline()
        .sheet(item: $commentSheet) { context in
            DownloadedLocalCommentsSheet(item: context.item, comments: context.comments)
                .picaxPresentationDetents([.medium, .large])
        }
    }

    private var localDetail: ComicDetailInfo? {
        record.detail
    }

    private var copyItem: ComicListItem {
        localDetail?.item ?? record.item
    }

    private var localDescription: String {
        localDetail?.description ?? record.item.subtitle
    }

    private var localTagGroups: [ComicTagGroup] {
        if let groups = localDetail?.tagGroups, !groups.isEmpty {
            return groups
        }
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

    private var localComments: [ComicComment] {
        record.comments
    }

    private var localCoverURL: URL? {
        downloadService.localCoverURL(for: record) ?? record.item.coverURL
    }

    private var localChapters: [ComicChapter] {
        if let chapters = localDetail?.chapters, !chapters.isEmpty {
            return chapters
        }
        return record.chapters.map(\.chapter)
    }

}

private struct DownloadedComicLocalHeader: View {
    let record: DownloadRecord
    let coverURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: coverURL, accentColor: record.item.accentColor, width: 102, height: 136)

            VStack(alignment: .leading, spacing: 8) {
                Text(record.item.title.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.title3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !record.item.subtitle.isEmpty {
                    Text(record.item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(record.detailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.item.accentColor)

                Text(record.directoryName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DownloadedLocalChapterRow: View {
    let chapter: ComicChapter
    let downloadedChapter: DownloadedChapterRecord?
    let accentColor: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: downloadedChapter == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(downloadedChapter == nil ? Color.secondary : accentColor)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let downloadedChapter {
            return "\(downloadedChapter.pageCount) 页 · 已下载"
        }
        if let subtitle = chapter.subtitle, !subtitle.isEmpty {
            return "\(subtitle) · 未下载"
        }
        return "未下载"
    }
}

private struct DownloadedLocalCommentSheetContext: Identifiable {
    let item: ComicListItem
    let comments: [ComicComment]

    var id: String {
        "\(item.platform.id)-\(item.id)-local-comments"
    }
}

private struct DownloadedLocalCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ComicListItem
    let comments: [ComicComment]

    var body: some View {
        PicaxNavigationContainer {
            Group {
                if comments.isEmpty {
                    ContentUnavailableView("未下载评论", systemImage: "text.bubble", description: Text("下载漫画时开启评论区选项后会保存在这里。"))
                } else {
                    List {
                        ForEach(comments) { comment in
                            DownloadedLocalCommentRow(comment: comment)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("评论")
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
}

private struct DownloadedLocalCommentRow: View {
    let comment: ComicComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.author)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                if let timeText = comment.timeText {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(comment.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let likesCount = comment.likesCount {
                Text("\(likesCount) 喜欢")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

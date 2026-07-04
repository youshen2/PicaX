import SwiftUI

struct ReaderChapterCommentsView: View {
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

enum ReaderChapterCommentsState {
    case loading
    case loaded([ComicComment])
    case failed(String)
}

struct ReaderCommentsEmptyView: View {
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

struct ReaderCommentRow: View {
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

struct ReaderChapterPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [ComicChapter]
    let selectedIndex: Int
    let listContext: ComicReaderListContext?
    let onSelectReadingListEntry: (ReadingListEntry) -> Void
    let onSelect: (Int) -> Void
    @State private var selectedTab: ReaderChapterSheetTab

    init(
        chapters: [ComicChapter],
        selectedIndex: Int,
        initialTab: ReaderChapterSheetTab = .chapters,
        listContext: ComicReaderListContext?,
        onSelectReadingListEntry: @escaping (ReadingListEntry) -> Void,
        onSelect: @escaping (Int) -> Void
    ) {
        self.chapters = chapters
        self.selectedIndex = selectedIndex
        self.listContext = listContext
        self.onSelectReadingListEntry = onSelectReadingListEntry
        self.onSelect = onSelect
        _selectedTab = State(initialValue: listContext == nil ? .chapters : initialTab)
    }

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

enum ReaderChapterSheetTab: String, CaseIterable, Identifiable {
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

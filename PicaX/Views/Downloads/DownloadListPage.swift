import SwiftUI
import UniformTypeIdentifiers

struct DownloadListPage: View {
    @EnvironmentObject private var downloadService: DownloadService
    let service: ComicContentService

    @State private var showsQueueSheet = false
    @State private var showsFilterSheet = false
    @State private var selectedRecord: DownloadRecord?
    @State private var readerRequest: DownloadedComicReaderRequest?
    @State private var readingListRequest: ReadingListRequest?
    @State private var searchRequest: DownloadedComicSearchRequest?
    @State private var selectedPlatform: ComicPlatform?
    @State private var completionFilter: DownloadCompletionFilter = .all
    @State private var sortOption: DownloadSortOption = .updatedAt
    @State private var sortDirection: DownloadSortDirection = .descending
    @State private var displayRecords: [DownloadRecord] = []
    @State private var exportingRecordID: String?
    @State private var archiveExportDocument = DownloadedComicExportDocument()
    @State private var archiveExportFileName = "漫画.zip"
    @State private var showsArchiveExporter = false
    @State private var pdfExportDocument = DownloadedComicExportDocument()
    @State private var pdfExportFileName = "漫画.pdf"
    @State private var showsPDFExporter = false
    @State private var exportFeedback: DownloadArchiveExportFeedback?

    var body: some View {
        Group {
            downloadList
        }
        .navigationTitle("下载")
        .toolbar {
            ToolbarItemGroup(placement: .picaxTopBarTrailing) {
                Button {
                    showsQueueSheet = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .accessibilityLabel("下载队列")

                Button {
                    showsFilterSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("高级筛选")
            }
        }
        .sheet(isPresented: $showsQueueSheet) {
            DownloadQueueSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsFilterSheet) {
            DownloadAdvancedFilterSheet(
                selectedPlatform: $selectedPlatform,
                completionFilter: $completionFilter,
                sortOption: $sortOption,
                sortDirection: $sortDirection
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fileExporter(
            isPresented: $showsArchiveExporter,
            document: archiveExportDocument,
            contentType: .zip,
            defaultFilename: archiveExportFileName
        ) { result in
            archiveExportDocument.removeTemporaryFile()
            archiveExportDocument = DownloadedComicExportDocument()
            handleExportResult(result)
        }
        .fileExporter(
            isPresented: $showsPDFExporter,
            document: pdfExportDocument,
            contentType: .pdf,
            defaultFilename: pdfExportFileName
        ) { result in
            pdfExportDocument.removeTemporaryFile()
            pdfExportDocument = DownloadedComicExportDocument()
            handleExportResult(result)
        }
        .alert(item: $exportFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
        .sheet(item: $selectedRecord) { record in
            DownloadedComicInfoSheet(record: record, service: service) { request in
                selectedRecord = nil
                readerRequest = request
            } openSearch: { request in
                selectedRecord = nil
                searchRequest = request
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $readerRequest) { request in
            ComicReaderPage(
                detail: request.detail,
                initialChapterIndex: request.initialChapterIndex,
                initialPageIndex: request.initialPageIndex,
                ignoresHistoryProgress: request.ignoresHistoryProgress,
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
        .navigationDestination(item: $readingListRequest) { request in
            ReadingListReaderPage(request: request, service: service)
        }
        .navigationDestination(item: $searchRequest) { request in
            ComicSearchPage(initialQuery: request.tag.query, platform: request.tag.platform, service: service)
        }
        .task {
            refreshDisplayRecords()
        }
        .onChange(of: downloadService.records) { _, _ in
            refreshDisplayRecords()
        }
        .onChange(of: selectedPlatform) { _, _ in
            refreshDisplayRecords()
        }
        .onChange(of: completionFilter) { _, _ in
            refreshDisplayRecords()
        }
        .onChange(of: sortOption) { _, _ in
            refreshDisplayRecords()
        }
        .onChange(of: sortDirection) { _, _ in
            refreshDisplayRecords()
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            exportFeedback = DownloadArchiveExportFeedback(title: "导出失败", message: error.localizedDescription)
        }
    }

    private var downloadList: some View {
        List {
            if displayRecords.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "arrow.down.circle",
                    description: Text(emptyDescription)
                )
                .listRowBackground(Color.clear)
            } else {
                Section("已下载") {
                    if !readableDisplayRecords.isEmpty {
                        Button {
                            Task { @MainActor in
                                readingListRequest = ReadingListRequest(
                                    title: "已下载",
                                    entries: readableDisplayRecords.map { record in
                                        ReadingListEntry.downloaded(
                                            record,
                                            coverURL: downloadService.localCoverURL(for: record) ?? record.item.coverURL
                                        )
                                    }
                                )
                            }
                        } label: {
                            Label("阅读全部", systemImage: "play.circle")
                        }
                    }

                    LazyLocalForEach(items: displayRecords, initialCount: 48, pageSize: 48) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            DownloadRecordRow(
                                record: record,
                                coverURL: downloadService.localCoverURL(for: record) ?? record.item.coverURL
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                prepareArchiveExport(for: record)
                            } label: {
                                Label("以 ZIP 导出", systemImage: "archivebox")
                            }
                            .disabled(exportingRecordID != nil)

                            Button {
                                preparePDFExport(for: record)
                            } label: {
                                Label("以 PDF 导出", systemImage: "doc.richtext")
                            }
                            .disabled(exportingRecordID != nil)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                downloadService.removeRecord(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
    }

    private var readableDisplayRecords: [DownloadRecord] {
        displayRecords.filter { !$0.chapters.isEmpty }
    }

    private func prepareArchiveExport(for record: DownloadRecord) {
        guard exportingRecordID == nil else { return }
        exportingRecordID = record.id

        Task { @MainActor in
            do {
                let export = try await downloadService.makeArchiveExport(for: record)
                archiveExportDocument.removeTemporaryFile()
                archiveExportDocument = DownloadedComicExportDocument(fileURL: export.fileURL, fileName: export.fileName)
                archiveExportFileName = export.fileName
                showsArchiveExporter = true
            } catch {
                exportFeedback = DownloadArchiveExportFeedback(title: "导出失败", message: error.localizedDescription)
            }
            exportingRecordID = nil
        }
    }

    private func preparePDFExport(for record: DownloadRecord) {
        guard exportingRecordID == nil else { return }
        exportingRecordID = record.id

        Task { @MainActor in
            do {
                let export = try await downloadService.makePDFExport(for: record)
                pdfExportDocument.removeTemporaryFile()
                pdfExportDocument = DownloadedComicExportDocument(fileURL: export.fileURL, fileName: export.fileName)
                pdfExportFileName = export.fileName
                showsPDFExporter = true
            } catch {
                exportFeedback = DownloadArchiveExportFeedback(title: "导出失败", message: error.localizedDescription)
            }
            exportingRecordID = nil
        }
    }

    private func refreshDisplayRecords() {
        var records = downloadService.records

        if let selectedPlatform {
            records = records.filter { $0.item.platform == selectedPlatform }
        }

        switch completionFilter {
        case .all:
            break
        case .complete:
            records = records.filter { $0.chapters.count >= max($0.totalChapterCount, 1) }
        case .partial:
            records = records.filter { $0.chapters.count < max($0.totalChapterCount, 1) }
        }

        records.sort { lhs, rhs in
            switch sortDirection {
            case .ascending:
                return isOrdered(lhs, before: rhs)
            case .descending:
                return isOrdered(rhs, before: lhs)
            }
        }

        if displayRecords != records {
            displayRecords = records
        }
    }

    private func isOrdered(_ lhs: DownloadRecord, before rhs: DownloadRecord) -> Bool {
        switch sortOption {
        case .updatedAt:
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
            }
            return lhs.updatedAt < rhs.updatedAt
        case .title:
            let result = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if result == .orderedSame {
                return lhs.updatedAt < rhs.updatedAt
            }
            return result == .orderedAscending
        case .size:
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.totalBytes < rhs.totalBytes
        case .chapters:
            if lhs.chapters.count == rhs.chapters.count {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.chapters.count < rhs.chapters.count
        }
    }

    private var hasActiveFilters: Bool {
        selectedPlatform != nil || completionFilter != .all
    }

    private var emptyTitle: String {
        hasActiveFilters ? "没有匹配的下载" : "暂无已下载"
    }

    private var emptyDescription: String {
        if hasActiveFilters {
            return "调整右上角高级筛选后再试。"
        }
        if downloadService.tasks.isEmpty {
            return "在漫画详情页选择章节后会加入下载队列。"
        }
        return "右上角下载队列中有 \(downloadService.tasks.count) 个任务。"
    }
}

private struct DownloadedComicExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .pdf] }
    static var writableContentTypes: [UTType] { [.zip, .pdf] }

    var fileURL: URL?
    var fileName: String?

    init(fileURL: URL? = nil, fileName: String? = nil) {
        self.fileURL = fileURL
        self.fileName = fileName
    }

    init(configuration: ReadConfiguration) throws {
        fileURL = nil
        fileName = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let fileURL else {
            throw DownloadedComicExportDocumentError.missingFile
        }
        let wrapper = try FileWrapper(url: fileURL, options: .immediate)
        wrapper.preferredFilename = fileName ?? fileURL.lastPathComponent
        return wrapper
    }

    func removeTemporaryFile() {
        guard let fileURL else { return }
        let directoryURL = fileURL.deletingLastPathComponent()
        if directoryURL.lastPathComponent.hasPrefix("PicaX-") {
            try? FileManager.default.removeItem(at: directoryURL)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

private enum DownloadedComicExportDocumentError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        "导出文件尚未生成。"
    }
}

private struct DownloadArchiveExportFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct DownloadQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadService: DownloadService

    var body: some View {
        NavigationStack {
            List {
                if downloadService.tasks.isEmpty {
                    ContentUnavailableView("暂无下载任务", systemImage: "tray", description: Text("新任务会从漫画详情页加入"))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        LazyLocalForEach(items: downloadService.tasks, initialCount: 32, pageSize: 32) { task in
                            DownloadTaskRow(task: task)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if task.status == .paused {
                                        Button {
                                            downloadService.resume(task)
                                        } label: {
                                            Label("继续", systemImage: "play.fill")
                                        }
                                        .tint(.green)
                                    } else if task.status == .queued || task.status == .downloading {
                                        Button {
                                            downloadService.pause(task)
                                        } label: {
                                            Label("暂停", systemImage: "pause.fill")
                                        }
                                        .tint(.orange)
                                    }

                                    Button {
                                        downloadService.prioritize(task)
                                    } label: {
                                        Label("优先", systemImage: "arrow.up.to.line")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        downloadService.removeTask(task)
                                    } label: {
                                        Label("移除", systemImage: "trash")
                                    }

                                    if task.status == .failed {
                                        Button {
                                            downloadService.retry(task)
                                        } label: {
                                            Label("重试", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    } footer: {
                        Text("右滑可以暂停、继续或优先下载；左滑可以移除任务，失败任务可以重试。")
                    }
                }
            }
            .picaxInsetGroupedListStyle()
            .background(AppColor.groupedBackground)
            .navigationTitle("下载队列")
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

private struct DownloadAdvancedFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPlatform: ComicPlatform?
    @Binding var completionFilter: DownloadCompletionFilter
    @Binding var sortOption: DownloadSortOption
    @Binding var sortDirection: DownloadSortDirection

    var body: some View {
        NavigationStack {
            List {
                Section("平台") {
                    Picker("平台", selection: $selectedPlatform) {
                        Text("全部").tag(nil as ComicPlatform?)
                        ForEach(ComicPlatform.allCases) { platform in
                            Text(platform.title)
                                .tag(platform as ComicPlatform?)
                        }
                    }
                }

                Section("状态") {
                    Picker("完成状态", selection: $completionFilter) {
                        ForEach(DownloadCompletionFilter.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("排序") {
                    Picker("排序方式", selection: $sortOption) {
                        ForEach(DownloadSortOption.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }

                    Picker("排序方向", selection: $sortDirection) {
                        ForEach(DownloadSortDirection.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .picaxInsetGroupedListStyle()
            .background(AppColor.groupedBackground)
            .navigationTitle("高级筛选")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .picaxTopBarLeading) {
                    Button("重置") {
                        reset()
                    }
                }

                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("完成")
                }
            }
        }
    }

    private func reset() {
        selectedPlatform = nil
        completionFilter = .all
        sortOption = .updatedAt
        sortDirection = .descending
    }
}

private struct DownloadTaskRow: View {
    let task: ComicDownloadTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: task.item.coverURL, accentColor: task.item.accentColor)
                .frame(width: 58, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.item.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(task.statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)

                ProgressView(value: task.progress)
                    .tint(task.item.accentColor)

                Text(task.chapterCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch task.status {
        case .failed:
            .red
        case .paused:
            .orange
        case .queued, .downloading:
            .secondary
        }
    }
}

private struct DownloadRecordRow: View {
    let record: DownloadRecord
    let coverURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: coverURL, accentColor: record.item.accentColor)
                .frame(width: 58, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(record.detailText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(record.item.accentColor)
                    .lineLimit(1)

                Text("\(record.item.platformTitle) · \(record.updatedAtText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private enum DownloadCompletionFilter: String, CaseIterable, Identifiable {
    case all
    case complete
    case partial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .complete:
            "完整"
        case .partial:
            "部分"
        }
    }
}

private enum DownloadSortOption: String, CaseIterable, Identifiable {
    case updatedAt
    case title
    case size
    case chapters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updatedAt:
            "最近更新"
        case .title:
            "标题"
        case .size:
            "大小"
        case .chapters:
            "章节数"
        }
    }
}

private enum DownloadSortDirection: String, CaseIterable, Identifiable {
    case descending
    case ascending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .descending:
            "降序"
        case .ascending:
            "升序"
        }
    }
}

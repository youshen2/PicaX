import Combine
import CoreGraphics
import Foundation
import ImageIO
import zlib

struct DownloadedChapterRecord: Identifiable, Equatable, Codable {
    let index: Int
    let chapter: ComicChapter
    var pageCount: Int
    var bytes: Int64
    var comments: [ComicComment]
    var downloadedAt: Date

    var id: Int { index }

    init(
        index: Int,
        chapter: ComicChapter,
        pageCount: Int,
        bytes: Int64,
        comments: [ComicComment] = [],
        downloadedAt: Date
    ) {
        self.index = index
        self.chapter = chapter
        self.pageCount = pageCount
        self.bytes = bytes
        self.comments = comments
        self.downloadedAt = downloadedAt
    }

    enum CodingKeys: String, CodingKey {
        case index
        case chapter
        case pageCount
        case bytes
        case comments
        case downloadedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        chapter = try container.decode(ComicChapter.self, forKey: .chapter)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        comments = try container.decodeIfPresent([ComicComment].self, forKey: .comments) ?? []
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
    }
}

struct DownloadRecord: Identifiable, Equatable, Codable {
    let item: ComicListItem
    var chapters: [DownloadedChapterRecord]
    var totalChapterCount: Int
    var totalBytes: Int64
    var directoryName: String
    var coverFileName: String?
    var detail: ComicDetailInfo?
    var comments: [ComicComment]
    var updatedAt: Date

    var id: String {
        "\(item.platform.id)-\(item.id)"
    }

    var downloadedChapterIndexes: Set<Int> {
        Set(chapters.map(\.index))
    }

    var statusText: String {
        if totalChapterCount <= 1 {
            let pages = chapters.first?.pageCount ?? item.pageCount ?? 0
            return pages > 0 ? "已下载 \(pages) 页" : "已下载"
        }
        return "已下载 \(chapters.count)/\(totalChapterCount) 章"
    }

    var detailText: String {
        let size = Self.byteFormatter.string(fromByteCount: totalBytes)
        return totalBytes > 0 ? "\(statusText) · \(size)" : statusText
    }

    var updatedAtText: String {
        Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

struct ComicDownloadTask: Identifiable, Equatable, Codable {
    let id: String
    let item: ComicListItem
    var chapters: [ComicChapter]
    var chapterIndexes: [Int]
    var detail: ComicDetailInfo?
    var downloadsComments: Bool
    var status: ComicDownloadTaskStatus
    var createdAt: Date
    var startedAt: Date?
    var completedChapterIndexes: Set<Int>
    var currentChapterIndex: Int?
    var currentPageIndex: Int
    var currentPageCount: Int
    var downloadedBytes: Int64
    var errorMessage: String?

    init(item: ComicListItem, chapters: [ComicChapter], chapterIndexes: [Int], detail: ComicDetailInfo?, downloadsComments: Bool) {
        self.id = UUID().uuidString
        self.item = item
        self.chapters = chapters
        self.chapterIndexes = chapterIndexes.sorted()
        self.detail = detail
        self.downloadsComments = downloadsComments
        self.status = .queued
        self.createdAt = Date()
        self.startedAt = nil
        self.completedChapterIndexes = []
        self.currentChapterIndex = nil
        self.currentPageIndex = 0
        self.currentPageCount = 0
        self.downloadedBytes = 0
        self.errorMessage = nil
    }

    init(item: ComicListItem, downloadsComments: Bool) {
        self.init(
            item: item,
            chapters: [],
            chapterIndexes: [],
            detail: nil,
            downloadsComments: downloadsComments
        )
    }

    var needsChapterResolution: Bool {
        chapters.isEmpty && chapterIndexes.isEmpty
    }

    var progress: Double {
        guard !needsChapterResolution else { return 0 }
        let totalChapters = max(chapterIndexes.count, 1)
        let completed = Double(completedChapterIndexes.count)
        guard status == .downloading, currentPageCount > 0 else {
            return min(completed / Double(totalChapters), 1)
        }
        let pageProgress = min(Double(currentPageIndex) / Double(currentPageCount), 1)
        return min((completed + pageProgress) / Double(totalChapters), 1)
    }

    var statusText: String {
        switch status {
        case .queued:
            if needsChapterResolution {
                return "等待解析章节"
            }
            return "等待下载"
        case .downloading:
            if needsChapterResolution {
                return "正在准备章节"
            }
            if let currentChapterIndex,
               chapters.indices.contains(currentChapterIndex) {
                let chapter = chapters[currentChapterIndex]
                if currentPageCount > 0 {
                    return "\(chapter.title) · \(min(currentPageIndex, currentPageCount))/\(currentPageCount) 页"
                }
                return "正在准备 \(chapter.title)"
            }
            return "正在下载"
        case .paused:
            return "已暂停"
        case .failed:
            return errorMessage ?? "下载出错"
        }
    }

    var chapterCountText: String {
        guard !needsChapterResolution else {
            return "等待章节"
        }
        return "\(completedChapterIndexes.count)/\(chapterIndexes.count) 章"
    }
}

enum ComicDownloadTaskStatus: String, Codable {
    case queued
    case downloading
    case paused
    case failed

    var canRun: Bool {
        self == .queued
    }
}

enum DownloadEnqueueResult: Equatable {
    case queued(Int)
    case alreadyDownloading
    case alreadyDownloaded
    case emptySelection

    var message: String {
        switch self {
        case .queued(let count):
            guard count > 0 else { return "已加入下载队列" }
            return "已加入下载队列：\(count) 章"
        case .alreadyDownloading:
            return "下载中"
        case .alreadyDownloaded:
            return "已下载"
        case .emptySelection:
            return "请选择要下载的章节"
        }
    }
}

struct DownloadStorageUsage: Equatable {
    let filesBytes: Int64
    let recordsBytes: Int
    let tasksBytes: Int

    var metadataBytes: Int {
        recordsBytes + tasksBytes
    }
}

struct DownloadArchiveExport {
    let fileURL: URL
    let fileName: String
}

struct DownloadPDFExport {
    let fileURL: URL
    let fileName: String
}

enum DownloadArchiveExportError: LocalizedError {
    case noImages
    case invalidArchivePath
    case entryTooLarge
    case tooManyEntries

    var errorDescription: String? {
        switch self {
        case .noImages:
            "没有可导出的漫画图片。"
        case .invalidArchivePath:
            "ZIP 内部文件路径无效。"
        case .entryTooLarge:
            "漫画文件过大，无法导出为 ZIP。"
        case .tooManyEntries:
            "漫画图片数量过多，无法导出为 ZIP。"
        }
    }
}

enum DownloadPDFExportError: LocalizedError {
    case noImages
    case invalidOutput
    case unreadableImage(String)

    var errorDescription: String? {
        switch self {
        case .noImages:
            "没有可导出的漫画图片。"
        case .invalidOutput:
            "无法创建 PDF 文件。"
        case .unreadableImage(let name):
            "无法读取图片：\(name)"
        }
    }
}

private enum DownloadTaskControlError: Error {
    case stopped
}

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var tasks: [ComicDownloadTask] = []

    private let defaults: UserDefaults
    private let contentService: ComicContentService
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var workerTask: Task<Void, Never>?
    private var accountProvider: ((ComicPlatform) -> PlatformAccount?)?
    #if os(iOS)
    private lazy var progressPresentationService = DownloadProgressPresentationService(defaults: defaults)
    #endif

    init(
        defaults: UserDefaults = .standard,
        contentService: ComicContentService? = nil,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.contentService = contentService ?? ComicContentService()
        self.fileManager = fileManager
        if defaults.object(forKey: DownloadSettingsKey.homeLimit) == nil {
            defaults.set(8, forKey: DownloadSettingsKey.homeLimit)
        }
        if defaults.object(forKey: DownloadSettingsKey.imageRetryCount) == nil {
            defaults.set(2, forKey: DownloadSettingsKey.imageRetryCount)
        }
        if defaults.object(forKey: DownloadSettingsKey.concurrentDownloadCount) == nil {
            defaults.set(1, forKey: DownloadSettingsKey.concurrentDownloadCount)
        }
        if defaults.object(forKey: DownloadSettingsKey.speedLimitEnabled) == nil {
            defaults.set(false, forKey: DownloadSettingsKey.speedLimitEnabled)
        }
        if defaults.object(forKey: DownloadSettingsKey.speedLimitKBPerSecond) == nil {
            defaults.set(1024, forKey: DownloadSettingsKey.speedLimitKBPerSecond)
        }
        if defaults.object(forKey: DownloadSettingsKey.readsImagesFromCache) == nil {
            defaults.set(true, forKey: DownloadSettingsKey.readsImagesFromCache)
        }
        if defaults.object(forKey: DownloadSettingsKey.archiveFileNameTemplate) == nil {
            defaults.set(DownloadSettingsKey.defaultArchiveFileNameTemplate, forKey: DownloadSettingsKey.archiveFileNameTemplate)
        }
        if defaults.object(forKey: DownloadSettingsKey.showsProgressNotifications) == nil {
            defaults.set(true, forKey: DownloadSettingsKey.showsProgressNotifications)
        }
        if defaults.object(forKey: DownloadSettingsKey.showsProgressLiveActivity) == nil {
            defaults.set(true, forKey: DownloadSettingsKey.showsProgressLiveActivity)
        }
        if defaults.object(forKey: DownloadSettingsKey.progressNotificationUpdateIntervalSeconds) == nil {
            defaults.set(
                DownloadSettingsKey.defaultProgressNotificationUpdateIntervalSeconds,
                forKey: DownloadSettingsKey.progressNotificationUpdateIntervalSeconds
            )
        }
        records = PicaXSQLiteStore.loadDownloadRecords()
        tasks = Self.loadTasks(defaults: defaults, decoder: decoder)
    }

    deinit {
        workerTask?.cancel()
    }

    func configure(accountProvider: @escaping (ComicPlatform) -> PlatformAccount?) {
        self.accountProvider = accountProvider
        startIfNeeded()
        refreshProgressPresentation()
    }

    func latest(limit: Int) -> [DownloadRecord] {
        Array(records.prefix(max(limit, 0)))
    }

    func record(for item: ComicListItem) -> DownloadRecord? {
        records.first { $0.id == downloadID(for: item) }
    }

    func task(for item: ComicListItem) -> ComicDownloadTask? {
        tasks.first { $0.item.platform == item.platform && $0.item.id == item.id }
    }

    func downloadedChapterIndexes(for item: ComicListItem) -> Set<Int> {
        record(for: item)?.downloadedChapterIndexes ?? []
    }

    func localCoverURL(for record: DownloadRecord) -> URL? {
        guard let coverFileName = record.coverFileName,
              let directoryURL = comicDirectoryURLIfAvailable(for: record.item) else {
            return nil
        }
        let url = directoryURL.appendingPathComponent(coverFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func localChapterImages(for record: DownloadRecord, chapterIndex: Int) async -> [ComicChapterImage] {
        let chapters = record.detail?.chapters ?? record.chapters.map(\.chapter)
        guard chapters.indices.contains(chapterIndex) else {
            return []
        }

        return await Self.localChapterImages(
            item: record.item,
            chapter: chapters[chapterIndex],
            chapterIndex: chapterIndex
        )
    }

    func localChapterComments(for record: DownloadRecord, chapterIndex: Int) async -> [ComicComment] {
        if let chapter = record.chapters.first(where: { $0.index == chapterIndex }),
           !chapter.comments.isEmpty {
            return chapter.comments
        }
        return record.comments
    }

    func enqueue(detail: ComicDetailInfo, chapterIndexes: [Int], downloadsComments: Bool = false) -> DownloadEnqueueResult {
        guard task(for: detail.item) == nil else {
            return .alreadyDownloading
        }

        let downloaded = downloadedChapterIndexes(for: detail.item)
        let validIndexes = chapterIndexes
            .filter { detail.chapters.indices.contains($0) }
            .filter { !downloaded.contains($0) }
        let uniqueIndexes = Array(Set(validIndexes)).sorted()
        guard !uniqueIndexes.isEmpty else {
            return downloaded.count >= detail.chapters.count ? .alreadyDownloaded : .emptySelection
        }

        tasks.append(ComicDownloadTask(
            item: detail.item,
            chapters: detail.chapters,
            chapterIndexes: uniqueIndexes,
            detail: detail,
            downloadsComments: downloadsComments
        ))
        saveTasks()
        startIfNeeded()
        return .queued(uniqueIndexes.count)
    }

    func enqueue(item: ComicListItem, downloadsComments: Bool = false) -> DownloadEnqueueResult {
        guard task(for: item) == nil else {
            return .alreadyDownloading
        }

        if let record = record(for: item),
           record.totalChapterCount > 0,
           record.chapters.count >= record.totalChapterCount {
            return .alreadyDownloaded
        }

        tasks.append(ComicDownloadTask(
            item: item,
            downloadsComments: downloadsComments
        ))
        saveTasks()
        startIfNeeded()
        return .queued(0)
    }

    func retry(_ task: ComicDownloadTask) {
        updateTask(task.id) { value in
            value.status = .queued
            value.errorMessage = nil
            value.currentChapterIndex = nil
            value.currentPageIndex = 0
            value.currentPageCount = 0
        }
        saveTasks()
        startIfNeeded()
    }

    func pause(_ task: ComicDownloadTask) {
        updateTask(task.id) { value in
            guard value.status == .queued || value.status == .downloading else { return }
            value.status = .paused
            value.errorMessage = nil
        }
        saveTasks()
    }

    func resume(_ task: ComicDownloadTask) {
        updateTask(task.id) { value in
            guard value.status == .paused else { return }
            value.status = .queued
            value.errorMessage = nil
            value.currentChapterIndex = nil
            value.currentPageIndex = 0
            value.currentPageCount = 0
        }
        saveTasks()
        startIfNeeded()
    }

    func prioritize(_ task: ComicDownloadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var value = tasks.remove(at: index)
        if value.status == .failed {
            value.status = .queued
            value.errorMessage = nil
        }
        tasks.insert(value, at: 0)
        saveTasks()
        startIfNeeded()
    }

    func removeTask(_ task: ComicDownloadTask) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    func clearTasks() {
        guard !tasks.isEmpty else { return }
        tasks.removeAll()
        saveTasks()
    }

    func removeRecord(_ record: DownloadRecord) {
        let directoryURL = comicDirectoryURLIfAvailable(for: record.item)
        records.removeAll { $0.id == record.id }
        PicaXSQLiteStore.deleteDownloadRecord(id: record.id)
        Self.removeDownloadDirectories([directoryURL].compactMap { $0 })
    }

    func clearFinishedDownloads() {
        let directoryURLs = records.compactMap { comicDirectoryURLIfAvailable(for: $0.item) }
        records.removeAll()
        PicaXSQLiteStore.clearDownloadRecords()
        Self.removeDownloadDirectories(directoryURLs)
    }

    func reloadFromDefaults() {
        records = PicaXSQLiteStore.loadDownloadRecords()
        tasks = Self.loadTasks(defaults: defaults, decoder: decoder)
        startIfNeeded()
        refreshProgressPresentation()
    }

    func refreshProgressPresentation() {
        #if os(iOS)
        progressPresentationService.update(tasks: tasks)
        #endif
    }

    func storageUsage() async -> DownloadStorageUsage {
        let filesBytes = await Self.downloadsDirectorySize()
        return DownloadStorageUsage(
            filesBytes: filesBytes,
            recordsBytes: PicaXSQLiteStore.bytes(for: .downloadRecords),
            tasksBytes: defaults.data(forKey: DownloadSettingsKey.tasks)?.count ?? 0
        )
    }

    func makeArchiveExport(for record: DownloadRecord) async throws -> DownloadArchiveExport {
        let storedFileNameTemplate = defaults.string(forKey: DownloadSettingsKey.archiveFileNameTemplate)
            ?? DownloadSettingsKey.defaultArchiveFileNameTemplate
        let fileNameTemplate = storedFileNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? DownloadSettingsKey.defaultArchiveFileNameTemplate
            : storedFileNameTemplate
        return try await Self.makeArchiveExport(for: record, fileNameTemplate: fileNameTemplate)
    }

    func makePDFExport(for record: DownloadRecord) async throws -> DownloadPDFExport {
        let storedFileNameTemplate = defaults.string(forKey: DownloadSettingsKey.archiveFileNameTemplate)
            ?? DownloadSettingsKey.defaultArchiveFileNameTemplate
        let fileNameTemplate = storedFileNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? DownloadSettingsKey.defaultArchiveFileNameTemplate
            : storedFileNameTemplate
        return try await Self.makePDFExport(for: record, fileNameTemplate: fileNameTemplate)
    }

    private func startIfNeeded() {
        guard workerTask == nil else { return }
        guard tasks.contains(where: { $0.status.canRun }) else { return }
        workerTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        defer {
            workerTask = nil
            if tasks.contains(where: { $0.status.canRun }) {
                startIfNeeded()
            }
        }

        while !Task.isCancelled {
            let taskIDs = Array(tasks
                .filter { $0.status.canRun }
                .prefix(maxConcurrentDownloads)
                .map(\.id))
            guard !taskIDs.isEmpty else { return }

            await withTaskGroup(of: Void.self) { group in
                for taskID in taskIDs {
                    group.addTask { @MainActor [weak self] in
                        await self?.runTask(id: taskID)
                    }
                }
            }
        }
    }

    private var maxConcurrentDownloads: Int {
        let storedValue = defaults.object(forKey: DownloadSettingsKey.concurrentDownloadCount) == nil
            ? 1
            : defaults.integer(forKey: DownloadSettingsKey.concurrentDownloadCount)
        return min(max(storedValue, 1), 6)
    }

    private func runTask(id: String) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        guard task.status.canRun else { return }
        updateTask(id) { value in
            value.status = .downloading
            value.startedAt = Date()
            value.errorMessage = nil
        }
        saveTasks()

        do {
            let account = accountProvider?(task.item.platform)
            guard let preparedTask = try await prepareTaskForDownload(id: id, account: account) else { return }
            let metadata = await loadMetadata(for: preparedTask, account: account)
            for chapterIndex in preparedTask.chapterIndexes {
                try Task.checkCancellation()
                try checkTaskCanContinue(id)
                guard preparedTask.chapters.indices.contains(chapterIndex) else { continue }
                if tasks.first(where: { $0.id == id })?.completedChapterIndexes.contains(chapterIndex) == true {
                    continue
                }

                let chapter = preparedTask.chapters[chapterIndex]
                updateTask(id) { value in
                    value.currentChapterIndex = chapterIndex
                    value.currentPageIndex = 0
                    value.currentPageCount = 0
                }
                saveTasks()

                let images = try await contentService.loadChapterImages(
                    item: preparedTask.item,
                    chapter: chapter,
                    account: account
                )
                let chapterComments = preparedTask.downloadsComments
                    ? await loadChapterCommentsIfPossible(item: preparedTask.item, chapter: chapter, account: account)
                    : []
                let downloadedChapter = try await downloadChapter(
                    item: preparedTask.item,
                    chapter: chapter,
                    chapterIndex: chapterIndex,
                    images: images,
                    comments: chapterComments,
                    taskID: id
                )
                appendDownloadedChapter(
                    item: preparedTask.item,
                    totalChapterCount: preparedTask.chapters.count,
                    chapter: downloadedChapter,
                    detail: metadata.detail,
                    comments: metadata.comments,
                    coverFileName: metadata.coverFileName
                )
                updateTask(id) { value in
                    value.completedChapterIndexes.insert(chapterIndex)
                    value.currentPageIndex = images.count
                    value.currentPageCount = images.count
                }
                saveTasks()
            }

            tasks.removeAll { $0.id == id }
            saveTasks()
        } catch is CancellationError {
            updateTask(id) { value in
                value.status = .queued
                value.errorMessage = nil
            }
            saveTasks()
        } catch DownloadTaskControlError.stopped {
            saveTasks()
        } catch {
            updateTask(id) { value in
                value.status = .failed
                value.errorMessage = error.localizedDescription
            }
            saveTasks()
        }
    }

    private func prepareTaskForDownload(id: String, account: PlatformAccount?) async throws -> ComicDownloadTask? {
        guard let task = tasks.first(where: { $0.id == id }) else { return nil }
        guard task.needsChapterResolution else { return task }

        try checkTaskCanContinue(id)
        let detail = try await contentService.loadDetail(item: task.item, account: account)
        try checkTaskCanContinue(id)

        let downloaded = downloadedChapterIndexes(for: detail.item)
        let indexes = Array(detail.chapters.indices.filter { !downloaded.contains($0) })
        guard !indexes.isEmpty else {
            tasks.removeAll { $0.id == id }
            saveTasks()
            return nil
        }

        updateTask(id) { value in
            value.chapters = detail.chapters
            value.chapterIndexes = indexes
            value.detail = detail
        }
        saveTasks()
        return tasks.first { $0.id == id }
    }

    private func loadMetadata(
        for task: ComicDownloadTask,
        account: PlatformAccount?
    ) async -> (detail: ComicDetailInfo?, comments: [ComicComment], coverFileName: String?) {
        let detail: ComicDetailInfo?
        if let storedDetail = task.detail {
            detail = storedDetail
        } else {
            detail = try? await contentService.loadDetail(item: task.item, account: account)
        }
        let coverFileName = await downloadCoverIfNeeded(item: task.item)
        let comments = task.downloadsComments ? await loadCommentsIfPossible(item: task.item, account: account) : []
        return (detail, comments, coverFileName)
    }

    private func loadCommentsIfPossible(item: ComicListItem, account: PlatformAccount?) async -> [ComicComment] {
        guard item.supportsComments else { return [] }
        return (try? await contentService.loadComments(item: item, account: account)) ?? []
    }

    private func loadChapterCommentsIfPossible(
        item: ComicListItem,
        chapter: ComicChapter,
        account: PlatformAccount?
    ) async -> [ComicComment] {
        guard item.supportsComments, contentService.supportsChapterComments(platform: item.platform) else {
            return []
        }
        var comments: [ComicComment] = []
        var seenIDs = Set<String>()
        let supportsPagination = item.platform == .picacg || item.platform == .jmComic
        let maxPages = supportsPagination ? 20 : 1

        for page in 1...maxPages {
            guard let pageComments = try? await contentService.loadChapterComments(
                item: item,
                chapter: chapter,
                account: account,
                page: page
            ), !pageComments.isEmpty else {
                break
            }

            let newComments = pageComments.filter { seenIDs.insert($0.id).inserted }
            comments.append(contentsOf: newComments)
            guard supportsPagination, !newComments.isEmpty else { break }
        }

        return comments
    }

    private func downloadCoverIfNeeded(item: ComicListItem) async -> String? {
        guard !item.coverURLString.isEmpty,
              let directoryURL = try? comicDirectory(for: item) else {
            return nil
        }

        let fileName = "cover.jpg"
        let url = directoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            return fileName
        }

        guard let data = try? await loadImageDataWithRetry(urlString: item.coverURLString) else {
            return nil
        }

        do {
            try await Self.write(data, to: url)
            return fileName
        } catch {
            return nil
        }
    }

    private func downloadChapter(
        item: ComicListItem,
        chapter: ComicChapter,
        chapterIndex: Int,
        images: [ComicChapterImage],
        comments: [ComicComment],
        taskID: String
    ) async throws -> DownloadedChapterRecord {
        let directoryURL = try chapterDirectory(for: item, chapter: chapter, index: chapterIndex)
        var totalBytes: Int64 = 0

        for (pageIndex, image) in images.enumerated() {
            try Task.checkCancellation()
            try checkTaskCanContinue(taskID)
            let startedAt = Date()
            let data = try await loadImageDataWithRetry(urlString: image.urlString)
            try checkTaskCanContinue(taskID)
            let pageURL = directoryURL.appendingPathComponent(fileName(for: image.urlString, pageIndex: pageIndex))
            try await Self.write(data, to: pageURL)
            totalBytes += Int64(data.count)
            updateTask(taskID) { value in
                value.currentPageIndex = pageIndex + 1
                value.currentPageCount = images.count
                value.downloadedBytes += Int64(data.count)
            }
            saveTasks()
            try await throttleIfNeeded(downloadedBytes: data.count, startedAt: startedAt)
        }

        return DownloadedChapterRecord(
            index: chapterIndex,
            chapter: chapter,
            pageCount: images.count,
            bytes: totalBytes,
            comments: comments,
            downloadedAt: Date()
        )
    }

    private func checkTaskCanContinue(_ id: String) throws {
        guard tasks.first(where: { $0.id == id })?.status == .downloading else {
            throw DownloadTaskControlError.stopped
        }
    }

    private func loadImageDataWithRetry(urlString: String) async throws -> Data {
        let storedRetryCount = defaults.object(forKey: DownloadSettingsKey.imageRetryCount) == nil
            ? 2
            : defaults.integer(forKey: DownloadSettingsKey.imageRetryCount)
        let attempts = min(max(storedRetryCount, 0), 8) + 1
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                return try await contentService.loadImageData(
                    urlString: urlString,
                    storesInCache: readsImagesFromCache
                )
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        throw lastError ?? ComicContentError.invalidResponse("图片下载失败。")
    }

    private var readsImagesFromCache: Bool {
        defaults.object(forKey: DownloadSettingsKey.readsImagesFromCache) == nil
            ? true
            : defaults.bool(forKey: DownloadSettingsKey.readsImagesFromCache)
    }

    private func throttleIfNeeded(downloadedBytes: Int, startedAt: Date) async throws {
        guard defaults.bool(forKey: DownloadSettingsKey.speedLimitEnabled) else { return }
        let storedLimit = defaults.object(forKey: DownloadSettingsKey.speedLimitKBPerSecond) == nil
            ? 1024
            : defaults.integer(forKey: DownloadSettingsKey.speedLimitKBPerSecond)
        let limit = min(max(storedLimit, 64), 10240)
        let expectedDuration = Double(downloadedBytes) / Double(limit * 1024)
        let elapsed = Date().timeIntervalSince(startedAt)
        guard expectedDuration > elapsed else { return }
        try await Task.sleep(nanoseconds: UInt64((expectedDuration - elapsed) * 1_000_000_000))
    }

    private func appendDownloadedChapter(
        item: ComicListItem,
        totalChapterCount: Int,
        chapter: DownloadedChapterRecord,
        detail: ComicDetailInfo?,
        comments: [ComicComment],
        coverFileName: String?
    ) {
        let id = downloadID(for: item)
        var record = records.first { $0.id == id } ?? DownloadRecord(
            item: item,
            chapters: [],
            totalChapterCount: totalChapterCount,
            totalBytes: 0,
            directoryName: directoryName(for: item),
            coverFileName: nil,
            detail: nil,
            comments: [],
            updatedAt: Date()
        )
        record.totalChapterCount = totalChapterCount
        record.directoryName = directoryName(for: item)
        record.chapters.removeAll { $0.index == chapter.index }
        record.chapters.append(chapter)
        record.chapters.sort { $0.index < $1.index }
        record.totalBytes = record.chapters.reduce(0) { $0 + $1.bytes }
        if let detail {
            record.detail = detail
        }
        if !comments.isEmpty {
            record.comments = comments
        }
        if let coverFileName {
            record.coverFileName = coverFileName
        }
        record.updatedAt = Date()

        records.removeAll { $0.id == id }
        records.insert(record, at: 0)
        records.sort { $0.updatedAt > $1.updatedAt }
        PicaXSQLiteStore.upsertDownloadRecord(record)
    }

    private func updateTask(_ id: String, update: (inout ComicDownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        update(&tasks[index])
    }

    private func saveTasks() {
        let persistedTasks = tasks.map { task -> ComicDownloadTask in
            var value = task
            if value.status == .downloading {
                value.status = .queued
                value.currentChapterIndex = nil
                value.currentPageIndex = 0
                value.currentPageCount = 0
            }
            return value
        }
        guard let data = try? encoder.encode(persistedTasks) else { return }
        defaults.set(data, forKey: DownloadSettingsKey.tasks)
        refreshProgressPresentation()
    }

    private static func loadTasks(defaults: UserDefaults, decoder: JSONDecoder) -> [ComicDownloadTask] {
        guard let data = defaults.data(forKey: DownloadSettingsKey.tasks),
              let tasks = try? decoder.decode([ComicDownloadTask].self, from: data) else {
            return []
        }
        return tasks.map { task in
            var value = task
            if value.status == .downloading {
                value.status = .queued
                value.currentChapterIndex = nil
                value.currentPageIndex = 0
                value.currentPageCount = 0
            }
            return value
        }
    }

    private func comicDirectory(for item: ComicListItem) throws -> URL {
        let directoryURL = try downloadsRootURL()
            .appendingPathComponent(item.platform.id, isDirectory: true)
            .appendingPathComponent(Self.safeFileName("\(item.id)-\(item.title)"), isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func comicDirectoryURLIfAvailable(for item: ComicListItem) -> URL? {
        guard let rootURL = Self.downloadsRootURLIfAvailable(fileManager: fileManager) else {
            return nil
        }
        return rootURL
            .appendingPathComponent(item.platform.id, isDirectory: true)
            .appendingPathComponent(Self.safeFileName("\(item.id)-\(item.title)"), isDirectory: true)
    }

    private func chapterDirectory(for item: ComicListItem, chapter: ComicChapter, index: Int) throws -> URL {
        let chapterURL = try comicDirectory(for: item)
            .appendingPathComponent(String(format: "%03d-%@", index + 1, Self.safeFileName(chapter.title)), isDirectory: true)
        try fileManager.createDirectory(at: chapterURL, withIntermediateDirectories: true)
        return chapterURL
    }

    private func downloadsRootURL() throws -> URL {
        try Self.downloadsRootURL(fileManager: fileManager)
    }

    private nonisolated static func downloadsRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ComicContentError.invalidResponse("无法访问应用支持目录。")
        }
        let rootURL = baseURL
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private nonisolated static func downloadsRootURLIfAvailable(fileManager: FileManager = .default) -> URL? {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseURL
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    private nonisolated static func removeDownloadDirectories(_ directoryURLs: [URL]) {
        guard !directoryURLs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for directoryURL in directoryURLs {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        }
    }

    private nonisolated static func downloadsDirectorySize() async -> Int64 {
        await Task.detached(priority: .utility) {
            guard let rootURL = try? downloadsRootURL() else { return 0 }
            return directorySize(at: rootURL)
        }.value
    }

    private nonisolated static func directorySize(at rootURL: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private func directoryName(for item: ComicListItem) -> String {
        Self.directoryName(for: item)
    }

    private nonisolated static func directoryName(for item: ComicListItem) -> String {
        "\(item.platform.rawValue)/\(safeFileName("\(item.id)-\(item.title)"))"
    }

    private func fileName(for urlString: String, pageIndex: Int) -> String {
        let ext = URL.picaxResolved(from: urlString)?.pathExtension
        let normalizedExt = ext?.isEmpty == false ? ext! : "jpg"
        return String(format: "%04d.%@", pageIndex + 1, normalizedExt)
    }

    private nonisolated static func isImageFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "gif":
            true
        default:
            false
        }
    }

    private func downloadID(for item: ComicListItem) -> String {
        "\(item.platform.id)-\(item.id)"
    }

    private nonisolated static func localChapterImages(
        item: ComicListItem,
        chapter: ComicChapter,
        chapterIndex: Int
    ) async -> [ComicChapterImage] {
        await Task.detached(priority: .utility) {
            guard let directoryURL = try? chapterDirectoryURL(item: item, chapter: chapter, index: chapterIndex),
                  let fileURLs = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            return fileURLs
                .filter { isImageFile($0) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .enumerated()
                .map { pageIndex, url in
                    ComicChapterImage(id: "\(chapter.id)-local-\(pageIndex + 1)", urlString: url.absoluteString)
                }
        }.value
    }

    private nonisolated static func chapterDirectoryURL(item: ComicListItem, chapter: ComicChapter, index: Int) throws -> URL {
        try downloadsRootURL()
            .appendingPathComponent(item.platform.rawValue, isDirectory: true)
            .appendingPathComponent(safeFileName("\(item.id)-\(item.title)"), isDirectory: true)
            .appendingPathComponent(String(format: "%03d-%@", index + 1, safeFileName(chapter.title)), isDirectory: true)
    }

    private nonisolated static func write(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try data.write(to: url, options: .atomic)
        }.value
    }

    private nonisolated static func makeArchiveExport(for record: DownloadRecord, fileNameTemplate: String) async throws -> DownloadArchiveExport {
        try await Task.detached(priority: .utility) {
            let imageURLs = try exportImageURLs(for: record)
            let entries = imageURLs.enumerated().map { pageIndex, fileURL in
                StreamingZipEntry(sourceURL: fileURL, archivePath: archiveFileName(pageNumber: pageIndex + 1, sourceURL: fileURL))
            }
            guard !entries.isEmpty else { throw DownloadArchiveExportError.noImages }

            let fileName = archiveFileName(for: record, template: fileNameTemplate)
            let temporaryDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PicaX-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
            let outputURL = temporaryDirectoryURL.appendingPathComponent(fileName)
            try StreamingZipArchive.write(entries: entries, to: outputURL)
            return DownloadArchiveExport(fileURL: outputURL, fileName: fileName)
        }.value
    }

    private nonisolated static func makePDFExport(for record: DownloadRecord, fileNameTemplate: String) async throws -> DownloadPDFExport {
        try await Task.detached(priority: .utility) {
            let imageURLs = try exportImageURLs(for: record)
            guard !imageURLs.isEmpty else { throw DownloadPDFExportError.noImages }

            let fileName = pdfFileName(for: record, template: fileNameTemplate)
            let temporaryDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PicaX-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
            let outputURL = temporaryDirectoryURL.appendingPathComponent(fileName)
            try writePDF(imageURLs: imageURLs, to: outputURL)
            return DownloadPDFExport(fileURL: outputURL, fileName: fileName)
        }.value
    }

    private nonisolated static func exportImageURLs(for record: DownloadRecord) throws -> [URL] {
        var imageURLs: [URL] = []

        for chapter in record.chapters.sorted(by: { $0.index < $1.index }) {
            guard let directoryURL = try? chapterDirectoryURL(item: record.item, chapter: chapter.chapter, index: chapter.index),
                  let fileURLs = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for fileURL in fileURLs
                .filter({ isImageFile($0) })
                .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                imageURLs.append(fileURL)
            }
        }

        return imageURLs
    }

    private nonisolated static func writePDF(imageURLs: [URL], to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw DownloadPDFExportError.invalidOutput
        }

        var pageCount = 0
        for imageURL in imageURLs {
            try autoreleasepool {
                guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw DownloadPDFExportError.unreadableImage(imageURL.lastPathComponent)
                }

                let pageWidth = max(CGFloat(image.width), 1)
                let pageHeight = max(CGFloat(image.height), 1)
                var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
                context.beginPage(mediaBox: &mediaBox)
                context.draw(image, in: mediaBox)
                context.endPage()
                pageCount += 1
            }
        }

        context.closePDF()
        guard pageCount > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw DownloadPDFExportError.noImages
        }
    }

    private nonisolated static func archiveFileName(pageNumber: Int, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? "\(pageNumber)" : "\(pageNumber).\(ext.lowercased())"
    }

    private nonisolated static func archiveFileName(for record: DownloadRecord, template: String) -> String {
        exportFileName(for: record, template: template, pathExtension: "zip")
    }

    private nonisolated static func pdfFileName(for record: DownloadRecord, template: String) -> String {
        exportFileName(for: record, template: template, pathExtension: "pdf")
    }

    private nonisolated static func exportFileName(for record: DownloadRecord, template: String, pathExtension: String) -> String {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTemplate = trimmedTemplate.isEmpty ? "{title}" : trimmedTemplate
        let renderedName = effectiveTemplate
            .replacingOccurrences(of: "{title}", with: record.item.title)
            .replacingOccurrences(of: "{id}", with: record.item.id)
            .replacingOccurrences(of: "{platform}", with: archivePlatformTitle(for: record.item.platform))
            .replacingOccurrences(of: "{date}", with: archiveExportDateString())

        var baseName = safeFileName(renderedName)
        for knownExtension in ["zip", "pdf"] {
            let suffix = ".\(knownExtension)"
            if baseName.lowercased().hasSuffix(suffix) {
                baseName.removeLast(suffix.count)
                baseName = safeFileName(baseName)
                break
            }
        }
        return "\(baseName).\(pathExtension)"
    }

    private nonisolated static func archiveExportDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private nonisolated static func archivePlatformTitle(for platform: ComicPlatform) -> String {
        switch platform {
        case .picacg:
            "PicACG"
        case .jmComic:
            "JMComic"
        case .nhentai:
            "NHentai"
        case .eHentai:
            "E-Hentai"
        case .hitomi:
            "Hitomi"
        case .htManga:
            "HT Manga"
        }
    }

    private nonisolated static func safeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : String(cleaned.prefix(80))
    }
}

private struct StreamingZipEntry {
    let sourceURL: URL
    let archivePath: String
}

private enum StreamingZipArchive {
    private struct CentralDirectoryRecord {
        let fileName: Data
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
    }

    nonisolated static func write(entries: [StreamingZipEntry], to outputURL: URL) throws {
        guard entries.count <= Int(UInt16.max) else {
            throw DownloadArchiveExportError.tooManyEntries
        }

        try? FileManager.default.removeItem(at: outputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        var offset: UInt32 = 0
        var centralRecords: [CentralDirectoryRecord] = []

        do {
            for entry in entries {
                let fileName = try fileNameData(for: entry.archivePath)
                let data = try Data(contentsOf: entry.sourceURL)
                let size = try uint32Size(data.count)
                let entryOffset = offset
                let crc32 = DownloadExportCRC32.checksum(data)

                var header = Data()
                header.appendUInt32LE(0x04034b50)
                header.appendUInt16LE(10)
                header.appendUInt16LE(0)
                header.appendUInt16LE(0)
                header.appendUInt16LE(0)
                header.appendUInt16LE(0)
                header.appendUInt32LE(crc32)
                header.appendUInt32LE(size)
                header.appendUInt32LE(size)
                header.appendUInt16LE(UInt16(fileName.count))
                header.appendUInt16LE(0)
                header.append(fileName)
                try write(header, to: handle, offset: &offset)
                try write(data, to: handle, offset: &offset)

                centralRecords.append(CentralDirectoryRecord(
                    fileName: fileName,
                    crc32: crc32,
                    size: size,
                    offset: entryOffset
                ))
            }

            let centralDirectoryOffset = offset
            var centralDirectory = Data()
            for record in centralRecords {
                centralDirectory.appendUInt32LE(0x02014b50)
                centralDirectory.appendUInt16LE(20)
                centralDirectory.appendUInt16LE(10)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt32LE(record.crc32)
                centralDirectory.appendUInt32LE(record.size)
                centralDirectory.appendUInt32LE(record.size)
                centralDirectory.appendUInt16LE(UInt16(record.fileName.count))
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt32LE(0)
                centralDirectory.appendUInt32LE(record.offset)
                centralDirectory.append(record.fileName)
            }

            let centralDirectorySize = try uint32Size(centralDirectory.count)
            try write(centralDirectory, to: handle, offset: &offset)

            let entryCount = UInt16(centralRecords.count)
            var footer = Data()
            footer.appendUInt32LE(0x06054b50)
            footer.appendUInt16LE(0)
            footer.appendUInt16LE(0)
            footer.appendUInt16LE(entryCount)
            footer.appendUInt16LE(entryCount)
            footer.appendUInt32LE(centralDirectorySize)
            footer.appendUInt32LE(centralDirectoryOffset)
            footer.appendUInt16LE(0)
            try write(footer, to: handle, offset: &offset)

            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private nonisolated static func write(_ data: Data, to handle: FileHandle, offset: inout UInt32) throws {
        guard UInt64(offset) + UInt64(data.count) <= UInt64(UInt32.max) else {
            throw DownloadArchiveExportError.entryTooLarge
        }
        try handle.write(contentsOf: data)
        offset += UInt32(data.count)
    }

    private nonisolated static func fileNameData(for path: String) throws -> Data {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains(".."),
              let data = path.data(using: .utf8),
              data.count <= Int(UInt16.max) else {
            throw DownloadArchiveExportError.invalidArchivePath
        }
        return data
    }

    private nonisolated static func uint32Size(_ value: Int) throws -> UInt32 {
        guard value <= Int(UInt32.max) else {
            throw DownloadArchiveExportError.entryTooLarge
        }
        return UInt32(value)
    }
}

private enum DownloadExportCRC32 {
    nonisolated static func checksum(_ data: Data) -> UInt32 {
        let initialCRC = crc32(0, nil, 0)
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.bindMemory(to: Bytef.self).baseAddress else {
                return UInt32(truncatingIfNeeded: initialCRC)
            }
            return UInt32(truncatingIfNeeded: crc32(initialCRC, baseAddress, uInt(data.count)))
        }
    }
}

private extension Data {
    nonisolated mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8)
        ])
    }

    nonisolated mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }
}

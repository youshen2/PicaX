import Combine
import Foundation

struct WatchDownloadedChapterRecord: Identifiable, Hashable, Codable {
    let index: Int
    let chapter: WatchChapterItem
    var pageCount: Int
    var bytes: Int64
    var downloadedAt: Date

    var id: Int { index }
}

struct WatchDownloadRecord: Identifiable, Hashable, Codable {
    let item: WatchComicItem
    var chapters: [WatchDownloadedChapterRecord]
    var totalChapterCount: Int
    var totalBytes: Int64
    var coverFileName: String?
    var updatedAt: Date

    var id: String {
        "\(item.platform.id)-\(item.id)"
    }

    var statusText: String {
        if totalChapterCount <= 1 {
            let pages = chapters.first?.pageCount ?? item.pageCount ?? 0
            return pages > 0 ? "已下载 \(pages) 页" : "已下载"
        }
        return "已下载 \(chapters.count)/\(totalChapterCount) 章"
    }

    var detailText: String {
        totalBytes > 0 ? "\(statusText) · \(WatchStorageFormatter.formattedSize(totalBytes))" : statusText
    }
}

struct WatchDownloadTask: Identifiable, Hashable, Codable {
    let id: String
    let detail: WatchComicDetailInfo
    let chapterIndexes: [Int]
    var status: WatchDownloadTaskStatus
    var currentChapterIndex: Int?
    var currentPageIndex: Int
    var currentPageCount: Int
    var downloadedBytes: Int64
    var errorMessage: String?
    var createdAt: Date

    init(detail: WatchComicDetailInfo, chapterIndexes: [Int]) {
        self.id = UUID().uuidString
        self.detail = detail
        self.chapterIndexes = chapterIndexes.sorted()
        self.status = .queued
        self.currentChapterIndex = nil
        self.currentPageIndex = 0
        self.currentPageCount = 0
        self.downloadedBytes = 0
        self.errorMessage = nil
        self.createdAt = Date()
    }

    var progress: Double {
        let total = max(chapterIndexes.count, 1)
        let completed = Double(chapterIndexes.filter { index in
            if let currentChapterIndex, index < currentChapterIndex { return true }
            return false
        }.count)
        guard status == .downloading, currentPageCount > 0 else {
            return min(completed / Double(total), 1)
        }
        return min((completed + Double(currentPageIndex) / Double(currentPageCount)) / Double(total), 1)
    }

    var statusText: String {
        switch status {
        case .queued:
            "等待下载"
        case .downloading:
            currentPageCount > 0 ? "\(currentPageIndex)/\(currentPageCount) 页" : "正在准备"
        case .paused:
            "已暂停"
        case .failed:
            errorMessage ?? "下载失败"
        }
    }
}

enum WatchDownloadTaskStatus: String, Hashable, Codable {
    case queued
    case downloading
    case paused
    case failed

    var canRun: Bool {
        self == .queued
    }
}

struct WatchDownloadStorageUsage: Equatable {
    let filesBytes: Int64
    let metadataBytes: Int
}

@MainActor
final class WatchDownloadService: ObservableObject {
    @Published private(set) var records: [WatchDownloadRecord] = []
    @Published private(set) var tasks: [WatchDownloadTask] = []

    private let defaults: UserDefaults
    private let client: WatchComicAPIClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var workerTask: Task<Void, Never>?
    private var accountProvider: ((WatchComicPlatform) -> WatchPlatformAccount?)?

    init(defaults: UserDefaults = .standard, client: WatchComicAPIClient = WatchComicAPIClient()) {
        self.defaults = defaults
        self.client = client
        if defaults.object(forKey: WatchSettingsKey.downloadRetryCount) == nil {
            defaults.set(2, forKey: WatchSettingsKey.downloadRetryCount)
        }
        if defaults.object(forKey: WatchSettingsKey.downloadReadsImagesFromCache) == nil {
            defaults.set(true, forKey: WatchSettingsKey.downloadReadsImagesFromCache)
        }
        records = Self.loadRecords(defaults: defaults, decoder: decoder)
        tasks = Self.loadTasks(defaults: defaults, decoder: decoder)
    }

    deinit {
        workerTask?.cancel()
    }

    func configure(accountProvider: @escaping (WatchComicPlatform) -> WatchPlatformAccount?) {
        self.accountProvider = accountProvider
        startIfNeeded()
    }

    func enqueue(detail: WatchComicDetailInfo, chapterIndexes: [Int]) {
        let downloaded = Set(record(for: detail.item)?.chapters.map(\.index) ?? [])
        let valid = Array(Set(chapterIndexes))
            .filter { detail.chapters.indices.contains($0) }
            .filter { !downloaded.contains($0) }
            .sorted()
        guard !valid.isEmpty else { return }
        guard tasks.contains(where: { $0.detail.item.id == detail.item.id && $0.detail.item.platform == detail.item.platform }) == false else {
            return
        }
        tasks.append(WatchDownloadTask(detail: detail, chapterIndexes: valid))
        saveTasks()
        startIfNeeded()
    }

    func retry(_ task: WatchDownloadTask) {
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

    func pause(_ task: WatchDownloadTask) {
        updateTask(task.id) { value in
            guard value.status == .queued || value.status == .downloading else { return }
            value.status = .paused
        }
        saveTasks()
    }

    func resume(_ task: WatchDownloadTask) {
        updateTask(task.id) { value in
            guard value.status == .paused || value.status == .failed else { return }
            value.status = .queued
            value.errorMessage = nil
        }
        saveTasks()
        startIfNeeded()
    }

    func remove(_ record: WatchDownloadRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
        let directoryURL = try? Self.comicDirectoryURL(item: record.item)
        Task.detached(priority: .utility) {
            if let directoryURL {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        }
    }

    func clearAllDownloads() {
        records.removeAll()
        tasks.removeAll()
        saveRecords()
        saveTasks()
        Task.detached(priority: .utility) {
            guard let rootURL = try? Self.rootURL() else { return }
            try? FileManager.default.removeItem(at: rootURL)
            _ = try? Self.rootURL()
        }
    }

    func record(for item: WatchComicItem) -> WatchDownloadRecord? {
        records.first { $0.id == "\(item.platform.id)-\(item.id)" }
    }

    func localChapterImages(for record: WatchDownloadRecord, chapterIndex: Int) async -> [WatchChapterImage] {
        guard let chapter = record.chapters.first(where: { $0.index == chapterIndex })?.chapter else {
            return []
        }
        return await Self.localChapterImages(item: record.item, chapter: chapter, chapterIndex: chapterIndex)
    }

    func storageUsage() async -> WatchDownloadStorageUsage {
        let files = await Self.downloadsDirectorySize()
        let metadata = (defaults.data(forKey: Self.recordsKey)?.count ?? 0) + (defaults.data(forKey: Self.tasksKey)?.count ?? 0)
        return WatchDownloadStorageUsage(filesBytes: files, metadataBytes: metadata)
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
        while let task = tasks.first(where: { $0.status.canRun }) {
            await runTask(id: task.id)
        }
    }

    private func runTask(id: String) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        updateTask(id) { value in
            value.status = .downloading
            value.errorMessage = nil
        }
        saveTasks()

        do {
            for chapterIndex in task.chapterIndexes {
                guard task.detail.chapters.indices.contains(chapterIndex) else { continue }
                try checkTaskCanContinue(id)
                let chapter = task.detail.chapters[chapterIndex]
                updateTask(id) { value in
                    value.currentChapterIndex = chapterIndex
                    value.currentPageIndex = 0
                    value.currentPageCount = 0
                }
                saveTasks()

                let images = try await client.loadChapterImages(
                    item: task.detail.item,
                    chapter: chapter,
                    account: accountProvider?(task.detail.item.platform)
                )
                let record = try await downloadChapter(
                    detail: task.detail,
                    chapter: chapter,
                    chapterIndex: chapterIndex,
                    images: images,
                    taskID: id
                )
                let coverFileName = await downloadCoverIfNeeded(item: task.detail.item)
                append(record, detail: task.detail, coverFileName: coverFileName)
            }
            tasks.removeAll { $0.id == id }
            saveTasks()
        } catch {
            updateTask(id) { value in
                value.status = .failed
                value.errorMessage = error.localizedDescription
            }
            saveTasks()
        }
    }

    private func downloadChapter(
        detail: WatchComicDetailInfo,
        chapter: WatchChapterItem,
        chapterIndex: Int,
        images: [WatchChapterImage],
        taskID: String
    ) async throws -> WatchDownloadedChapterRecord {
        let directoryURL = try Self.chapterDirectoryURL(item: detail.item, chapter: chapter, index: chapterIndex)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var totalBytes: Int64 = 0
        for (pageIndex, image) in images.enumerated() {
            try checkTaskCanContinue(taskID)
            let data = try await loadImageData(urlString: image.urlString)
            let fileURL = directoryURL.appendingPathComponent(fileName(for: image.urlString, pageIndex: pageIndex))
            try await Self.write(data, to: fileURL)
            totalBytes += Int64(data.count)
            updateTask(taskID) { value in
                value.currentPageIndex = pageIndex + 1
                value.currentPageCount = images.count
                value.downloadedBytes += Int64(data.count)
            }
            saveTasks()
        }
        return WatchDownloadedChapterRecord(
            index: chapterIndex,
            chapter: chapter,
            pageCount: images.count,
            bytes: totalBytes,
            downloadedAt: Date()
        )
    }

    private func loadImageData(urlString: String) async throws -> Data {
        let attempts = min(max(defaults.integer(forKey: WatchSettingsKey.downloadRetryCount), 0), 6) + 1
        let readsFromCache = defaults.object(forKey: WatchSettingsKey.downloadReadsImagesFromCache) == nil
            ? true
            : defaults.bool(forKey: WatchSettingsKey.downloadReadsImagesFromCache)
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await WatchImageCacheService.data(for: urlString, storesInCache: readsFromCache)
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw lastError ?? WatchComicAPIError.invalidResponse("图片下载失败。")
    }

    func localCoverURL(for record: WatchDownloadRecord) -> URL? {
        guard let coverFileName = record.coverFileName,
              let directoryURL = try? Self.comicDirectoryURL(item: record.item) else {
            return nil
        }
        let url = directoryURL.appendingPathComponent(coverFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func downloadCoverIfNeeded(item: WatchComicItem) async -> String? {
        guard let coverURLString = item.coverURLString, !coverURLString.isEmpty,
              let directoryURL = try? Self.comicDirectoryURL(item: item) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileName = "cover.jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileName
        }
        guard let data = try? await WatchImageCacheService.data(for: coverURLString, storesInCache: true) else {
            return nil
        }
        do {
            try await Self.write(data, to: fileURL)
            return fileName
        } catch {
            return nil
        }
    }

    private func append(_ chapter: WatchDownloadedChapterRecord, detail: WatchComicDetailInfo, coverFileName: String?) {
        var record = record(for: detail.item) ?? WatchDownloadRecord(
            item: detail.item,
            chapters: [],
            totalChapterCount: detail.chapters.count,
            totalBytes: 0,
            coverFileName: nil,
            updatedAt: Date()
        )
        record.chapters.removeAll { $0.index == chapter.index }
        record.chapters.append(chapter)
        record.chapters.sort { $0.index < $1.index }
        record.totalChapterCount = detail.chapters.count
        record.totalBytes = record.chapters.reduce(0) { $0 + $1.bytes }
        if let coverFileName {
            record.coverFileName = coverFileName
        }
        record.updatedAt = Date()
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        saveRecords()
    }

    private func checkTaskCanContinue(_ id: String) throws {
        guard tasks.first(where: { $0.id == id })?.status == .downloading else {
            throw WatchComicAPIError.server("下载已停止。")
        }
    }

    private func updateTask(_ id: String, update: (inout WatchDownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        update(&tasks[index])
    }

    private func saveRecords() {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey)
    }

    private func saveTasks() {
        let persisted = tasks.map { task -> WatchDownloadTask in
            var value = task
            if value.status == .downloading {
                value.status = .queued
                value.currentChapterIndex = nil
                value.currentPageIndex = 0
                value.currentPageCount = 0
            }
            return value
        }
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: Self.tasksKey)
    }

    private func fileName(for urlString: String, pageIndex: Int) -> String {
        let ext = URL.picaxWatchResolved(from: urlString)?.pathExtension
        let normalized = ext?.isEmpty == false ? ext! : "jpg"
        return String(format: "%04d.%@", pageIndex + 1, normalized)
    }

    private nonisolated static let recordsKey = "watch.download.records"
    private nonisolated static let tasksKey = "watch.download.tasks"

    private nonisolated static func loadRecords(defaults: UserDefaults, decoder: JSONDecoder) -> [WatchDownloadRecord] {
        guard let data = defaults.data(forKey: recordsKey),
              let records = try? decoder.decode([WatchDownloadRecord].self, from: data) else {
            return []
        }
        return records
    }

    private nonisolated static func loadTasks(defaults: UserDefaults, decoder: JSONDecoder) -> [WatchDownloadTask] {
        guard let data = defaults.data(forKey: tasksKey),
              let tasks = try? decoder.decode([WatchDownloadTask].self, from: data) else {
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

    private nonisolated static func rootURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WatchComicAPIError.invalidResponse("无法访问应用支持目录。")
        }
        let url = base.appendingPathComponent("WatchDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func comicDirectoryURL(item: WatchComicItem) throws -> URL {
        try rootURL()
            .appendingPathComponent(item.platform.id, isDirectory: true)
            .appendingPathComponent(safeFileName("\(item.id)-\(item.title)"), isDirectory: true)
    }

    private static func chapterDirectoryURL(item: WatchComicItem, chapter: WatchChapterItem, index: Int) throws -> URL {
        try comicDirectoryURL(item: item)
            .appendingPathComponent(String(format: "%03d-%@", index + 1, safeFileName(chapter.title)), isDirectory: true)
    }

    private static func localChapterImages(
        item: WatchComicItem,
        chapter: WatchChapterItem,
        chapterIndex: Int
    ) async -> [WatchChapterImage] {
        guard let directoryURL = try? chapterDirectoryURL(item: item, chapter: chapter, index: chapterIndex) else {
            return []
        }
        let chapterID = chapter.id
        return await Task.detached(priority: .utility) {
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else {
                return []
            }
            return fileURLs
                .filter { ["jpg", "jpeg", "png", "webp", "gif"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .enumerated()
                .map { index, url in
                    WatchChapterImage(id: "\(chapterID)-local-\(index + 1)", urlString: url.absoluteString)
                }
        }.value
    }

    private nonisolated static func downloadsDirectorySize() async -> Int64 {
        await Task.detached(priority: .utility) {
            guard let root = try? rootURL(),
                  let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                return 0
            }
            var total: Int64 = 0
            let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
            for fileURL in fileURLs {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                total += Int64(values?.fileSize ?? 0)
            }
            return total
        }.value
    }

    private nonisolated static func write(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try data.write(to: url, options: .atomic)
        }.value
    }

    private nonisolated static func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : String(cleaned.prefix(80))
    }
}

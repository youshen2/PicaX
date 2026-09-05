import Foundation
import ImageIO

nonisolated struct DownloadIntegrityIssue: Identifiable, Sendable {
    let chapterIndex: Int
    let chapterTitle: String
    let pageIndex: Int
    var id: String { "\(chapterIndex):\(pageIndex)" }
}

nonisolated struct DownloadIntegrityReport: Sendable {
    let recordID: String
    let checkedPages: Int
    let issues: [DownloadIntegrityIssue]
}

nonisolated enum DownloadImageValidation {
    static func isReadable(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }

    static func pageFiles(in directory: URL) throws -> [Int: URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return Dictionary(files.compactMap { url -> (Int, URL)? in
            guard DownloadService.isImageFile(url), let number = Int(url.deletingPathExtension().lastPathComponent), number > 0 else { return nil }
            return (number - 1, url)
        }, uniquingKeysWith: { first, _ in first })
    }
}

extension DownloadService {
    func inspectIntegrity(of record: DownloadRecord) async throws -> DownloadIntegrityReport {
        let recordID = record.id
        let work = Task.detached(priority: .utility) {
            var issues: [DownloadIntegrityIssue] = []
            var checked = 0
            for chapter in record.chapters {
                let directory = try Self.chapterDirectoryURL(item: record.item, chapter: chapter.chapter, index: chapter.index)
                let files = try DownloadImageValidation.pageFiles(in: directory)
                for page in 0..<chapter.pageCount {
                    try Task.checkCancellation()
                    checked += 1
                    let readable = autoreleasepool { files[page].map(DownloadImageValidation.isReadable) ?? false }
                    if !readable {
                        issues.append(.init(chapterIndex: chapter.index, chapterTitle: chapter.chapter.title, pageIndex: page))
                    }
                }
            }
            return DownloadIntegrityReport(recordID: recordID, checkedPages: checked, issues: issues)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    func repair(_ report: DownloadIntegrityReport, record: DownloadRecord,
                onProgress: (Int, Int) -> Void) async throws {
        guard report.recordID == record.id, record.item.platform != .local else {
            throw ComicContentError.unsupported("本地导入的损坏页面需要从原文件重新导入。")
        }
        guard task(for: record.item) == nil else {
            throw ComicContentError.invalidResponse("请先完成或移除这本漫画的下载任务。")
        }
        var completed = 0
        for chapter in record.chapters {
            let issues = report.issues.filter { $0.chapterIndex == chapter.index }
            guard !issues.isEmpty else { continue }
            try Task.checkCancellation()
            let images = try await contentService.loadChapterImages(item: record.item, chapter: chapter.chapter,
                                                                    account: accountProvider?(record.item.platform))
            guard images.count == chapter.pageCount else {
                throw ComicContentError.invalidResponse("\(chapter.chapter.title) 的在线页数已变化，请重新下载该章节。")
            }
            let directory = try chapterDirectory(for: record.item, chapter: chapter.chapter, index: chapter.index)
            let existingFiles = try DownloadImageValidation.pageFiles(in: directory)
            for issue in issues {
                try Task.checkCancellation()
                guard self.record(for: record.item) != nil else { throw CancellationError() }
                let image = images[issue.pageIndex]
                let startedAt = Date()
                let data = try await loadImageDataWithRetry(urlString: image.urlString, bypassesCache: true)
                let storageImage: JmImageScrambler.DecodedStorageImage
                if record.item.platform == .jmComic, let url = image.url {
                    storageImage = try await Self.decodeJmImageForStorage(data: data, url: url)
                } else {
                    storageImage = .init(data: data, fileExtension: nil)
                }
                let destination = directory.appendingPathComponent(fileName(for: image.urlString, pageIndex: issue.pageIndex,
                                                                            preferredExtension: storageImage.fileExtension))
                guard self.record(for: record.item) != nil else { throw CancellationError() }
                try await Self.write(storageImage.data, to: destination)
                let isReadable = await Task.detached(priority: .utility) {
                    autoreleasepool { DownloadImageValidation.isReadable(destination) }
                }.value
                guard isReadable else {
                    throw ComicContentError.invalidResponse("\(chapter.chapter.title) 第 \(issue.pageIndex + 1) 页仍无法读取，请稍后重试。")
                }
                if let old = existingFiles[issue.pageIndex], old != destination { try fileManager.removeItem(at: old) }
                try await throttleIfNeeded(downloadedBytes: data.count, startedAt: startedAt)
                completed += 1
                onProgress(completed, report.issues.count)
            }
            var repaired = chapter
            repaired.bytes = await Task.detached(priority: .utility) { Self.directorySize(at: directory) }.value
            repaired.downloadedAt = Date()
            guard self.record(for: record.item) != nil else { throw CancellationError() }
            appendDownloadedChapter(item: record.item, totalChapterCount: record.totalChapterCount, chapter: repaired,
                                    detail: record.detail, comments: record.comments, coverFileName: record.coverFileName)
        }
    }
}

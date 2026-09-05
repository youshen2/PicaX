import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

enum LocalComicImportSettings {
    static let pdfPageWidth = "settings.localImport.pdfPageWidth"
}

extension DownloadService {
    func importComic(from source: URL) async throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let title = source.deletingPathExtension().lastPathComponent
        let item = ComicListItem(id: UUID().uuidString, platform: .local, title: title, subtitle: "本地导入",
                                 coverURLString: "", tags: [], pageCount: nil, likesCount: nil, favoriteDate: nil)
        let chapter = ComicChapter(id: item.id, title: title, subtitle: nil)
        let directory = try chapterDirectory(for: item, chapter: chapter, index: 0)
        let comicDirectory = directory.deletingLastPathComponent()
        let configuredWidth = defaults.integer(forKey: LocalComicImportSettings.pdfPageWidth)
        let width = configuredWidth > 0 ? min(max(configuredWidth, 1000), 3000) : 1800
        do {
            let work = Task.detached(priority: .userInitiated) {
                try LocalComicImporter.write(source: source, to: directory, pdfWidth: width)
            }
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            let first = result.firstPage
            let coverName = "cover." + first.pathExtension
            try fileManager.copyItem(at: first, to: comicDirectory.appendingPathComponent(coverName))
            let importedItem = ComicListItem(id: item.id, platform: .local, title: title, subtitle: "本地导入",
                                            coverURLString: comicDirectory.appendingPathComponent(coverName).picaxPortableDownloadURLString,
                                            tags: [], pageCount: result.pageCount, likesCount: nil, favoriteDate: nil)
            let detail = ComicDetailInfo(item: importedItem, description: "从 \(source.lastPathComponent) 导入",
                                         tagGroups: [], chapters: [chapter], related: [], updatedText: nil)
            appendDownloadedChapter(item: importedItem, totalChapterCount: 1,
                                    chapter: .init(index: 0, chapter: chapter, pageCount: result.pageCount,
                                                   bytes: result.bytes, downloadedAt: Date()),
                                    detail: detail, comments: [], coverFileName: coverName)
        } catch {
            try? fileManager.removeItem(at: comicDirectory)
            throw error
        }
    }
}

private nonisolated enum LocalComicImporter {
    struct Result: Sendable {
        let pageCount: Int
        let bytes: Int64
        let firstPage: URL
    }

    static func write(source: URL, to directory: URL, pdfWidth: Int) throws -> Result {
        let pages: [URL]
        switch source.pathExtension.lowercased() {
        case "zip", "cbz": pages = try extractArchive(source, to: directory)
        case "pdf": pages = try renderPDF(source, to: directory, width: pdfWidth)
        default: throw ComicContentError.unsupported("请选择 ZIP、CBZ 或 PDF 文件。")
        }
        guard let first = pages.first else { throw ComicContentError.invalidResponse("文件中没有可阅读的图片页面。") }
        return Result(pageCount: pages.count, bytes: DownloadService.directorySize(at: directory), firstPage: first)
    }

    static func extractArchive(_ source: URL, to directory: URL) throws -> [URL] {
        let archive = try Archive(url: source, accessMode: .read)
        let entries = archive.filter {
            $0.type == .file && !$0.path.hasPrefix("__MACOSX/") && DownloadService.isImageFile(URL(fileURLWithPath: $0.path))
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let maximumBytes: UInt64 = 2 * 1024 * 1024 * 1024
        var totalBytes: UInt64 = 0
        for entry in entries {
            guard UInt64(entry.uncompressedSize) <= maximumBytes - totalBytes else {
                throw ComicContentError.invalidResponse("解压后的图片超过 2 GB，请拆分后导入。")
            }
            totalBytes += UInt64(entry.uncompressedSize)
        }
        return try entries.enumerated().map { index, entry in
            try Task.checkCancellation()
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            let destination = directory.appendingPathComponent(String(format: "%04d.%@", index + 1, ext))
            // Generate every output path ourselves; archive paths and symlinks are never written.
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            var bytesWritten: UInt64 = 0
            let checksum = try archive.extract(entry) { data in
                try Task.checkCancellation()
                bytesWritten += UInt64(data.count)
                guard bytesWritten <= UInt64(entry.uncompressedSize) else {
                    throw ComicContentError.invalidResponse("压缩包图片尺寸与记录不符。")
                }
                try handle.write(contentsOf: data)
            }
            guard checksum == entry.checksum else {
                throw ComicContentError.invalidResponse("压缩包校验失败：\(entry.path)")
            }
            guard autoreleasepool(invoking: { DownloadImageValidation.isReadable(destination) }) else {
                throw ComicContentError.invalidResponse("无法读取图片：\(entry.path)")
            }
            return destination
        }
    }

    static func renderPDF(_ source: URL, to directory: URL, width: Int) throws -> [URL] {
        guard let document = CGPDFDocument(source as CFURL), !document.isEncrypted || document.isUnlocked else {
            throw ComicContentError.invalidResponse("PDF 无法读取或需要密码。")
        }
        var pages: [URL] = []
        for index in 0..<document.numberOfPages {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(String(format: "%04d.png", index + 1))
            try autoreleasepool {
                guard let page = document.page(at: index + 1) else { throw ComicContentError.invalidResponse("PDF 页面无法读取。") }
                let box = page.getBoxRect(.mediaBox)
                let rotated = abs(page.rotationAngle) % 180 == 90
                let pageWidth = rotated ? box.height : box.width
                let pageHeight = rotated ? box.width : box.height
                guard pageWidth > 0, pageHeight > 0 else { throw ComicContentError.invalidResponse("PDF 页面尺寸无效。") }
                let scale = min(CGFloat(width) / pageWidth, 6000 / pageHeight)
                let width = max(1, Int(pageWidth * scale))
                let height = max(1, Int(pageHeight * scale))
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    throw ComicContentError.invalidResponse("无法创建 PDF 页面图像。")
                }
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(bounds)
                context.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
                guard let image = context.makeImage(),
                      let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw ComicContentError.invalidResponse("无法保存 PDF 页面。")
                }
                CGImageDestinationAddImage(output, image, nil)
                guard CGImageDestinationFinalize(output) else { throw ComicContentError.invalidResponse("PDF 页面保存失败。") }
            }
            pages.append(url)
        }
        return pages
    }
}

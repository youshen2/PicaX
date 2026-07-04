import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import libwebp

struct WatchCacheUsage: Equatable {
    let diskBytes: Int64

    var formatted: String {
        WatchStorageFormatter.formattedSize(diskBytes)
    }
}

enum WatchImageCacheService {
    nonisolated static let defaultMaxDiskSizeMB = 120
    nonisolated private static let lock = NSLock()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    @MainActor
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB) == nil {
            defaults.set(defaultMaxDiskSizeMB, forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB)
        }
        trimIfNeeded(maxBytes: max(defaults.integer(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB), 20) * 1024 * 1024)
    }

    @MainActor
    static func clear() {
        withLock {
            try? FileManager.default.removeItem(at: cacheDirectoryURL)
            prepareDirectory()
        }
    }

    @MainActor
    static var usage: WatchCacheUsage {
        withLock {
            WatchCacheUsage(diskBytes: directorySize(at: cacheDirectoryURL))
        }
    }

    nonisolated static func data(for urlString: String, storesInCache: Bool = true) async throws -> Data {
        guard let url = URL.picaxWatchResolved(from: urlString) else {
            throw WatchComicAPIError.invalidURL(urlString)
        }
        return try await data(for: url, storesInCache: storesInCache)
    }

    nonisolated static func data(for url: URL, storesInCache: Bool = true) async throws -> Data {
        try await data(for: url, storesInCache: storesInCache, readsFromCache: true)
    }

    nonisolated private static func data(for url: URL, storesInCache: Bool, readsFromCache: Bool) async throws -> Data {
        if url.isFileURL {
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: url)
            }.value
        }

        let cacheEnabled = UserDefaults.standard.object(forKey: WatchSettingsKey.imageCacheEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: WatchSettingsKey.imageCacheEnabled)
        let shouldCache = storesInCache && cacheEnabled
        if shouldCache, readsFromCache, let cached = await cachedData(for: url) {
            return cached
        }

        let downloadedData = try await downloadImageData(for: url)
        let imageData = try await readableImageData(from: downloadedData, url: url)
        if shouldCache {
            await store(imageData, for: url)
        }
        return imageData
    }

    nonisolated static func preferredFileExtension(for urlString: String) -> String? {
        guard let url = URL.picaxWatchResolved(from: urlString), !url.isFileURL else { return nil }
        return WatchJmImageScrambler.cacheFileExtension(for: url) ?? WatchWebPDecoder.cacheFileExtension(for: url)
    }

    nonisolated static func localCachedURL(for urlString: String) -> URL? {
        guard let url = URL.picaxWatchResolved(from: urlString), !url.isFileURL else {
            return URL.picaxWatchResolved(from: urlString)
        }
        return withLock {
            let fileURL = cacheFileURL(for: url)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            guard isReadableImageFile(fileURL) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            touch(fileURL)
            return fileURL
        }
    }

    nonisolated static func cachedFileURL(for urlString: String, forceRefresh: Bool = false) async throws -> URL {
        guard let url = URL.picaxWatchResolved(from: urlString) else {
            throw WatchComicAPIError.invalidURL(urlString)
        }
        if url.isFileURL { return url }
        if !forceRefresh, let localURL = localCachedURL(for: url.absoluteString) {
            return localURL
        }
        if forceRefresh {
            removeCachedFile(for: url)
        }
        let data = try await data(for: url, storesInCache: true, readsFromCache: false)
        return try await Task.detached(priority: .utility) {
            try withLock {
                prepareDirectory()
                let fileURL = cacheFileURL(for: url)
                try data.write(to: fileURL, options: .atomic)
                touch(fileURL)
                let maxMB = UserDefaults.standard.object(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB) == nil
                    ? defaultMaxDiskSizeMB
                    : UserDefaults.standard.integer(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB)
                trimIfNeededLocked(maxBytes: max(maxMB, 20) * 1024 * 1024)
                return fileURL
            }
        }.value
    }

    nonisolated static func removeCachedFile(for urlString: String) {
        guard let url = URL.picaxWatchResolved(from: urlString), !url.isFileURL else { return }
        removeCachedFile(for: url)
    }

    private nonisolated static func cachedData(for url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            withLock {
                let fileURL = cacheFileURL(for: url)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                guard let data = try? Data(contentsOf: fileURL),
                      isReadableImageData(data) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                touch(fileURL)
                return data
            }
        }.value
    }

    private nonisolated static func store(_ data: Data, for url: URL) async {
        await Task.detached(priority: .utility) {
            withLock {
                prepareDirectory()
                let fileURL = cacheFileURL(for: url)
                try? data.write(to: fileURL, options: .atomic)
                touch(fileURL)
                let maxMB = UserDefaults.standard.object(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB) == nil
                    ? defaultMaxDiskSizeMB
                    : UserDefaults.standard.integer(forKey: WatchSettingsKey.imageCacheMaxDiskSizeMB)
                trimIfNeededLocked(maxBytes: max(maxMB, 20) * 1024 * 1024)
            }
        }.value
    }

    private nonisolated static func downloadImageData(for url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        imageHeaders(for: url).forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WatchComicAPIError.server("HTTP \(httpResponse.statusCode)")
        }
        return data
    }

    private nonisolated static func readableImageData(from data: Data, url: URL) async throws -> Data {
        let normalizedData = WatchWebPDecoder.decodedImageData(data) ?? data
        if let decoded = WatchJmImageScrambler.decodedImageData(data: normalizedData, url: url),
           isReadableImageData(decoded) {
            return decoded
        }
        if isReadableImageData(normalizedData) {
            return normalizedData
        }

        for fallbackURL in WatchJmImageScrambler.fallbackImageURLs(for: url) {
            guard fallbackURL != url else { continue }
            let fallbackData: Data
            do {
                fallbackData = try await downloadImageData(for: fallbackURL)
            } catch {
                continue
            }
            let normalizedFallbackData = WatchWebPDecoder.decodedImageData(fallbackData) ?? fallbackData
            if let decoded = WatchJmImageScrambler.decodedImageData(data: normalizedFallbackData, url: fallbackURL),
               isReadableImageData(decoded) {
                return decoded
            }
            if isReadableImageData(normalizedFallbackData) {
                return normalizedFallbackData
            }
        }

        throw WatchComicAPIError.invalidResponse("图片数据无法解码。")
    }

    private nonisolated static func isReadableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              !WatchWebPDecoder.isWebPData(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private nonisolated static func isReadableImageFile(_ fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else {
            return false
        }
        return isReadableImageData(data)
    }

    private nonisolated static func removeCachedFile(for url: URL) {
        withLock {
            try? FileManager.default.removeItem(at: cacheFileURL(for: url))
        }
    }

    private nonisolated static func imageHeaders(for url: URL) -> [String: String] {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        var headers = [
            "Accept": "image/webp,image/jpeg,image/png,image/apng,image/avif;q=0,image/*;q=0.6,*/*;q=0.4",
            "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ]
        if host.contains("nhentai") {
            headers["Referer"] = "https://nhentai.net/"
        } else if host.contains("e-hentai") || host.contains("exhentai") || host.contains("ehgt") {
            headers["Referer"] = "https://e-hentai.org/"
            headers["Cookie"] = "nw=1"
        }
        return headers
    }

    private nonisolated static func cacheFileURL(for url: URL) -> URL {
        let identity = WatchWebPDecoder.cacheIdentity(
            for: url,
            fallback: WatchJmImageScrambler.cacheIdentity(for: url)
        )
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let ext = WatchJmImageScrambler.cacheFileExtension(for: url)
            ?? WatchWebPDecoder.cacheFileExtension(for: url)
            ?? (url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased())
        return cacheDirectoryURL.appendingPathComponent("\(digest).\(ext)", isDirectory: false)
    }

    private nonisolated static var cacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WatchImageCache", isDirectory: true)
    }

    private nonisolated static func prepareDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private nonisolated static func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    private nonisolated static func trimIfNeeded(maxBytes: Int) {
        withLock {
            prepareDirectory()
            trimIfNeededLocked(maxBytes: maxBytes)
        }
    }

    private nonisolated static func trimIfNeededLocked(maxBytes: Int) {
        var files = cacheFiles()
        var total = files.reduce(Int64(0)) { $0 + $1.byteCount }
        guard total > Int64(maxBytes) else { return }
        files.sort { $0.modifiedAt < $1.modifiedAt }
        for file in files {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.byteCount
            if total <= Int64(maxBytes) { break }
        }
    }

    private nonisolated static func cacheFiles() -> [WatchDiskFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return WatchDiskFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        cacheFiles().reduce(Int64(0)) { $0 + $1.byteCount }
    }

    private nonisolated static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

struct WatchDiskFile {
    let url: URL
    let byteCount: Int64
    let modifiedAt: Date
}

private enum WatchWebPDecoder {
    private nonisolated static let cacheVersion = "webp-decoded-v1"

    nonisolated static func decodedImageData(_ data: Data) -> Data? {
        guard isWebPData(data),
              let cgImage = decodedCGImage(data) else {
            return nil
        }
        return encodedPNGData(cgImage: cgImage)
    }

    nonisolated static func cacheIdentity(for url: URL, fallback: String) -> String {
        url.pathExtension.lowercased() == "webp" ? "\(cacheVersion):\(fallback)" : fallback
    }

    nonisolated static func cacheFileExtension(for url: URL) -> String? {
        url.pathExtension.lowercased() == "webp" ? "png" : nil
    }

    nonisolated static func isWebPData(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return data.prefix(4).elementsEqual("RIFF".utf8)
            && data.dropFirst(8).prefix(4).elementsEqual("WEBP".utf8)
    }

    private nonisolated static func decodedCGImage(_ data: Data) -> CGImage? {
        data.withUnsafeBytes { rawBuffer -> CGImage? in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            var width: Int32 = 0
            var height: Int32 = 0
            guard WebPGetInfo(baseAddress, data.count, &width, &height) != 0,
                  width > 0,
                  height > 0,
                  let decodedPixels = WebPDecodeRGBA(baseAddress, data.count, &width, &height) else {
                return nil
            }
            defer { WebPFree(decodedPixels) }

            let widthValue = Int(width)
            let heightValue = Int(height)
            let bytesPerRow = widthValue * 4
            let pixelByteCount = bytesPerRow * heightValue
            let pixelData = Data(bytes: decodedPixels, count: pixelByteCount)
            guard let provider = CGDataProvider(data: pixelData as CFData) else {
                return nil
            }

            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue
            return CGImage(
                width: widthValue,
                height: heightValue,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }
    }

    private nonisolated static func encodedPNGData(cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

private enum WatchJmImageScrambler {
    private nonisolated static let scrambleID = 220_980
    private nonisolated static let cacheVersion = "jm-decoded-v1"

    nonisolated static func decodedImageData(data: Data, url: URL) -> Data? {
        guard let info = imageInfo(from: url),
              let segmentCount = segmentCount(epsID: info.epsID, pictureName: info.pictureName),
              segmentCount > 1,
              let cgImage = originalCGImage(data: data) else {
            return nil
        }

        guard let rendered = reorderedImage(cgImage: cgImage, segmentCount: segmentCount) else {
            return encodedPNGData(cgImage: cgImage)
        }
        return encodedPNGData(cgImage: rendered)
    }

    nonisolated static func cacheIdentity(for url: URL) -> String {
        guard requiresDecoding(url: url) else { return url.absoluteString }
        return "\(cacheVersion):\(url.absoluteString)"
    }

    nonisolated static func cacheFileExtension(for url: URL) -> String? {
        if requiresDecoding(url: url) {
            return "png"
        }
        if imageInfo(from: url) != nil, url.pathExtension.lowercased() == "webp" {
            return "png"
        }
        return nil
    }

    nonisolated static func fallbackImageURLs(for url: URL) -> [URL] {
        guard imageInfo(from: url) != nil else { return [] }
        let currentExtension = url.pathExtension.lowercased()
        let extensions = ["jpg", "jpeg", "png"].filter { $0 != currentExtension }
        var seen = Set<String>()
        return extensions.compactMap { ext in
            let candidate = url.deletingPathExtension().appendingPathExtension(ext)
            guard seen.insert(candidate.absoluteString).inserted else { return nil }
            return candidate
        }
    }

    private nonisolated static func requiresDecoding(url: URL) -> Bool {
        guard let info = imageInfo(from: url),
              let segmentCount = segmentCount(epsID: info.epsID, pictureName: info.pictureName) else {
            return false
        }
        return segmentCount > 1
    }

    private nonisolated static func imageInfo(from url: URL) -> (epsID: Int, pictureName: String)? {
        let components = url.pathComponents
        guard let photosIndex = components.lastIndex(of: "photos"),
              components.indices.contains(photosIndex + 2),
              let epsID = Int(components[photosIndex + 1]) else {
            return nil
        }

        let pictureName = (components[photosIndex + 2] as NSString).deletingPathExtension
        guard !pictureName.isEmpty else { return nil }
        return (epsID, pictureName)
    }

    private nonisolated static func segmentCount(epsID: Int, pictureName: String) -> Int? {
        if epsID < scrambleID {
            return 0
        }
        if epsID < 268_850 {
            return 10
        }

        let hashInput = "\(epsID)\(pictureName)"
        let digest = Insecure.MD5.hash(data: Data(hashInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let last = digest.utf8.last else { return nil }

        let divisor = epsID > 421_926 ? 8 : 10
        return Int(last % UInt8(divisor)) * 2 + 2
    }

    private nonisolated static func originalCGImage(data: Data) -> CGImage? {
        guard !WatchWebPDecoder.isWebPData(data) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private nonisolated static func reorderedImage(cgImage: CGImage, segmentCount: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let blockHeight = height / segmentCount
        let remainder = height % segmentCount
        guard width > 0, height > 0, blockHeight > 0 else { return cgImage }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = width * 4
        var sourcePixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let didDrawSource = sourcePixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard didDrawSource else { return nil }

        var destinationPixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        sourcePixels.withUnsafeBytes { sourceBuffer in
            destinationPixels.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBase = sourceBuffer.baseAddress,
                      let destinationBase = destinationBuffer.baseAddress else {
                    return
                }

                var destinationY = 0
                for index in stride(from: segmentCount - 1, through: 0, by: -1) {
                    let sourceY = index * blockHeight
                    let currentHeight = blockHeight + (index == segmentCount - 1 ? remainder : 0)

                    for row in 0..<currentHeight {
                        let sourceOffset = (sourceY + row) * bytesPerRow
                        let destinationOffset = (destinationY + row) * bytesPerRow
                        destinationBase
                            .advanced(by: destinationOffset)
                            .copyMemory(from: sourceBase.advanced(by: sourceOffset), byteCount: bytesPerRow)
                    }

                    destinationY += currentHeight
                }
            }
        }

        let data = Data(destinationPixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private nonisolated static func encodedPNGData(cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

}

enum WatchStorageFormatter {
    nonisolated static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

extension URL {
    nonisolated static func picaxWatchResolved(from value: String) -> URL? {
        if value.hasPrefix("file://") {
            return URL(string: value)
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return URL(string: value)
    }
}

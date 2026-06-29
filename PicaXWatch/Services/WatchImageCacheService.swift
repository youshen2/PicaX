import CryptoKit
import Foundation
import ImageIO

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

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        imageHeaders(for: url).forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WatchComicAPIError.server("HTTP \(httpResponse.statusCode)")
        }
        guard isImageData(data) else {
            throw WatchComicAPIError.invalidResponse("图片数据无法解码。")
        }
        if shouldCache {
            await store(data, for: url)
        }
        return data
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
                      isImageData(data) else {
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

    private nonisolated static func isImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private nonisolated static func isReadableImageFile(_ fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else {
            return false
        }
        return isImageData(data)
    }

    private nonisolated static func removeCachedFile(for url: URL) {
        withLock {
            try? FileManager.default.removeItem(at: cacheFileURL(for: url))
        }
    }

    private nonisolated static func imageHeaders(for url: URL) -> [String: String] {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        var headers = [
            "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
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
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
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

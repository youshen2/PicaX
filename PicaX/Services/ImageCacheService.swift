import CryptoKit
import Foundation
import ImageIO

struct ImageCacheUsage: Equatable {
    let memoryBytes: Int
    let diskBytes: Int

    var totalBytes: Int {
        memoryBytes + diskBytes
    }
}

enum ImageCacheService {
    nonisolated static let defaultMaxDiskSizeMB = 400
    private static let lock = NSLock()
    nonisolated(unsafe) private static var diskCapacityBytes = defaultMaxDiskSizeMB * 1024 * 1024
    private static let uncachedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    @MainActor
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: ImageCacheSettingsKey.maxDiskSizeMB) == nil {
            defaults.set(defaultMaxDiskSizeMB, forKey: ImageCacheSettingsKey.maxDiskSizeMB)
        }

        let storedSize = defaults.integer(forKey: ImageCacheSettingsKey.maxDiskSizeMB)
        let diskCapacity = max(storedSize, 50) * 1024 * 1024
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
        withDiskCacheLock {
            diskCapacityBytes = diskCapacity
            prepareDiskCacheDirectoryLocked()
            trimDiskCacheIfNeededLocked()
        }
    }

    @MainActor
    static func clear() {
        URLCache.shared.removeAllCachedResponses()
        withDiskCacheLock {
            let directoryURL = cacheDirectoryURL
            try? FileManager.default.removeItem(at: directoryURL)
            prepareDiskCacheDirectoryLocked()
        }
    }

    @MainActor
    static var usage: ImageCacheUsage {
        withDiskCacheLock {
            ImageCacheUsage(memoryBytes: 0, diskBytes: Int(min(diskUsageBytesLocked(), Int64(Int.max))))
        }
    }

    nonisolated static func formattedSize(_ bytes: Int) -> String {
        formattedSize(Int64(bytes))
    }

    nonisolated static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated static func data(for url: URL, storesInCache: Bool = true) async throws -> Data {
        if let fileURL = url.picaxLocalFileURL {
            return try await localFileData(for: fileURL)
        }

        guard url.picaxSupportsURLCache else {
            throw URLError(.unsupportedURL)
        }

        if storesInCache, let cachedData = await cachedImageData(for: url) {
            return cachedData
        }

        let (data, response) = try await uncachedData(for: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard isDecodableImageData(data) else {
            throw URLError(.cannotDecodeContentData)
        }
        if storesInCache {
            await storeImageData(data, for: url)
        }
        return data
    }

    nonisolated static func storeDecodedImageData(_ data: Data, for url: URL) {
        guard url.picaxLocalFileURL == nil,
              url.picaxSupportsURLCache,
              isDecodableImageData(data) else {
            return
        }
        withDiskCacheLock {
            prepareDiskCacheDirectoryLocked()
            let fileURL = cacheFileURL(for: url)
            try? data.write(to: fileURL, options: [.atomic])
            touchCacheFileLocked(fileURL)
            trimDiskCacheIfNeededLocked()
        }
    }

    nonisolated static func removeCachedImageData(for url: URL) {
        guard url.picaxSupportsURLCache else { return }
        withDiskCacheLock {
            try? FileManager.default.removeItem(at: cacheFileURL(for: url))
        }
    }

    nonisolated static func prefetchImageData(for url: URL) async throws {
        _ = try await data(for: url)
    }

    private nonisolated static func uncachedData(for url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return try await uncachedSession.data(for: request)
    }

    private nonisolated static func localFileData(for fileURL: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: fileURL)
        }.value
    }

    private nonisolated static func cachedImageData(for url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            diskCachedImageData(for: url)
        }.value
    }

    private nonisolated static func storeImageData(_ data: Data, for url: URL) async {
        await Task.detached(priority: .utility) {
            storeDecodedImageData(data, for: url)
        }.value
    }

    private nonisolated static func diskCachedImageData(for url: URL) -> Data? {
        guard url.picaxLocalFileURL == nil, url.picaxSupportsURLCache else {
            return nil
        }

        return withDiskCacheLock {
            let fileURL = cacheFileURL(for: url)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL), isDecodableImageData(data) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            touchCacheFileLocked(fileURL)
            return data
        }
    }

    private nonisolated static func isDecodableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private nonisolated static func withDiskCacheLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private nonisolated static var cacheDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("ImageCache", isDirectory: true)
    }

    private nonisolated static func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectoryURL.appendingPathComponent(digest, isDirectory: false)
    }

    private nonisolated static func prepareDiskCacheDirectoryLocked() {
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private nonisolated static func touchCacheFileLocked(_ fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private nonisolated static func trimDiskCacheIfNeededLocked() {
        let files = cacheFilesLocked()
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalBytes > Int64(diskCapacityBytes) else { return }

        for file in files.sorted(by: { $0.modificationDate < $1.modificationDate }) {
            try? FileManager.default.removeItem(at: file.url)
            totalBytes -= file.byteCount
            if totalBytes <= Int64(diskCapacityBytes) {
                break
            }
        }
    }

    private nonisolated static func diskUsageBytesLocked() -> Int64 {
        cacheFilesLocked().reduce(Int64(0)) { $0 + $1.byteCount }
    }

    private nonisolated static func cacheFilesLocked() -> [DiskCacheFile] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return DiskCacheFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private nonisolated struct DiskCacheFile {
        let url: URL
        let byteCount: Int64
        let modificationDate: Date
    }

}

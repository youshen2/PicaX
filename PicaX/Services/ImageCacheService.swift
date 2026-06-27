import Foundation

struct ImageCacheUsage: Equatable {
    let memoryBytes: Int
    let diskBytes: Int

    var totalBytes: Int {
        memoryBytes + diskBytes
    }
}

enum ImageCacheService {
    nonisolated static let defaultMaxDiskSizeMB = 400

    @MainActor
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: ImageCacheSettingsKey.maxDiskSizeMB) == nil {
            defaults.set(defaultMaxDiskSizeMB, forKey: ImageCacheSettingsKey.maxDiskSizeMB)
        }

        let storedSize = defaults.integer(forKey: ImageCacheSettingsKey.maxDiskSizeMB)
        let diskCapacity = max(storedSize, 50) * 1024 * 1024
        let memoryCapacity = min(max(diskCapacity / 4, 16 * 1024 * 1024), 128 * 1024 * 1024)
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
    }

    @MainActor
    static func clear() {
        URLCache.shared.removeAllCachedResponses()
    }

    @MainActor
    static var usage: ImageCacheUsage {
        ImageCacheUsage(
            memoryBytes: URLCache.shared.currentMemoryUsage,
            diskBytes: URLCache.shared.currentDiskUsage
        )
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

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request) {
            return cachedResponse.data
        }

        let (data, response) = storesInCache
            ? try await URLSession.shared.data(for: request)
            : try await uncachedData(for: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        if storesInCache {
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        }
        return data
    }

    private nonisolated static func uncachedData(for url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    private nonisolated static func localFileData(for fileURL: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: fileURL)
        }.value
    }
}

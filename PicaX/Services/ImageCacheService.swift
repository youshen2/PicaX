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
    nonisolated(unsafe) private static let uncachedSession: URLSession = {
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

        let request = cacheRequest(for: url)
        if storesInCache, let cachedResponse = URLCache.shared.cachedResponse(for: request) {
            return cachedResponse.data
        }

        let (data, response) = try await uncachedData(for: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    nonisolated static func storeDecodedImageData(_ data: Data, for url: URL) {
        guard url.picaxLocalFileURL == nil, url.picaxSupportsURLCache, !data.isEmpty else {
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: nil,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        URLCache.shared.storeCachedResponse(
            CachedURLResponse(response: response, data: data),
            for: cacheRequest(for: url)
        )
    }

    nonisolated static func removeCachedImageData(for url: URL) {
        guard url.picaxSupportsURLCache else { return }
        URLCache.shared.removeCachedResponse(for: cacheRequest(for: url))
    }

    nonisolated static func prefetchImageData(for url: URL) async throws {
        let data = try await data(for: url)
        guard isDecodableImageData(data) else {
            removeCachedImageData(for: url)
            throw URLError(.cannotDecodeContentData)
        }
        storeDecodedImageData(data, for: url)
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

    private nonisolated static func cacheRequest(for url: URL) -> URLRequest {
        URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
    }

    private nonisolated static func isDecodableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

}

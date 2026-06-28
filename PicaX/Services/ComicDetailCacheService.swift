import CryptoKit
import Foundation

struct ComicDetailCacheUsage: Equatable {
    let diskBytes: Int
}

enum ComicDetailCacheService {
    nonisolated static let defaultMaxDiskSizeMB = 50
    private nonisolated static let minimumDiskSizeMB = 5
    private nonisolated static let cacheFormatVersion = 1
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var diskCapacityBytes = defaultMaxDiskSizeMB * 1024 * 1024

    @MainActor
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: DetailCacheSettingsKey.isEnabled) == nil {
            defaults.set(true, forKey: DetailCacheSettingsKey.isEnabled)
        }
        if defaults.object(forKey: DetailCacheSettingsKey.maxDiskSizeMB) == nil {
            defaults.set(defaultMaxDiskSizeMB, forKey: DetailCacheSettingsKey.maxDiskSizeMB)
        }

        let storedSize = defaults.integer(forKey: DetailCacheSettingsKey.maxDiskSizeMB)
        let diskCapacity = max(storedSize, minimumDiskSizeMB) * 1024 * 1024
        withDiskCacheLock {
            diskCapacityBytes = diskCapacity
            prepareDiskCacheDirectoryLocked()
            trimDiskCacheIfNeededLocked()
        }
    }

    @MainActor
    static func clear() {
        withDiskCacheLock {
            let directoryURL = cacheDirectoryURL
            try? FileManager.default.removeItem(at: directoryURL)
            prepareDiskCacheDirectoryLocked()
        }
    }

    @MainActor
    static var usage: ComicDetailCacheUsage {
        withDiskCacheLock {
            ComicDetailCacheUsage(diskBytes: Int(min(diskUsageBytesLocked(), Int64(Int.max))))
        }
    }

    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DetailCacheSettingsKey.isEnabled) == nil
            ? true
            : defaults.bool(forKey: DetailCacheSettingsKey.isEnabled)
    }

    nonisolated static func detail(for item: ComicListItem, account: PlatformAccount?) async -> ComicDetailInfo? {
        guard isEnabled() else { return nil }
        return await Task.detached(priority: .utility) {
            diskCachedDetail(for: item, account: account)
        }.value
    }

    nonisolated static func store(_ detail: ComicDetailInfo, account: PlatformAccount?) async {
        guard isEnabled() else { return }
        await Task.detached(priority: .utility) {
            storeDetailOnDisk(cacheableDetail(detail), account: account)
        }.value
    }

    nonisolated static func removeCachedDetail(for item: ComicListItem, account: PlatformAccount?) {
        withDiskCacheLock {
            try? FileManager.default.removeItem(at: cacheFileURL(for: item, account: account))
        }
    }

    private nonisolated static func diskCachedDetail(for item: ComicListItem, account: PlatformAccount?) -> ComicDetailInfo? {
        withDiskCacheLock {
            let fileURL = cacheFileURL(for: item, account: account)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let payload = try? JSONDecoder().decode(CachedComicDetail.self, from: data),
                  payload.version == cacheFormatVersion else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            touchCacheFileLocked(fileURL)
            return payload.detail
        }
    }

    private nonisolated static func storeDetailOnDisk(_ detail: ComicDetailInfo, account: PlatformAccount?) {
        guard let data = try? JSONEncoder().encode(CachedComicDetail(version: cacheFormatVersion, cachedAt: Date(), detail: detail)) else {
            return
        }
        withDiskCacheLock {
            prepareDiskCacheDirectoryLocked()
            let fileURL = cacheFileURL(for: detail.item, account: account)
            try? data.write(to: fileURL, options: [.atomic])
            touchCacheFileLocked(fileURL)
            trimDiskCacheIfNeededLocked()
        }
    }

    private nonisolated static func cacheableDetail(_ detail: ComicDetailInfo) -> ComicDetailInfo {
        ComicDetailInfo(
            item: detail.item,
            description: detail.description,
            tagGroups: detail.tagGroups,
            chapters: [],
            related: [],
            updatedText: detail.updatedText,
            isLiked: detail.isLiked,
            uploader: detail.item.platform == .picacg ? nil : detail.uploader
        )
    }

    private nonisolated static func withDiskCacheLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private nonisolated static var cacheDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("ComicDetailCache", isDirectory: true)
    }

    private nonisolated static func cacheFileURL(for item: ComicListItem, account: PlatformAccount?) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey(for: item, account: account).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectoryURL.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private nonisolated static func cacheKey(for item: ComicListItem, account: PlatformAccount?) -> String {
        let accountKey: String
        if let account {
            accountKey = [
                account.platform.rawValue,
                account.username,
                account.credential.profile?.username ?? "",
                account.credential.baseURL ?? ""
            ].joined(separator: "|")
        } else {
            accountKey = "anonymous"
        }
        return "\(item.platform.rawValue)|\(item.id)|\(accountKey)"
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

    private nonisolated struct CachedComicDetail: Codable {
        let version: Int
        let cachedAt: Date
        let detail: ComicDetailInfo
    }

    private nonisolated struct DiskCacheFile {
        let url: URL
        let byteCount: Int64
        let modificationDate: Date
    }
}

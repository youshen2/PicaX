import CryptoKit
import Foundation

struct WatchDetailCacheUsage: Equatable {
    let diskBytes: Int64

    var formatted: String {
        WatchStorageFormatter.formattedSize(diskBytes)
    }
}

enum WatchComicDetailCacheService {
    nonisolated static let defaultMaxDiskSizeMB = 20

    @MainActor
    static func configure(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: WatchSettingsKey.detailCacheMaxDiskSizeMB) == nil {
            defaults.set(defaultMaxDiskSizeMB, forKey: WatchSettingsKey.detailCacheMaxDiskSizeMB)
        }
        trimIfNeeded(maxBytes: maxDiskSizeBytes(defaults: defaults))
    }

    static func detail(for item: WatchComicItem) async -> WatchComicDetailInfo? {
        guard UserDefaults.standard.object(forKey: WatchSettingsKey.detailCacheEnabled) == nil ||
                UserDefaults.standard.bool(forKey: WatchSettingsKey.detailCacheEnabled) else {
            return nil
        }
        let fileURL = cacheFileURL(for: item)
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(WatchComicDetailCacheEntry.self, from: data) else {
            return nil
        }
        return entry.detail
    }

    static func store(_ detail: WatchComicDetailInfo) async {
        guard UserDefaults.standard.object(forKey: WatchSettingsKey.detailCacheEnabled) == nil ||
                UserDefaults.standard.bool(forKey: WatchSettingsKey.detailCacheEnabled) else {
            return
        }
        prepareDirectory()
        let entry = WatchComicDetailCacheEntry(detail: detail, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: cacheFileURL(for: detail.item), options: .atomic)
        trimIfNeeded(maxBytes: maxDiskSizeBytes(defaults: .standard))
    }

    @MainActor
    static func clear() {
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
        prepareDirectory()
    }

    @MainActor
    static var usage: WatchDetailCacheUsage {
        WatchDetailCacheUsage(diskBytes: directorySize(at: cacheDirectoryURL))
    }

    private static func cacheFileURL(for item: WatchComicItem) -> URL {
        let key = "\(item.platform.id)-\(item.id)"
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectoryURL.appendingPathComponent("\(digest).json")
    }

    private static var cacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WatchDetailCache", isDirectory: true)
    }

    private static func prepareDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private static func maxDiskSizeBytes(defaults: UserDefaults) -> Int {
        let maxMB = defaults.object(forKey: WatchSettingsKey.detailCacheMaxDiskSizeMB) == nil
            ? defaultMaxDiskSizeMB
            : defaults.integer(forKey: WatchSettingsKey.detailCacheMaxDiskSizeMB)
        return max(maxMB, 5) * 1024 * 1024
    }

    private static func trimIfNeeded(maxBytes: Int) {
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

    private static func cacheFiles() -> [WatchDiskFile] {
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

    private static func directorySize(at rootURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
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
}

private struct WatchComicDetailCacheEntry: Codable {
    let detail: WatchComicDetailInfo
    let updatedAt: Date
}

import Combine
import Foundation

struct FollowUpdateRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var item: ComicListItem
    var fingerprint: String?
    var hasNewUpdate: Bool
    var lastCheckDate: Date?
    var lastUpdateDate: Date?
    var errorMessage: String?

    nonisolated init(item: ComicListItem) {
        id = item.readingHistoryID
        self.item = item
        fingerprint = nil
        hasNewUpdate = false
        lastCheckDate = nil
        lastUpdateDate = nil
        errorMessage = nil
    }
}

enum FollowUpdateCheckFrequency: String, CaseIterable, Identifiable, Sendable {
    case hourly
    case everySixHours
    case everyTwelveHours
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly:
            "每小时最多一次"
        case .everySixHours:
            "每 6 小时最多一次"
        case .everyTwelveHours:
            "每 12 小时最多一次"
        case .daily:
            "每天最多一次"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .hourly:
            60 * 60
        case .everySixHours:
            6 * 60 * 60
        case .everyTwelveHours:
            12 * 60 * 60
        case .daily:
            24 * 60 * 60
        }
    }
}

struct FollowUpdateProgress: Equatable, Sendable {
    let total: Int
    let completed: Int
    let updated: Int
    let errors: Int

    static let idle = FollowUpdateProgress(total: 0, completed: 0, updated: 0, errors: 0)

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

@MainActor
final class FollowUpdatesService: ObservableObject {
    enum Key {
        static let isEnabled = "settings.followUpdates.isEnabled"
        static let checkFrequency = "settings.followUpdates.checkFrequency"
    }

    @Published private(set) var records: [FollowUpdateRecord] = []
    @Published private(set) var isChecking = false
    @Published private(set) var progress = FollowUpdateProgress.idle

    private let defaults: UserDefaults
    private let contentService: ComicContentService
    private var checkTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var accountProvider: ((ComicPlatform) -> PlatformAccount?)?

    init(defaults: UserDefaults = .standard, contentService: ComicContentService = ComicContentService()) {
        self.defaults = defaults
        self.contentService = contentService
        reload()
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Key.isEnabled)
    }

    var checkFrequency: FollowUpdateCheckFrequency {
        guard let rawValue = defaults.string(forKey: Key.checkFrequency) else { return .daily }
        return FollowUpdateCheckFrequency(rawValue: rawValue) ?? .daily
    }

    var updatedRecords: [FollowUpdateRecord] {
        records.filter(\.hasNewUpdate)
    }

    var updatedCount: Int {
        updatedRecords.count
    }

    func configure(accountProvider: @escaping (ComicPlatform) -> PlatformAccount?) {
        self.accountProvider = accountProvider
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                self?.checkAutomaticallyIfNeeded()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.isEnabled)
        objectWillChange.send()
        if enabled {
            checkNow(force: true)
        } else {
            cancelCheck()
        }
    }

    func setCheckFrequency(_ frequency: FollowUpdateCheckFrequency) {
        defaults.set(frequency.rawValue, forKey: Key.checkFrequency)
        objectWillChange.send()
        if isEnabled {
            checkAutomaticallyIfNeeded()
        }
    }

    func reload() {
        records = PicaXSQLiteStore.loadFollowUpdateRecords()
        synchronizeWithFavorites()
    }

    func checkAutomaticallyIfNeeded() {
        guard isEnabled else { return }
        checkNow(force: false)
    }

    func checkNow(force: Bool = true) {
        guard isEnabled, !isChecking else { return }
        checkTask = Task { [weak self] in
            await self?.runCheck(force: force)
        }
    }

    func cancelCheck() {
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
    }

    func markAsRead(item: ComicListItem) {
        guard let index = records.firstIndex(where: { $0.id == item.readingHistoryID }),
              records[index].hasNewUpdate else { return }
        records[index].hasNewUpdate = false
        persist()
    }

    func markAllAsRead() {
        guard records.contains(where: \.hasNewUpdate) else { return }
        for index in records.indices {
            records[index].hasNewUpdate = false
        }
        persist()
    }

    private func synchronizeWithFavorites() {
        let favorites = PicaXSQLiteStore.loadLocalFavorites(folderID: "default").map(\.item)
        let favoriteIDs = Set(favorites.map(\.readingHistoryID))
        var existing = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        records = favorites.map { item in
            var record = existing.removeValue(forKey: item.readingHistoryID) ?? FollowUpdateRecord(item: item)
            record.item = item
            return record
        }
        .filter { favoriteIDs.contains($0.id) }
        sortRecords()
    }

    private func runCheck(force: Bool) async {
        synchronizeWithFavorites()
        let cutoff = Date().addingTimeInterval(-checkFrequency.interval)
        let targetIDs = records
            .filter { force || $0.lastCheckDate == nil || $0.lastCheckDate! < cutoff }
            .map(\.id)

        isChecking = true
        progress = FollowUpdateProgress(total: targetIDs.count, completed: 0, updated: 0, errors: 0)
        defer {
            isChecking = false
            checkTask = nil
        }

        for id in targetIDs {
            guard !Task.isCancelled,
                  let index = records.firstIndex(where: { $0.id == id }) else { break }
            let oldRecord = records[index]
            do {
                let detail = try await loadDetailWithRetry(item: oldRecord.item)
                try Task.checkCancellation()
                let fingerprint = Self.fingerprint(for: detail)
                let changed = oldRecord.fingerprint != nil && oldRecord.fingerprint != fingerprint
                var record = oldRecord
                record.item = Self.favoriteItem(from: detail.item, favoriteDate: oldRecord.item.favoriteDate)
                record.fingerprint = fingerprint
                record.hasNewUpdate = oldRecord.hasNewUpdate || changed
                record.lastCheckDate = Date()
                record.errorMessage = nil
                record.lastUpdateDate = changed ? Date() : oldRecord.lastUpdateDate
                records[index] = record
                PicaXSQLiteStore.upsertLocalFavorite(
                    StoredLocalFavorite(item: record.item, favoriteDate: record.item.favoriteDate),
                    folderID: "default",
                    notify: false
                )
                progress = FollowUpdateProgress(
                    total: progress.total,
                    completed: progress.completed + 1,
                    updated: progress.updated + (changed ? 1 : 0),
                    errors: progress.errors
                )
            } catch where error.isTaskCancellation {
                break
            } catch {
                records[index].lastCheckDate = Date()
                records[index].errorMessage = error.localizedDescription
                progress = FollowUpdateProgress(
                    total: progress.total,
                    completed: progress.completed + 1,
                    updated: progress.updated,
                    errors: progress.errors + 1
                )
            }
            persist()
        }
        sortRecords()
        persist()
        if !targetIDs.isEmpty {
            NotificationCenter.default.post(name: .picaxLocalFavoritesDidChange, object: nil)
        }
    }

    private func loadDetailWithRetry(item: ComicListItem) async throws -> ComicDetailInfo {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await contentService.loadDetail(item: item, account: accountProvider?(item.platform))
            } catch where error.isTaskCancellation {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError ?? FollowUpdatesError.checkFailed
    }

    private func persist() {
        PicaXSQLiteStore.replaceFollowUpdateRecords(records)
    }

    private func sortRecords() {
        records.sort {
            if $0.hasNewUpdate != $1.hasNewUpdate { return $0.hasNewUpdate }
            return ($0.lastUpdateDate ?? $0.lastCheckDate ?? .distantPast) > ($1.lastUpdateDate ?? $1.lastCheckDate ?? .distantPast)
        }
    }

    nonisolated private static func fingerprint(for detail: ComicDetailInfo) -> String {
        let updateText = detail.updatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chapters = detail.chapters.map { "\($0.id)|\($0.title)|\($0.subtitle ?? "")" }.joined(separator: "\n")
        return "\(updateText)\n\(chapters)"
    }

    nonisolated private static func favoriteItem(from item: ComicListItem, favoriteDate: Date?) -> ComicListItem {
        ComicListItem(
            id: item.id,
            platform: item.platform,
            title: item.title,
            subtitle: item.subtitle,
            coverURLString: item.coverURLString,
            tags: item.tags,
            pageCount: item.pageCount,
            likesCount: item.likesCount,
            favoriteDate: favoriteDate
        )
    }
}

private enum FollowUpdatesError: LocalizedError {
    case checkFailed

    var errorDescription: String? { "检查更新失败" }
}

import Foundation

struct WatchReadingHistoryStore {
    private static let defaultsKey = "picax.watch.readingHistory.records"
    private static let deletionsKey = "picax.watch.readingHistory.deletions"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [WatchReadingHistoryRecord] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let records = try? JSONDecoder().decode([WatchReadingHistoryRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.viewedAt > $1.viewedAt }
    }

    func latest(limit: Int) -> [WatchReadingHistoryRecord] {
        Array(load().prefix(max(limit, 0)))
    }

    func loadDeletions() -> [WatchReadingHistoryDeletion] {
        guard let data = defaults.data(forKey: Self.deletionsKey),
              let values = try? JSONDecoder().decode([WatchReadingHistoryDeletion].self, from: data) else {
            return []
        }
        return TimestampedSyncMerge.deletions(values, id: \.syncID, deletedAt: \.deletedAt)
    }

    @discardableResult
    func merge(
        _ incoming: [WatchReadingHistoryRecord],
        deletions incomingDeletions: [WatchReadingHistoryDeletion] = []
    ) -> [WatchReadingHistoryRecord] {
        let deletions = mergeDeletions(incomingDeletions)
        let records = TimestampedSyncMerge.items(
            existing: load(),
            incoming: incoming,
            deletions: deletions,
            itemID: \.id,
            itemDate: \.viewedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        .sorted { $0.viewedAt > $1.viewedAt }
        let limitedRecords = Array(records.prefix(120))
        save(limitedRecords)
        return limitedRecords
    }

    @discardableResult
    func mergeDeletions(
        _ incoming: [WatchReadingHistoryDeletion]
    ) -> [WatchReadingHistoryDeletion] {
        let values = TimestampedSyncMerge.deletions(
            loadDeletions() + incoming,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        saveDeletions(values)
        return values
    }

    func record(for item: WatchComicItem) -> WatchReadingHistoryRecord? {
        load().first { $0.id == "\(item.platform.id)-\(item.id)" }
    }

    func record(
        item: WatchComicItem,
        chapterIndex: Int,
        pageIndex: Int,
        totalPages: Int,
        totalChapters: Int
    ) {
        var records = load()
        let id = "\(item.platform.id)-\(item.id)"
        saveDeletions(loadDeletions().filter { $0.syncID != id })
        records.removeAll { $0.id == id }
        records.insert(
            WatchReadingHistoryRecord(
                comicID: item.id,
                platformID: item.platform.id,
                title: item.title,
                subtitle: item.subtitle,
                coverURLString: item.coverURLString,
                tags: item.tags,
                pageCount: item.pageCount,
                favoriteDate: item.favoriteDate,
                viewedAt: Date(),
                progress: WatchReadingProgress(
                    chapterIndex: max(chapterIndex, 0),
                    pageIndex: max(pageIndex, 0),
                    totalPages: max(totalPages, 0),
                    totalChapters: max(totalChapters, 1)
                )
            ),
            at: 0
        )
        records = Array(records.prefix(120))
        save(records)
    }

    func remove(_ record: WatchReadingHistoryRecord) {
        mergeDeletions([
            WatchReadingHistoryDeletion(syncID: record.id, deletedAt: Date())
        ])
        save(load().filter { $0.id != record.id })
    }

    func clear() {
        mergeDeletions(load().map {
            WatchReadingHistoryDeletion(syncID: $0.id, deletedAt: Date())
        })
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func save(_ records: [WatchReadingHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func saveDeletions(_ values: [WatchReadingHistoryDeletion]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.deletionsKey)
    }
}

extension WatchReadingHistoryRecord {
    var item: WatchComicItem {
        WatchComicItem(
            id: comicID,
            platform: WatchComicPlatform(rawValue: platformID) ?? .picacg,
            title: title,
            subtitle: subtitle,
            coverURLString: coverURLString,
            tags: tags,
            pageCount: pageCount,
            favoriteDate: favoriteDate
        )
    }
}

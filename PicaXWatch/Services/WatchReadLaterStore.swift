import Foundation

struct WatchReadLaterStore {
    private static let defaultsKey = "picax.watch.readLater"
    private static let deletionsKey = "picax.watch.readLater.deletions"

    func load() -> [WatchReadLaterItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let items = try? JSONDecoder().decode([WatchReadLaterItem].self, from: data) else {
            return []
        }
        return sorted(items)
    }

    func loadDeletions() -> [WatchReadLaterDeletion] {
        guard let data = UserDefaults.standard.data(forKey: Self.deletionsKey),
              let deletions = try? JSONDecoder().decode([WatchReadLaterDeletion].self, from: data) else {
            return []
        }
        return TimestampedSyncMerge.deletions(
            deletions,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
    }

    func contains(_ item: WatchComicItem) -> Bool {
        load().contains { $0.syncID == WatchReadLaterItem(item: item).syncID }
    }

    func replace(_ items: [WatchReadLaterItem]) {
        persist(sorted(deduplicated(items)))
    }

    @discardableResult
    func merge(
        _ incoming: [WatchReadLaterItem],
        deletions incomingDeletions: [WatchReadLaterDeletion] = []
    ) -> [WatchReadLaterItem] {
        let deletions = mergeDeletions(incomingDeletions)
        let merged = merge(existing: load(), incoming: incoming, deletions: deletions)
        replace(merged)
        return merged
    }

    @discardableResult
    func mergeDeletions(_ incoming: [WatchReadLaterDeletion]) -> [WatchReadLaterDeletion] {
        let merged = TimestampedSyncMerge.deletions(
            loadDeletions() + incoming,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        persistDeletions(merged)
        return merged
    }

    @discardableResult
    func add(_ item: WatchComicItem) -> [WatchReadLaterItem] {
        let readLater = WatchReadLaterItem(item: item)
        removeDeletion(syncID: readLater.syncID)
        return merge([readLater])
    }

    @discardableResult
    func remove(_ item: WatchComicItem) -> [WatchReadLaterItem] {
        let readLater = WatchReadLaterItem(item: item)
        return remove(syncID: readLater.syncID)
    }

    @discardableResult
    func remove(syncID: String) -> [WatchReadLaterItem] {
        let deletion = WatchReadLaterDeletion(syncID: syncID, deletedAt: Date())
        mergeDeletions([deletion])
        let remaining = load().filter { $0.syncID != syncID }
        replace(remaining)
        return remaining
    }

    private func removeDeletion(syncID: String) {
        let deletions = loadDeletions().filter { $0.syncID != syncID }
        persistDeletions(deletions)
    }

    private func merge(
        existing: [WatchReadLaterItem],
        incoming: [WatchReadLaterItem],
        deletions: [WatchReadLaterDeletion]
    ) -> [WatchReadLaterItem] {
        sorted(TimestampedSyncMerge.items(
            existing: existing,
            incoming: incoming,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: \.addedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        ))
    }

    private func deduplicated(_ items: [WatchReadLaterItem]) -> [WatchReadLaterItem] {
        var result: [String: WatchReadLaterItem] = [:]
        for item in items {
            if let old = result[item.syncID] {
                result[item.syncID] = newer(old, item)
            } else {
                result[item.syncID] = item
            }
        }
        return sorted(Array(result.values))
    }

    private func newer(_ lhs: WatchReadLaterItem, _ rhs: WatchReadLaterItem) -> WatchReadLaterItem {
        rhs.addedAt >= lhs.addedAt ? rhs : lhs
    }

    private func sorted(_ items: [WatchReadLaterItem]) -> [WatchReadLaterItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    private func persist(_ items: [WatchReadLaterItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func persistDeletions(_ deletions: [WatchReadLaterDeletion]) {
        guard let data = try? JSONEncoder().encode(deletions) else { return }
        UserDefaults.standard.set(data, forKey: Self.deletionsKey)
    }
}

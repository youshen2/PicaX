import Foundation

struct WatchLocalFavoritesStore {
    private static let defaultsKey = "picax.watch.localFavorites.default"
    private static let deletionsKey = "picax.watch.localFavorites.deletions"

    func load() -> [WatchLocalFavoriteItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let items = try? JSONDecoder().decode([WatchLocalFavoriteItem].self, from: data) else {
            return []
        }
        return sorted(items)
    }

    func loadDeletions() -> [WatchLocalFavoriteDeletion] {
        guard let data = UserDefaults.standard.data(forKey: Self.deletionsKey),
              let deletions = try? JSONDecoder().decode([WatchLocalFavoriteDeletion].self, from: data) else {
            return []
        }
        return TimestampedSyncMerge.deletions(
            deletions,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
    }

    func contains(_ item: WatchComicItem) -> Bool {
        load().contains { $0.syncID == WatchLocalFavoriteItem(item: item).syncID }
    }

    func replace(_ items: [WatchLocalFavoriteItem]) {
        persist(sorted(deduplicated(items)))
    }

    @discardableResult
    func merge(
        _ incoming: [WatchLocalFavoriteItem],
        deletions incomingDeletions: [WatchLocalFavoriteDeletion] = []
    ) -> [WatchLocalFavoriteItem] {
        let deletions = mergeDeletions(incomingDeletions)
        let merged = merge(existing: load(), incoming: incoming, deletions: deletions)
        replace(merged)
        return merged
    }

    @discardableResult
    func mergeDeletions(
        _ incoming: [WatchLocalFavoriteDeletion]
    ) -> [WatchLocalFavoriteDeletion] {
        let merged = TimestampedSyncMerge.deletions(
            loadDeletions() + incoming,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        persistDeletions(merged)
        return merged
    }

    @discardableResult
    func add(_ item: WatchComicItem) -> [WatchLocalFavoriteItem] {
        let favorite = WatchLocalFavoriteItem(item: item)
        removeDeletion(syncID: favorite.syncID)
        return merge([favorite])
    }

    @discardableResult
    func remove(_ item: WatchComicItem) -> [WatchLocalFavoriteItem] {
        let favorite = WatchLocalFavoriteItem(item: item)
        return remove(syncID: favorite.syncID)
    }

    @discardableResult
    func remove(syncID: String) -> [WatchLocalFavoriteItem] {
        let deletion = WatchLocalFavoriteDeletion(syncID: syncID, deletedAt: Date())
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
        existing: [WatchLocalFavoriteItem],
        incoming: [WatchLocalFavoriteItem],
        deletions: [WatchLocalFavoriteDeletion]
    ) -> [WatchLocalFavoriteItem] {
        sorted(TimestampedSyncMerge.items(
            existing: existing,
            incoming: incoming,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: { $0.favoriteDate ?? .distantPast },
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        ))
    }

    private func deduplicated(_ items: [WatchLocalFavoriteItem]) -> [WatchLocalFavoriteItem] {
        var result: [String: WatchLocalFavoriteItem] = [:]
        for item in items {
            if let old = result[item.syncID] {
                result[item.syncID] = newer(old, item)
            } else {
                result[item.syncID] = item
            }
        }
        return sorted(Array(result.values))
    }

    private func newer(_ lhs: WatchLocalFavoriteItem, _ rhs: WatchLocalFavoriteItem) -> WatchLocalFavoriteItem {
        let lhsDate = lhs.favoriteDate ?? .distantPast
        let rhsDate = rhs.favoriteDate ?? .distantPast
        return rhsDate >= lhsDate ? rhs : lhs
    }

    private func sorted(_ items: [WatchLocalFavoriteItem]) -> [WatchLocalFavoriteItem] {
        items.sorted {
            ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast)
        }
    }

    private func persist(_ items: [WatchLocalFavoriteItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func persistDeletions(_ deletions: [WatchLocalFavoriteDeletion]) {
        guard let data = try? JSONEncoder().encode(deletions) else { return }
        UserDefaults.standard.set(data, forKey: Self.deletionsKey)
    }
}

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
        return deletions.sorted { $0.deletedAt > $1.deletedAt }
    }

    func contains(_ item: WatchComicItem) -> Bool {
        load().contains { $0.syncID == WatchLocalFavoriteItem(item: item).syncID }
    }

    func replace(_ items: [WatchLocalFavoriteItem]) {
        persist(sorted(deduplicated(items)))
    }

    @discardableResult
    func merge(_ incoming: [WatchLocalFavoriteItem]) -> [WatchLocalFavoriteItem] {
        let merged = merge(existing: load(), incoming: incoming, deletions: loadDeletions())
        replace(merged)
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
        persistDeletions(deduplicatedDeletions(loadDeletions() + [deletion]))
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
        let deletionMap = Dictionary(uniqueKeysWithValues: deletions.map { ($0.syncID, $0.deletedAt) })
        return deduplicated(existing + incoming).filter { item in
            guard let deletedAt = deletionMap[item.syncID] else { return true }
            return (item.favoriteDate ?? .distantPast) > deletedAt
        }
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

    private func deduplicatedDeletions(_ deletions: [WatchLocalFavoriteDeletion]) -> [WatchLocalFavoriteDeletion] {
        var result: [String: WatchLocalFavoriteDeletion] = [:]
        for deletion in deletions {
            if let old = result[deletion.syncID] {
                result[deletion.syncID] = deletion.deletedAt >= old.deletedAt ? deletion : old
            } else {
                result[deletion.syncID] = deletion
            }
        }
        return Array(result.values).sorted { $0.deletedAt > $1.deletedAt }
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

#if os(iOS)
import Foundation

struct PhoneWatchSyncMergeResult<Item, Deletion> {
    var items: [Item]
    var deletions: [Deletion]
}

struct PhoneWatchSyncStateStore {
    private static let defaultsKey = "picax.phone.watchSync.state.v1"

    func reconcileLocalFavorites(
        current: [WatchLocalFavoriteItem],
        incoming: [WatchLocalFavoriteItem] = [],
        incomingDeletions: [WatchLocalFavoriteDeletion] = [],
        now: Date = Date()
    ) -> PhoneWatchSyncMergeResult<WatchLocalFavoriteItem, WatchLocalFavoriteDeletion> {
        let state = load()
        let currentIDs = Set(current.map(\.syncID))
        let inferredDeletions = state.hasInitializedLocalFavorites
            ? state.knownLocalFavoriteIDs.subtracting(currentIDs).map {
                WatchLocalFavoriteDeletion(syncID: $0, deletedAt: now)
            }
            : []

        var deletions = TimestampedSyncMerge.deletions(
            state.localFavoriteDeletions + incomingDeletions + inferredDeletions,
            now: now,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        var items = TimestampedSyncMerge.items(
            existing: current,
            incoming: incoming,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: { $0.favoriteDate ?? .distantPast },
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        deletions = deletions.filter { deletion in
            !items.contains {
                $0.syncID == deletion.syncID
                    && ($0.favoriteDate ?? .distantPast) > deletion.deletedAt
            }
        }
        items = TimestampedSyncMerge.items(
            existing: [],
            incoming: items,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: { $0.favoriteDate ?? .distantPast },
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        .sorted { ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast) }

        return PhoneWatchSyncMergeResult(items: items, deletions: deletions)
    }

    func commitLocalFavorites(
        _ result: PhoneWatchSyncMergeResult<WatchLocalFavoriteItem, WatchLocalFavoriteDeletion>
    ) {
        var state = load()
        state.hasInitializedLocalFavorites = true
        state.knownLocalFavoriteIDs = Set(result.items.map(\.syncID))
        state.localFavoriteDeletions = result.deletions
        persist(state)
    }

    func reconcileReadLater(
        current: [WatchReadLaterItem],
        incoming: [WatchReadLaterItem] = [],
        incomingDeletions: [WatchReadLaterDeletion] = [],
        now: Date = Date()
    ) -> PhoneWatchSyncMergeResult<WatchReadLaterItem, WatchReadLaterDeletion> {
        let state = load()
        let currentIDs = Set(current.map(\.syncID))
        let inferredDeletions = state.hasInitializedReadLater
            ? state.knownReadLaterIDs.subtracting(currentIDs).map {
                WatchReadLaterDeletion(syncID: $0, deletedAt: now)
            }
            : []

        var deletions = TimestampedSyncMerge.deletions(
            state.readLaterDeletions + incomingDeletions + inferredDeletions,
            now: now,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        var items = TimestampedSyncMerge.items(
            existing: current,
            incoming: incoming,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: \.addedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        deletions = deletions.filter { deletion in
            !items.contains { $0.syncID == deletion.syncID && $0.addedAt > deletion.deletedAt }
        }
        items = TimestampedSyncMerge.items(
            existing: [],
            incoming: items,
            deletions: deletions,
            itemID: \.syncID,
            itemDate: \.addedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        .sorted { $0.addedAt > $1.addedAt }

        return PhoneWatchSyncMergeResult(items: items, deletions: deletions)
    }

    func commitReadLater(
        _ result: PhoneWatchSyncMergeResult<WatchReadLaterItem, WatchReadLaterDeletion>
    ) {
        var state = load()
        state.hasInitializedReadLater = true
        state.knownReadLaterIDs = Set(result.items.map(\.syncID))
        state.readLaterDeletions = result.deletions
        persist(state)
    }

    func reconcileReadingHistory(
        current: [WatchReadingHistoryRecord],
        incoming: [WatchReadingHistoryRecord] = [],
        incomingDeletions: [WatchReadingHistoryDeletion] = [],
        now: Date = Date()
    ) -> PhoneWatchSyncMergeResult<WatchReadingHistoryRecord, WatchReadingHistoryDeletion> {
        let state = load()
        let currentIDs = Set(current.map(\.id))
        let inferredDeletions = state.hasInitializedReadingHistory
            ? state.knownReadingHistoryIDs.subtracting(currentIDs).map {
                WatchReadingHistoryDeletion(syncID: $0, deletedAt: now)
            }
            : []

        var deletions = TimestampedSyncMerge.deletions(
            state.readingHistoryDeletions + incomingDeletions + inferredDeletions,
            now: now,
            id: \.syncID,
            deletedAt: \.deletedAt
        )
        var items = TimestampedSyncMerge.items(
            existing: current,
            incoming: incoming,
            deletions: deletions,
            itemID: \.id,
            itemDate: \.viewedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        deletions = deletions.filter { deletion in
            !items.contains { $0.id == deletion.syncID && $0.viewedAt > deletion.deletedAt }
        }
        items = TimestampedSyncMerge.items(
            existing: [],
            incoming: items,
            deletions: deletions,
            itemID: \.id,
            itemDate: \.viewedAt,
            deletionID: \.syncID,
            deletedAt: \.deletedAt
        )
        .sorted { $0.viewedAt > $1.viewedAt }

        return PhoneWatchSyncMergeResult(items: items, deletions: deletions)
    }

    func commitReadingHistory(
        _ result: PhoneWatchSyncMergeResult<WatchReadingHistoryRecord, WatchReadingHistoryDeletion>
    ) {
        var state = load()
        state.hasInitializedReadingHistory = true
        state.knownReadingHistoryIDs = Set(result.items.map(\.id))
        state.readingHistoryDeletions = result.deletions
        persist(state)
    }

    private func load() -> PhoneWatchSyncState {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(PhoneWatchSyncState.self, from: data) else {
            return PhoneWatchSyncState()
        }
        return state
    }

    private func persist(_ state: PhoneWatchSyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

private struct PhoneWatchSyncState: Codable {
    var hasInitializedLocalFavorites = false
    var hasInitializedReadLater = false
    var hasInitializedReadingHistory = false
    var knownLocalFavoriteIDs: Set<String> = []
    var knownReadLaterIDs: Set<String> = []
    var knownReadingHistoryIDs: Set<String> = []
    var localFavoriteDeletions: [WatchLocalFavoriteDeletion] = []
    var readLaterDeletions: [WatchReadLaterDeletion] = []
    var readingHistoryDeletions: [WatchReadingHistoryDeletion] = []
}
#endif

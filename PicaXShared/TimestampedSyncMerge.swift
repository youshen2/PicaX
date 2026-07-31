import Foundation

enum TimestampedSyncMerge {
    nonisolated static let tombstoneRetention: TimeInterval = 30 * 24 * 60 * 60

    nonisolated static func deletions<Deletion>(
        _ values: [Deletion],
        now: Date = Date(),
        id: (Deletion) -> String,
        deletedAt: (Deletion) -> Date
    ) -> [Deletion] {
        let cutoff = now.addingTimeInterval(-tombstoneRetention)
        var latest: [String: Deletion] = [:]
        for value in values where deletedAt(value) >= cutoff {
            let key = id(value)
            if let old = latest[key], deletedAt(old) >= deletedAt(value) {
                continue
            }
            latest[key] = value
        }
        return latest.values.sorted { deletedAt($0) > deletedAt($1) }
    }

    nonisolated static func items<Item, Deletion>(
        existing: [Item],
        incoming: [Item],
        deletions: [Deletion],
        itemID: (Item) -> String,
        itemDate: (Item) -> Date,
        deletionID: (Deletion) -> String,
        deletedAt: (Deletion) -> Date
    ) -> [Item] {
        var tombstones: [String: Date] = [:]
        for deletion in deletions {
            tombstones[deletionID(deletion)] = max(
                tombstones[deletionID(deletion)] ?? .distantPast,
                deletedAt(deletion)
            )
        }

        var latest: [String: Item] = [:]
        for item in existing + incoming {
            let key = itemID(item)
            guard (tombstones[key] ?? .distantPast) < itemDate(item) else {
                continue
            }
            if let old = latest[key], itemDate(old) > itemDate(item) {
                continue
            }
            latest[key] = item
        }
        return Array(latest.values)
    }
}

import XCTest
@testable import PicaX

final class TimestampedSyncMergeTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
        let updatedAt: Date
        let value: String
    }

    private struct Deletion: Equatable {
        let id: String
        let deletedAt: Date
    }

    func testOlderDeletedDuplicateDoesNotRemoveNewerResurrection() {
        let deletionDate = Date(timeIntervalSince1970: 1_000)
        let resurrected = Item(
            id: "comic",
            updatedAt: deletionDate.addingTimeInterval(10),
            value: "new"
        )
        let stale = Item(
            id: "comic",
            updatedAt: deletionDate.addingTimeInterval(-10),
            value: "old"
        )

        let result = TimestampedSyncMerge.items(
            existing: [resurrected],
            incoming: [stale],
            deletions: [Deletion(id: "comic", deletedAt: deletionDate)],
            itemID: \.id,
            itemDate: \.updatedAt,
            deletionID: \.id,
            deletedAt: \.deletedAt
        )

        XCTAssertEqual(result, [resurrected])
    }

    func testDeletionWinsWhenTimestampMatchesItem() {
        let date = Date(timeIntervalSince1970: 2_000)
        let result = TimestampedSyncMerge.items(
            existing: [Item(id: "comic", updatedAt: date, value: "same time")],
            incoming: [],
            deletions: [Deletion(id: "comic", deletedAt: date)],
            itemID: \.id,
            itemDate: \.updatedAt,
            deletionID: \.id,
            deletedAt: \.deletedAt
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testDeletionCompactionKeepsNewestAndPrunesExpiredTombstones() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let recent = now.addingTimeInterval(-60)
        let olderDuplicate = now.addingTimeInterval(-120)
        let expired = now.addingTimeInterval(-TimestampedSyncMerge.tombstoneRetention - 1)

        let result = TimestampedSyncMerge.deletions(
            [
                Deletion(id: "comic", deletedAt: olderDuplicate),
                Deletion(id: "comic", deletedAt: recent),
                Deletion(id: "expired", deletedAt: expired)
            ],
            now: now,
            id: \.id,
            deletedAt: \.deletedAt
        )

        XCTAssertEqual(result, [Deletion(id: "comic", deletedAt: recent)])
    }
}

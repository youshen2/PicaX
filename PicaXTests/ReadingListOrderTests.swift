import XCTest
@testable import PicaX

final class ReadingListOrderTests: XCTestCase {
    private struct Entry: Identifiable, Equatable {
        let id: Int
    }

    private let sourceIndexes = [1: 0, 2: 1, 3: 2, 4: 3]

    func testAscendingRestoresSourceOrder() {
        let entries = [Entry(id: 3), Entry(id: 1), Entry(id: 4), Entry(id: 2)]

        let ordered = ReadingListOrder.ascending.ordered(entries, sourceIndexes: sourceIndexes)

        XCTAssertEqual(ordered.map(\.id), [1, 2, 3, 4])
    }

    func testDescendingReversesSourceOrder() {
        let entries = [Entry(id: 3), Entry(id: 1), Entry(id: 4), Entry(id: 2)]

        let ordered = ReadingListOrder.descending.ordered(entries, sourceIndexes: sourceIndexes)

        XCTAssertEqual(ordered.map(\.id), [4, 3, 2, 1])
    }

    func testRandomPreservesEntriesAndChangesVisibleOrder() {
        let entries = [Entry(id: 1), Entry(id: 2), Entry(id: 3), Entry(id: 4)]

        let ordered = ReadingListOrder.random.ordered(entries, sourceIndexes: sourceIndexes)

        XCTAssertEqual(Set(ordered.map(\.id)), Set(entries.map(\.id)))
        XCTAssertNotEqual(ordered, entries)
    }

    func testOrderingPreservesRemainingEntriesAfterDeletion() {
        let entries = [Entry(id: 4), Entry(id: 2), Entry(id: 1)]

        let ascending = ReadingListOrder.ascending.ordered(entries, sourceIndexes: sourceIndexes)
        let descending = ReadingListOrder.descending.ordered(entries, sourceIndexes: sourceIndexes)

        XCTAssertEqual(ascending.map(\.id), [1, 2, 4])
        XCTAssertEqual(descending.map(\.id), [4, 2, 1])
    }
}

import XCTest
@testable import PicaX

@MainActor
final class ReadingListBurnAfterReadingStateTests: XCTestCase {
    func testRemovalIsAvailableOnlyAfterDestinationLoads() {
        var state = ReadingListBurnAfterReadingState()
        state.prepareRemoval(
            entryID: "first-entry",
            recordID: "first-record",
            hasFinishedCurrentEntry: true,
            isLaterDestination: true,
            isBurnAfterReadingEnabled: true,
            destinationEntryID: "later-entry"
        )

        XCTAssertNil(state.takeRemoval(afterLoading: "unrelated-entry"))
        XCTAssertTrue(state.hasPendingRemoval)

        let removal = state.takeRemoval(afterLoading: "later-entry")
        XCTAssertEqual(
            removal,
            ReadingListBurnAfterReadingState.Removal(
                entryID: "first-entry",
                recordID: "first-record",
                destinationEntryID: "later-entry"
            )
        )
        XCTAssertFalse(state.hasPendingRemoval)
    }

    func testFailedDestinationLoadCancelsRemoval() {
        var state = ReadingListBurnAfterReadingState()
        state.prepareRemoval(
            entryID: "first-entry",
            recordID: "first-record",
            hasFinishedCurrentEntry: true,
            isLaterDestination: true,
            isBurnAfterReadingEnabled: true,
            destinationEntryID: "second-entry"
        )

        state.cancelRemoval(afterFailingToLoad: "second-entry")

        XCTAssertFalse(state.hasPendingRemoval)
        XCTAssertNil(state.takeRemoval(afterLoading: "second-entry"))
    }

    func testUnfinishedEntryDoesNotPrepareRemoval() {
        var state = ReadingListBurnAfterReadingState()

        state.prepareRemoval(
            entryID: "first-entry",
            recordID: "first-record",
            hasFinishedCurrentEntry: false,
            isLaterDestination: true,
            isBurnAfterReadingEnabled: true,
            destinationEntryID: "second-entry"
        )

        XCTAssertFalse(state.hasPendingRemoval)
    }

    func testEarlierDestinationDoesNotPrepareRemoval() {
        var state = ReadingListBurnAfterReadingState()

        state.prepareRemoval(
            entryID: "second-entry",
            recordID: "second-record",
            hasFinishedCurrentEntry: true,
            isLaterDestination: false,
            isBurnAfterReadingEnabled: true,
            destinationEntryID: "first-entry"
        )

        XCTAssertFalse(state.hasPendingRemoval)
    }

    func testDisabledBurnAfterReadingDoesNotPrepareRemoval() {
        var state = ReadingListBurnAfterReadingState()

        state.prepareRemoval(
            entryID: "first-entry",
            recordID: "first-record",
            hasFinishedCurrentEntry: true,
            isLaterDestination: true,
            isBurnAfterReadingEnabled: false,
            destinationEntryID: "second-entry"
        )

        XCTAssertFalse(state.hasPendingRemoval)
    }

    func testOnlineEntryDoesNotPrepareRemoval() {
        var state = ReadingListBurnAfterReadingState()

        state.prepareRemoval(
            entryID: "first-entry",
            recordID: nil,
            hasFinishedCurrentEntry: true,
            isLaterDestination: true,
            isBurnAfterReadingEnabled: true,
            destinationEntryID: "second-entry"
        )

        XCTAssertFalse(state.hasPendingRemoval)
    }
}

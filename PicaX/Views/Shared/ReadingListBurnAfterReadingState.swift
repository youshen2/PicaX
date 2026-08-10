struct ReadingListBurnAfterReadingState {
    struct Removal: Equatable {
        let entryID: String
        let recordID: String
        let destinationEntryID: String
    }

    var isEnabled = false
    private var pendingRemoval: Removal?

    var hasPendingRemoval: Bool {
        pendingRemoval != nil
    }

    mutating func prepareRemoval(
        entryID: String,
        recordID: String?,
        hasFinishedCurrentEntry: Bool,
        isLaterDestination: Bool,
        destinationEntryID: String
    ) {
        guard hasFinishedCurrentEntry,
              isLaterDestination,
              isEnabled,
              let recordID else {
            pendingRemoval = nil
            return
        }
        pendingRemoval = Removal(
            entryID: entryID,
            recordID: recordID,
            destinationEntryID: destinationEntryID
        )
    }

    mutating func takeRemoval(afterLoading entryID: String) -> Removal? {
        guard pendingRemoval?.destinationEntryID == entryID else { return nil }
        defer { pendingRemoval = nil }
        return pendingRemoval
    }

    mutating func cancelRemoval(afterFailingToLoad entryID: String) {
        guard pendingRemoval?.destinationEntryID == entryID else { return }
        pendingRemoval = nil
    }
}

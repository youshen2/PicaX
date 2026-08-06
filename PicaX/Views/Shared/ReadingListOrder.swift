enum ReadingListOrder: String, CaseIterable, Identifiable {
    case ascending
    case descending
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending:
            "正序"
        case .descending:
            "倒序"
        case .random:
            "随机"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending:
            "arrow.down"
        case .descending:
            "arrow.up"
        case .random:
            "shuffle"
        }
    }

    func ordered<Entry: Identifiable>(
        _ entries: [Entry],
        sourceIndexes: [Entry.ID: Int]
    ) -> [Entry] where Entry.ID: Hashable {
        switch self {
        case .ascending:
            return entries.sorted {
                sourceIndexes[$0.id, default: .max] < sourceIndexes[$1.id, default: .max]
            }
        case .descending:
            return entries.sorted {
                sourceIndexes[$0.id, default: .min] > sourceIndexes[$1.id, default: .min]
            }
        case .random:
            return randomized(entries)
        }
    }

    private func randomized<Entry: Identifiable>(_ entries: [Entry]) -> [Entry] {
        var randomizedEntries = entries.shuffled()
        guard randomizedEntries.count > 1,
              randomizedEntries.elementsEqual(entries, by: { $0.id == $1.id }) else {
            return randomizedEntries
        }

        randomizedEntries.append(randomizedEntries.removeFirst())
        return randomizedEntries
    }
}

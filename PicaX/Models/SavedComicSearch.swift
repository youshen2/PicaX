import Foundation

nonisolated struct SavedComicSearch: Codable, Identifiable {
    static let storageKey = "picax.savedSearches"
    var id = UUID()
    var name: String
    var isPinned = false
    var search: SearchHistoryRecord
}

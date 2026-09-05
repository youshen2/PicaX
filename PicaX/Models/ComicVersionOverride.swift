import Foundation

nonisolated struct ComicVersionOverride: Codable, Identifiable, Hashable, Sendable {
    static let storageKey = "picax.comicVersionOverrides"
    let id: String
    var group: String
    var separates: Bool
}

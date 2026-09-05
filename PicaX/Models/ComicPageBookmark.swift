import Foundation

nonisolated struct ComicPageBookmark: Codable, Identifiable {
    static let storageKey = "picax.pageBookmarks"
    let comicID: String
    let chapterID: String
    let chapterTitle: String
    let chapterIndex: Int
    let pageIndex: Int
    let thumbnailURLString: String?
    var note: String
    var createdAt: Date = Date()
    var id: String { "\(comicID):\(chapterID):\(pageIndex)" }
}

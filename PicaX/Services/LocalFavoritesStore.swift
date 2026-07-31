import Foundation

struct LocalFavoritesStore: Sendable {
    nonisolated static let legacyDefaultsKeyPrefix = "picax.localFavorites."

    nonisolated init() {}

    nonisolated var folders: [LocalFavoriteFolder] {
        [
            LocalFavoriteFolder(id: "default", title: "本地收藏", subtitle: "保存在当前设备")
        ]
    }

    nonisolated func items(folderID: String) -> [ComicListItem] {
        PicaXSQLiteStore.loadLocalFavorites(folderID: folderID).map(\.item)
    }

    func add(item: ComicListItem, folderID: String) {
        let stored = StoredLocalFavorite(item: item, favoriteDate: Date())
        PicaXSQLiteStore.upsertLocalFavorite(stored, folderID: folderID)
    }
}

struct StoredLocalFavorite: Codable, Sendable {
    let id: String
    let platform: ComicPlatform
    let title: String
    let subtitle: String
    let coverURLString: String
    let tags: [String]
    let pageCount: Int?
    let likesCount: Int?
    let favoriteDate: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case platform
        case title
        case subtitle
        case coverURLString
        case tags
        case pageCount
        case likesCount
        case favoriteDate
    }

    nonisolated init(item: ComicListItem, favoriteDate: Date?) {
        id = item.id
        platform = item.platform
        title = item.title
        subtitle = item.subtitle
        coverURLString = item.coverURLString
        tags = item.tags
        pageCount = item.pageCount
        likesCount = item.likesCount
        self.favoriteDate = favoriteDate
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        platform = try container.decode(ComicPlatform.self, forKey: .platform)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        coverURLString = try container.decode(String.self, forKey: .coverURLString)
        tags = try container.decode([String].self, forKey: .tags)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        favoriteDate = try container.decodeIfPresent(Date.self, forKey: .favoriteDate)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(platform, forKey: .platform)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(coverURLString, forKey: .coverURLString)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encodeIfPresent(likesCount, forKey: .likesCount)
        try container.encodeIfPresent(favoriteDate, forKey: .favoriteDate)
    }

    nonisolated var item: ComicListItem {
        ComicListItem(
            id: id,
            platform: platform,
            title: title,
            subtitle: subtitle,
            coverURLString: coverURLString,
            tags: tags,
            pageCount: pageCount,
            likesCount: likesCount,
            favoriteDate: favoriteDate
        )
    }
}

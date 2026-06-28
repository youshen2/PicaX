import Foundation

struct WatchComicItem: Identifiable, Hashable {
    let id: String
    let platform: WatchComicPlatform
    let title: String
    let subtitle: String
    let coverURLString: String?
    let tags: [String]
    let pageCount: Int?
    let favoriteDate: Date?

    var coverURL: URL? {
        guard let coverURLString, !coverURLString.isEmpty else { return nil }
        return URL(string: coverURLString)
    }
}

struct WatchCategoryItem: Identifiable, Hashable {
    let title: String
    let query: String
    let platform: WatchComicPlatform
    let subtitle: String
    let groupTitle: String?

    var id: String {
        "\(platform.id)-\(query)-\(title)"
    }
}

struct WatchComicDetailInfo: Identifiable, Hashable {
    let item: WatchComicItem
    let description: String
    let metadata: [WatchDetailMetadata]
    let tagGroups: [WatchTagGroup]
    let chapters: [WatchChapterItem]
    let related: [WatchComicItem]
    let updatedText: String?

    var id: String { item.id }
}

struct WatchDetailMetadata: Identifiable, Hashable {
    let title: String
    let value: String

    var id: String {
        "\(title)-\(value)"
    }
}

struct WatchTagGroup: Identifiable, Hashable {
    let title: String
    let tags: [WatchTagItem]

    var id: String { title }
}

struct WatchTagItem: Identifiable, Hashable {
    let title: String
    let query: String
    let platform: WatchComicPlatform

    var id: String {
        "\(platform.id)-\(query)-\(title)"
    }
}

struct WatchChapterItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

enum WatchPageState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

enum WatchComicAPIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse(String)
    case loginRequired(String)
    case unsupported(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            "接口地址无效：\(value)"
        case .invalidResponse(let message), .loginRequired(let message), .unsupported(let message), .server(let message):
            message
        }
    }
}

extension WatchComicItem {
    init(localFavorite: WatchLocalFavoriteItem) {
        self.init(
            id: localFavorite.id,
            platform: WatchComicPlatform(rawValue: localFavorite.platformID) ?? .picacg,
            title: localFavorite.title,
            subtitle: localFavorite.subtitle,
            coverURLString: localFavorite.coverURLString,
            tags: localFavorite.tags,
            pageCount: localFavorite.pageCount,
            favoriteDate: localFavorite.favoriteDate
        )
    }
}

extension WatchLocalFavoriteItem {
    init(item: WatchComicItem, favoriteDate: Date = Date()) {
        self.init(
            id: item.id,
            platformID: item.platform.id,
            title: item.title,
            subtitle: item.subtitle,
            coverURLString: item.coverURLString ?? "",
            tags: item.tags,
            pageCount: item.pageCount,
            likesCount: nil,
            favoriteDate: item.favoriteDate ?? favoriteDate
        )
    }
}

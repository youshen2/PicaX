import Foundation

struct WatchComicItem: Identifiable, Hashable, Codable {
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

struct WatchCategoryItem: Identifiable, Hashable, Codable {
    let title: String
    let query: String
    let platform: WatchComicPlatform
    let subtitle: String
    let groupTitle: String?

    var id: String {
        "\(platform.id)-\(query)-\(title)"
    }
}

struct WatchFavoriteFolder: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let platform: WatchComicPlatform
}

struct WatchComicDetailInfo: Identifiable, Hashable, Codable {
    let item: WatchComicItem
    let description: String
    let metadata: [WatchDetailMetadata]
    let tagGroups: [WatchTagGroup]
    let chapters: [WatchChapterItem]
    let related: [WatchComicItem]
    let updatedText: String?

    var id: String { item.id }
}

struct WatchDetailMetadata: Identifiable, Hashable, Codable {
    let title: String
    let value: String

    var id: String {
        "\(title)-\(value)"
    }
}

struct WatchTagGroup: Identifiable, Hashable, Codable {
    let title: String
    let tags: [WatchTagItem]

    var id: String { title }
}

struct WatchTagItem: Identifiable, Hashable, Codable {
    let title: String
    let query: String
    let platform: WatchComicPlatform

    var id: String {
        "\(platform.id)-\(query)-\(title)"
    }
}

struct WatchChapterItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String?
}

struct WatchChapterImage: Identifiable, Hashable, Codable {
    let id: String
    let urlString: String

    var url: URL? {
        URL.picaxWatchResolved(from: urlString)
    }
}

enum WatchSearchTarget: Hashable, Identifiable, Codable {
    case aggregate([WatchComicPlatform])
    case platform(WatchComicPlatform)

    static var defaultAggregate: WatchSearchTarget {
        .aggregate(WatchComicPlatform.allCases)
    }

    var id: String {
        switch self {
        case .aggregate(let platforms):
            "aggregate-\(Self.normalizedPlatforms(platforms).map(\.id).joined(separator: "-"))"
        case .platform(let platform):
            platform.id
        }
    }

    var title: String {
        switch self {
        case .aggregate(let platforms):
            let normalized = Self.normalizedPlatforms(platforms)
            if normalized.count == WatchComicPlatform.allCases.count {
                return "多平台聚合"
            }
            return "\(normalized.count) 个平台聚合"
        case .platform(let platform):
            return platform.title
        }
    }

    var systemImage: String {
        switch self {
        case .aggregate:
            "square.grid.2x2"
        case .platform(let platform):
            platform.systemImage
        }
    }

    var platforms: [WatchComicPlatform] {
        switch self {
        case .aggregate(let platforms):
            Self.normalizedPlatforms(platforms)
        case .platform(let platform):
            [platform]
        }
    }

    var isAggregate: Bool {
        if case .aggregate = self {
            return true
        }
        return false
    }

    private static func normalizedPlatforms(_ platforms: [WatchComicPlatform]) -> [WatchComicPlatform] {
        let selected = Set(platforms)
        let normalized = WatchComicPlatform.allCases.filter { selected.contains($0) }
        return normalized.isEmpty ? WatchComicPlatform.allCases : normalized
    }
}

struct WatchSearchOptions: Equatable {
    var picacgSort = "dd"
    var nhentaiSort = "date"
    var jmComicSort = "mr"
    var nhentaiLanguage: WatchSearchLanguage?

    nonisolated init(
        picacgSort: String = "dd",
        nhentaiSort: String = "date",
        jmComicSort: String = "mr",
        nhentaiLanguage: WatchSearchLanguage? = nil
    ) {
        self.picacgSort = picacgSort
        self.nhentaiSort = nhentaiSort
        self.jmComicSort = jmComicSort
        self.nhentaiLanguage = nhentaiLanguage
    }

    nonisolated func sortValue(for platform: WatchComicPlatform) -> String {
        switch platform {
        case .picacg:
            picacgSort
        case .nhentai:
            nhentaiSort
        case .jmComic:
            jmComicSort
        case .eHentai, .htManga, .hitomi:
            ""
        }
    }

    nonisolated mutating func setSortValue(_ value: String, for platform: WatchComicPlatform) {
        switch platform {
        case .picacg:
            picacgSort = value
        case .nhentai:
            nhentaiSort = value
        case .jmComic:
            jmComicSort = value
        case .eHentai, .htManga, .hitomi:
            break
        }
    }

    nonisolated func keyword(_ keyword: String, for platform: WatchComicPlatform) -> String {
        guard platform == .nhentai, let nhentaiLanguage else { return keyword }
        let tokens = keyword
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.lowercased().hasPrefix("language:") }
        let cleaned = tokens.joined(separator: " ")
        return "\(cleaned) language:\(nhentaiLanguage.rawValue)"
    }

    nonisolated func isCustomized(for platform: WatchComicPlatform) -> Bool {
        switch platform {
        case .picacg:
            picacgSort != "dd"
        case .nhentai:
            nhentaiSort != "date" || nhentaiLanguage != nil
        case .jmComic:
            jmComicSort != "mr"
        case .eHentai, .htManga, .hitomi:
            false
        }
    }
}

enum WatchSearchLanguage: String, CaseIterable, Identifiable {
    case chinese
    case japanese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese:
            "中文"
        case .japanese:
            "日文"
        case .english:
            "英文"
        }
    }
}

struct WatchSearchSortChoice: Identifiable {
    let value: String
    let title: String

    var id: String { value }
}

enum WatchPageState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

extension WatchComicPlatform {
    var searchSortChoices: [WatchSearchSortChoice] {
        switch self {
        case .picacg:
            [
                WatchSearchSortChoice(value: "dd", title: "新到旧"),
                WatchSearchSortChoice(value: "da", title: "旧到新"),
                WatchSearchSortChoice(value: "ld", title: "最多喜欢"),
                WatchSearchSortChoice(value: "vd", title: "最多指名")
            ]
        case .nhentai:
            [
                WatchSearchSortChoice(value: "date", title: "最近"),
                WatchSearchSortChoice(value: "popular-today", title: "热门 | 今天"),
                WatchSearchSortChoice(value: "popular-week", title: "热门 | 一周"),
                WatchSearchSortChoice(value: "popular-month", title: "热门 | 本月"),
                WatchSearchSortChoice(value: "popular", title: "热门 | 所有时间")
            ]
        case .jmComic:
            [
                WatchSearchSortChoice(value: "mr", title: "最新"),
                WatchSearchSortChoice(value: "mv", title: "总排行"),
                WatchSearchSortChoice(value: "mv_m", title: "月排行"),
                WatchSearchSortChoice(value: "mv_w", title: "周排行"),
                WatchSearchSortChoice(value: "mv_t", title: "日排行"),
                WatchSearchSortChoice(value: "mp", title: "最多图片"),
                WatchSearchSortChoice(value: "tf", title: "最多喜欢")
            ]
        case .eHentai, .htManga, .hitomi:
            []
        }
    }
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

    init(readLater: WatchReadLaterItem) {
        self.init(
            id: readLater.id,
            platform: WatchComicPlatform(rawValue: readLater.platformID) ?? .picacg,
            title: readLater.title,
            subtitle: readLater.subtitle,
            coverURLString: readLater.coverURLString,
            tags: readLater.tags,
            pageCount: readLater.pageCount,
            favoriteDate: nil
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

extension WatchReadLaterItem {
    init(item: WatchComicItem, addedAt: Date = Date()) {
        self.init(
            id: item.id,
            platformID: item.platform.id,
            title: item.title,
            subtitle: item.subtitle,
            coverURLString: item.coverURLString ?? "",
            tags: item.tags,
            pageCount: item.pageCount,
            likesCount: nil,
            addedAt: addedAt
        )
    }
}

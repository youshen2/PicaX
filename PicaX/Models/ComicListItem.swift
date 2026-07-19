import Foundation
import SwiftUI

struct ComicListItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let platform: ComicPlatform
    let title: String
    let subtitle: String
    let coverURLString: String
    let tags: [String]
    let pageCount: Int?
    let likesCount: Int?
    let favoriteDate: Date?

    nonisolated var target: String { id }

    nonisolated var readingHistoryID: String {
        "\(platform.rawValue)-\(id)"
    }

    var coverURL: URL? {
        URL.picaxResolved(from: coverURLString)
    }

    var accentColor: Color {
        platform.accentColor
    }

    nonisolated var platformTitle: String {
        platform.title
    }

    nonisolated var supportsComments: Bool {
        switch platform {
        case .picacg, .nhentai, .eHentai, .jmComic:
            true
        case .htManga, .hitomi:
            false
        }
    }

    nonisolated var pageText: String? {
        guard let pageCount else { return nil }
        return "\(pageCount) 页"
    }

    nonisolated var metadataText: String {
        if let likesCount {
            return "\(likesCount) 喜欢"
        }
        return platform.title
    }

    var favoriteDateText: String {
        guard let favoriteDate else { return "平台收藏" }
        return Self.dateFormatter.string(from: favoriteDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct ComicDetailInfo: Identifiable, Equatable, Codable {
    let item: ComicListItem
    let description: String
    let tagGroups: [ComicTagGroup]
    let chapters: [ComicChapter]
    let related: [ComicListItem]
    let updatedText: String?
    var isLiked: Bool? = nil
    var uploader: ComicUploaderInfo? = nil

    var id: String { item.id }

    var allTags: [ComicTagReference] {
        tagGroups.flatMap(\.tags)
    }
}

struct ComicUploaderInfo: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let title: String
    let level: Int
    let exp: Int
    let slogan: String?
    let avatarURLString: String?
    let frameURLString: String?
    let tag: ComicTagReference?

    var displayName: String {
        name.isEmpty ? id : name
    }

    var levelText: String {
        "Lv\(level) \(title) Exp\(exp)"
    }

    var avatarURL: URL? {
        URL.picaxResolved(from: avatarURLString)
    }

    var frameURL: URL? {
        URL.picaxResolved(from: frameURLString)
    }
}

struct ComicCopyAction: Equatable {
    let title: String
    let copiedTitle: String
    let value: String
    let systemImage: String
}

extension ComicListItem {
    var copyAction: ComicCopyAction? {
        switch platform {
        case .jmComic:
            ComicCopyAction(
                title: "复制车牌号",
                copiedTitle: "已复制车牌号",
                value: jmPlateNumber,
                systemImage: "number.square"
            )
        case .nhentai, .eHentai, .hitomi, .htManga:
            shareURLString.map {
                ComicCopyAction(
                    title: "复制分享链接",
                    copiedTitle: "已复制分享链接",
                    value: $0,
                    systemImage: "link"
                )
            }
        case .picacg:
            nil
        }
    }

    var shareURLString: String? {
        switch platform {
        case .nhentai:
            guard let id = firstNumber(in: self.id) else { return nil }
            return "\(PlatformFeatureSettings.frontendBaseURL(for: .nhentai))/g/\(id)/"
        case .eHentai:
            return normalizedWebURLString(allowedHosts: allowedHosts(for: .eHentai, defaults: ["e-hentai.org", "exhentai.org"]))
        case .hitomi:
            let baseURL = PlatformFeatureSettings.frontendBaseURL(for: .hitomi)
            if let urlString = normalizedWebURLString(allowedHosts: allowedHosts(for: .hitomi, defaults: ["hitomi.la"])) {
                return urlString
            }
            guard let id = firstNumber(in: self.id) else { return nil }
            return "\(baseURL)/galleries/\(id).html"
        case .htManga:
            let baseURL = PlatformFeatureSettings.frontendBaseURL(for: .htManga)
            if let urlString = normalizedWebURLString(allowedHosts: allowedHosts(for: .htManga, defaults: ["www.wnacg.com", "wnacg.com", "www.htmanga3.top", "htmanga3.top"])) {
                return urlString
            }
            guard let id = firstNumber(in: self.id) else { return nil }
            return "\(baseURL)/photos-index-page-1-aid-\(id).html"
        case .picacg, .jmComic:
            return nil
        }
    }

    var jmPlateNumber: String {
        let rawID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = rawID.lowercased().hasPrefix("jm") ? String(rawID.dropFirst(2)) : rawID
        return "jm\(id)"
    }

    private func normalizedWebURLString(allowedHosts: Set<String>) -> String? {
        let rawValue = self.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: rawValue),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host) else {
            return nil
        }
        if components.scheme == nil {
            components.scheme = "https"
        }
        return components.url?.absoluteString
    }

    private func allowedHosts(for platform: ComicPlatform, defaults: Set<String>) -> Set<String> {
        var hosts = defaults
        if let configuredHost = URL(string: PlatformFeatureSettings.frontendBaseURL(for: platform))?.host?.lowercased() {
            hosts.insert(configuredHost)
        }
        return hosts
    }

    private func firstNumber(in value: String) -> String? {
        var result = ""
        for character in value {
            if character.isNumber {
                result.append(character)
            } else if !result.isEmpty {
                return result
            }
        }
        return result.isEmpty ? nil : result
    }
}

struct ComicComment: Identifiable, Equatable, Codable {
    let id: String
    let author: String
    let content: String
    let timeText: String?
    let avatarURLString: String?
    let likesCount: Int?
    let replyCount: Int?
    let replies: [ComicComment]
    var frameURLString: String? = nil

    var avatarURL: URL? {
        guard let avatarURLString, !avatarURLString.isEmpty else { return nil }
        return URL.picaxResolved(from: avatarURLString)
    }

    var frameURL: URL? {
        guard let frameURLString, !frameURLString.isEmpty else { return nil }
        return URL.picaxResolved(from: frameURLString)
    }
}

struct ComicTagGroup: Identifiable, Equatable, Codable {
    let title: String
    let tags: [ComicTagReference]

    var id: String { title }
}

struct ComicTagReference: Identifiable, Hashable, Codable {
    let title: String
    let query: String
    let platform: ComicPlatform
    let urlString: String?

    var id: String {
        "\(platform.id)-\(query)-\(urlString ?? "")"
    }

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}

struct ComicCategoryItem: Identifiable, Hashable {
    let title: String
    let query: String
    let platform: ComicPlatform
    let subtitle: String
    let coverURLString: String?
    let groupTitle: String?

    var id: String {
        "\(platform.id)-\(query)-\(title)"
    }

    var tag: ComicTagReference {
        ComicTagReference(title: title, query: query, platform: platform, urlString: nil)
    }
}

struct ComicChapter: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let subtitle: String?
}

struct ComicChapterImage: Identifiable, Equatable {
    let id: String
    let urlString: String

    var url: URL? {
        URL.picaxResolved(from: urlString)
    }
}

extension URL {
    nonisolated static func picaxResolved(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value) else { return nil }
        if url.scheme == nil, url.path.hasPrefix("/") {
            return URL(fileURLWithPath: url.path)
        }
        return url
    }

    nonisolated var picaxLocalFileURL: URL? {
        if isFileURL {
            return self
        }
        if scheme == nil, path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    nonisolated var picaxSupportsURLCache: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "picax-ehentai-image"
    }
}

struct LocalFavoriteFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
}

struct PlatformFavoriteFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let platform: ComicPlatform
}

enum ComicExplorePopularityPeriod: String, Hashable, Identifiable {
    case today
    case week
    case month
    case year
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "本日热门"
        case .week:
            "本周热门"
        case .month:
            "本月热门"
        case .year:
            "本年热门"
        case .allTime:
            "总排行榜"
        }
    }

    var subtitle: String {
        switch self {
        case .today:
            "查看最近一天的人气漫画"
        case .week:
            "查看最近一周的人气漫画"
        case .month:
            "查看最近一个月的人气漫画"
        case .year:
            "查看最近一年的人气漫画"
        case .allTime:
            "查看平台累计热门排行"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "flame.fill"
        case .week:
            "calendar"
        case .month:
            "calendar.circle"
        case .year:
            "chart.line.uptrend.xyaxis"
        case .allTime:
            "trophy.fill"
        }
    }
}

enum ComicExploreEntry: Hashable, Identifiable {
    case random
    case latest
    case popular(ComicExplorePopularityPeriod)
    case search

    nonisolated static func availableEntries(for platform: ComicPlatform) -> [ComicExploreEntry] {
        switch platform {
        case .picacg:
            [.random, .latest, .popular(.today), .popular(.week), .popular(.month)]
        case .nhentai:
            [.latest, .popular(.today), .popular(.week), .popular(.month), .popular(.allTime)]
        case .eHentai:
            [.latest, .popular(.today)]
        case .htManga:
            [.latest, .popular(.today), .popular(.week), .popular(.month)]
        case .jmComic:
            [.random, .latest, .popular(.today), .popular(.week), .popular(.month), .popular(.allTime)]
        case .hitomi:
            [.random, .latest, .popular(.today), .popular(.week), .popular(.month), .popular(.year)]
        }
    }

    var id: String {
        switch self {
        case .random:
            "random"
        case .latest:
            "latest"
        case .popular(let period):
            "popular-\(period.rawValue)"
        case .search:
            "search"
        }
    }

    var isPopular: Bool {
        if case .popular = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .random:
            "随机"
        case .latest:
            "最新"
        case .popular(let period):
            period.title
        case .search:
            "高级筛选"
        }
    }

    var subtitle: String {
        switch self {
        case .random:
            "打开随机推荐列表"
        case .latest:
            "查看最近更新的漫画"
        case .popular(let period):
            period.subtitle
        case .search:
            "按平台默认搜索接口浏览"
        }
    }

    var systemImage: String {
        switch self {
        case .random:
            "shuffle"
        case .latest:
            "clock.arrow.circlepath"
        case .popular(let period):
            period.systemImage
        case .search:
            "line.3.horizontal.decrease.circle"
        }
    }
}

struct ComicSearchAdvancedOptions: Equatable {
    var picacgSort = "dd"
    var nhentaiSort = "date"
    var jmComicSort = "mr"
    var nhentaiLanguage: ComicSearchLanguage?

    nonisolated init(
        picacgSort: String = "dd",
        nhentaiSort: String = "date",
        jmComicSort: String = "mr",
        nhentaiLanguage: ComicSearchLanguage? = nil
    ) {
        self.picacgSort = picacgSort
        self.nhentaiSort = nhentaiSort
        self.jmComicSort = jmComicSort
        self.nhentaiLanguage = nhentaiLanguage
    }

    nonisolated func sortValue(for platform: ComicPlatform) -> String {
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

    nonisolated mutating func setSortValue(_ value: String, for platform: ComicPlatform) {
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

    nonisolated func keyword(_ keyword: String, for platform: ComicPlatform) -> String {
        guard platform == .nhentai, let nhentaiLanguage else { return keyword }
        let tokens = keyword
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.lowercased().hasPrefix("language:") }
        let cleaned = tokens.joined(separator: " ")
        return "\(cleaned) language:\(nhentaiLanguage.rawValue)"
    }

    nonisolated func isCustomized(for platform: ComicPlatform) -> Bool {
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

enum ComicSearchLanguage: String, CaseIterable, Identifiable {
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

struct ComicSearchSortChoice: Identifiable {
    let value: String
    let title: String

    var id: String { value }
}

extension ComicPlatform {
    var searchSortChoices: [ComicSearchSortChoice] {
        switch self {
        case .picacg:
            [
                ComicSearchSortChoice(value: "dd", title: "新到旧"),
                ComicSearchSortChoice(value: "da", title: "旧到新"),
                ComicSearchSortChoice(value: "ld", title: "最多喜欢"),
                ComicSearchSortChoice(value: "vd", title: "最多指名")
            ]
        case .nhentai:
            [
                ComicSearchSortChoice(value: "date", title: "最近"),
                ComicSearchSortChoice(value: "popular-today", title: "热门 | 今天"),
                ComicSearchSortChoice(value: "popular-week", title: "热门 | 一周"),
                ComicSearchSortChoice(value: "popular-month", title: "热门 | 本月"),
                ComicSearchSortChoice(value: "popular", title: "热门 | 所有时间")
            ]
        case .jmComic:
            [
                ComicSearchSortChoice(value: "mr", title: "最新"),
                ComicSearchSortChoice(value: "mv", title: "总排行"),
                ComicSearchSortChoice(value: "mv_m", title: "月排行"),
                ComicSearchSortChoice(value: "mv_w", title: "周排行"),
                ComicSearchSortChoice(value: "mv_t", title: "日排行"),
                ComicSearchSortChoice(value: "mp", title: "最多图片"),
                ComicSearchSortChoice(value: "tf", title: "最多喜欢")
            ]
        case .eHentai, .htManga, .hitomi:
            []
        }
    }
}

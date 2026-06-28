import Foundation

struct WatchAccountSnapshot: Codable, Equatable {
    var updatedAt: Date
    var platformAccounts: [WatchPlatformAccount]
    var localFavorites: [WatchLocalFavoriteItem]

    var hasSyncedAccounts: Bool {
        !platformAccounts.isEmpty
    }

    static var empty: WatchAccountSnapshot {
        WatchAccountSnapshot(updatedAt: .distantPast, platformAccounts: [], localFavorites: [])
    }

    init(updatedAt: Date, platformAccounts: [WatchPlatformAccount], localFavorites: [WatchLocalFavoriteItem] = []) {
        self.updatedAt = updatedAt
        self.platformAccounts = platformAccounts
        self.localFavorites = localFavorites
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt
        case platformAccounts
        case localFavorites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        platformAccounts = try container.decode([WatchPlatformAccount].self, forKey: .platformAccounts)
        localFavorites = try container.decodeIfPresent([WatchLocalFavoriteItem].self, forKey: .localFavorites) ?? []
    }
}

struct WatchPlatformAccount: Codable, Equatable, Identifiable {
    var id: String
    var platformID: String
    var title: String
    var username: String
    var displayName: String
    var credentialState: String
    var credential: WatchPlatformCredential
    var loggedInAt: Date
}

struct WatchPlatformCredential: Codable, Equatable {
    var token: String?
    var refreshToken: String?
    var tokenType: String?
    var password: String?
    var cookies: [WatchStoredHTTPCookie]
    var userAgent: String?
    var baseURL: String?
    var source: String
    var profile: WatchPlatformAccountProfile?

    nonisolated init(
        token: String?,
        refreshToken: String?,
        tokenType: String?,
        password: String?,
        cookies: [WatchStoredHTTPCookie],
        userAgent: String?,
        baseURL: String?,
        source: String,
        profile: WatchPlatformAccountProfile?
    ) {
        self.token = token
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.password = password
        self.cookies = cookies
        self.userAgent = userAgent
        self.baseURL = baseURL
        self.source = source
        self.profile = profile
    }

    static let empty = WatchPlatformCredential(
        token: nil,
        refreshToken: nil,
        tokenType: nil,
        password: nil,
        cookies: [],
        userAgent: nil,
        baseURL: nil,
        source: "manual",
        profile: nil
    )

    var isEmpty: Bool {
        (token?.isEmpty ?? true) && (refreshToken?.isEmpty ?? true) && (password?.isEmpty ?? true) && cookies.isEmpty
    }
}

struct WatchPlatformAccountProfile: Codable, Equatable {
    var email: String?
    var username: String?
    var nickname: String?

    nonisolated init(email: String?, username: String?, nickname: String?) {
        self.email = email
        self.username = username
        self.nickname = nickname
    }
}

struct WatchStoredHTTPCookie: Codable, Equatable, Identifiable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresDate: Date?
    var isSecure: Bool

    nonisolated init(name: String, value: String, domain: String, path: String, expiresDate: Date?, isSecure: Bool) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
    }

    var id: String {
        "\(domain)|\(path)|\(name)"
    }
}

struct WatchLocalFavoriteItem: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var platformID: String
    var title: String
    var subtitle: String
    var coverURLString: String
    var tags: [String]
    var pageCount: Int?
    var likesCount: Int?
    var favoriteDate: Date?

    nonisolated init(
        id: String,
        platformID: String,
        title: String,
        subtitle: String,
        coverURLString: String,
        tags: [String],
        pageCount: Int?,
        likesCount: Int?,
        favoriteDate: Date?
    ) {
        self.id = id
        self.platformID = platformID
        self.title = title
        self.subtitle = subtitle
        self.coverURLString = coverURLString
        self.tags = tags
        self.pageCount = pageCount
        self.likesCount = likesCount
        self.favoriteDate = favoriteDate
    }

    var syncID: String {
        "\(platformID)-\(id)"
    }
}

struct WatchLocalFavoriteDeletion: Codable, Equatable, Identifiable, Hashable {
    var syncID: String
    var deletedAt: Date

    var id: String { syncID }

    nonisolated init(syncID: String, deletedAt: Date) {
        self.syncID = syncID
        self.deletedAt = deletedAt
    }
}

enum WatchComicPlatform: String, CaseIterable, Codable, Identifiable {
    case picacg
    case jmComic
    case nhentai
    case eHentai
    case hitomi
    case htManga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .picacg:
            "PicACG"
        case .jmComic:
            "JMComic"
        case .nhentai:
            "NHentai"
        case .eHentai:
            "E-Hentai"
        case .hitomi:
            "Hitomi"
        case .htManga:
            "HT Manga"
        }
    }

    var subtitle: String {
        switch self {
        case .picacg:
            "哔咔漫画账号"
        case .jmComic:
            "禁漫天堂账号"
        case .nhentai:
            "NHentai 网站账号"
        case .eHentai:
            "E-Hentai 网页登录"
        case .hitomi:
            "Hitomi 浏览状态"
        case .htManga:
            "HT Manga 账号"
        }
    }

    var systemImage: String {
        switch self {
        case .picacg:
            "p.circle"
        case .jmComic:
            "j.circle"
        case .nhentai:
            "n.circle"
        case .eHentai:
            "e.circle"
        case .hitomi:
            "h.circle"
        case .htManga:
            "book.circle"
        }
    }

    var accentColorName: String {
        switch self {
        case .picacg:
            "pink"
        case .jmComic:
            "orange"
        case .nhentai:
            "red"
        case .eHentai:
            "purple"
        case .hitomi:
            "blue"
        case .htManga:
            "teal"
        }
    }

    var supportsFavorites: Bool {
        switch self {
        case .picacg, .jmComic, .nhentai, .eHentai, .htManga:
            true
        case .hitomi:
            false
        }
    }

    var discoveryEntries: [WatchDiscoveryKind] {
        switch self {
        case .nhentai, .eHentai, .htManga:
            [.latest, .ranking]
        case .picacg, .jmComic, .hitomi:
            [.random, .latest, .ranking]
        }
    }
}

enum WatchDiscoveryKind: String, CaseIterable, Codable, Identifiable {
    case random
    case latest
    case ranking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random:
            "随机"
        case .latest:
            "最新"
        case .ranking:
            "排行榜"
        }
    }

    var subtitle: String {
        switch self {
        case .random:
            "打开随机推荐列表"
        case .latest:
            "查看最近更新的漫画"
        case .ranking:
            "按平台热度浏览"
        }
    }

    var systemImage: String {
        switch self {
        case .random:
            "shuffle"
        case .latest:
            "clock.arrow.circlepath"
        case .ranking:
            "chart.bar"
        }
    }
}

enum WatchAccountSyncEnvelope {
    static let messageKindKey = "picax.message.kind"
    static let snapshotDataKey = "picax.accountSnapshot.data"
    static let localFavoritesDataKey = "picax.localFavorites.data"
    static let localFavoriteDeletionsDataKey = "picax.localFavoriteDeletions.data"
    static let accountSnapshotKind = "accountSnapshot"
    static let requestSnapshotKind = "requestAccountSnapshot"
    static let localFavoritesSyncKind = "localFavoritesSync"

    static var requestMessage: [String: Any] {
        [messageKindKey: requestSnapshotKind]
    }

    static func message(for snapshot: WatchAccountSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return [messageKindKey: accountSnapshotKind]
        }
        return [
            messageKindKey: accountSnapshotKind,
            snapshotDataKey: data
        ]
    }

    static func message(
        forLocalFavorites localFavorites: [WatchLocalFavoriteItem],
        deletions: [WatchLocalFavoriteDeletion] = []
    ) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(localFavorites) else {
            return [messageKindKey: localFavoritesSyncKind]
        }
        var message: [String: Any] = [
            messageKindKey: localFavoritesSyncKind,
            localFavoritesDataKey: data
        ]
        if let deletionData = try? JSONEncoder().encode(deletions) {
            message[localFavoriteDeletionsDataKey] = deletionData
        }
        return message
    }

    static func snapshot(from message: [String: Any]) -> WatchAccountSnapshot? {
        guard let data = message[snapshotDataKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchAccountSnapshot.self, from: data)
    }

    static func localFavorites(from message: [String: Any]) -> [WatchLocalFavoriteItem]? {
        guard let data = message[localFavoritesDataKey] as? Data else { return nil }
        return try? JSONDecoder().decode([WatchLocalFavoriteItem].self, from: data)
    }

    static func localFavoriteDeletions(from message: [String: Any]) -> [WatchLocalFavoriteDeletion] {
        guard let data = message[localFavoriteDeletionsDataKey] as? Data,
              let deletions = try? JSONDecoder().decode([WatchLocalFavoriteDeletion].self, from: data) else {
            return []
        }
        return deletions
    }

    static func isSnapshotRequest(_ message: [String: Any]) -> Bool {
        message[messageKindKey] as? String == requestSnapshotKind
    }

    static func isLocalFavoritesSync(_ message: [String: Any]) -> Bool {
        message[messageKindKey] as? String == localFavoritesSyncKind
    }
}

import Foundation

nonisolated struct WatchAccountSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var platformAccounts: [WatchPlatformAccount]
    var localFavorites: [WatchLocalFavoriteItem]
    var localFavoriteDeletions: [WatchLocalFavoriteDeletion]
    var readLater: [WatchReadLaterItem]
    var readLaterDeletions: [WatchReadLaterDeletion]
    var readingHistory: [WatchReadingHistoryRecord]
    var readingHistoryDeletions: [WatchReadingHistoryDeletion]

    var hasSyncedAccounts: Bool {
        !platformAccounts.isEmpty
    }

    static var empty: WatchAccountSnapshot {
        WatchAccountSnapshot(
            updatedAt: .distantPast,
            platformAccounts: [],
            localFavorites: [],
            localFavoriteDeletions: [],
            readLater: [],
            readLaterDeletions: [],
            readingHistory: [],
            readingHistoryDeletions: []
        )
    }

    init(
        updatedAt: Date,
        platformAccounts: [WatchPlatformAccount],
        localFavorites: [WatchLocalFavoriteItem] = [],
        localFavoriteDeletions: [WatchLocalFavoriteDeletion] = [],
        readLater: [WatchReadLaterItem] = [],
        readLaterDeletions: [WatchReadLaterDeletion] = [],
        readingHistory: [WatchReadingHistoryRecord] = [],
        readingHistoryDeletions: [WatchReadingHistoryDeletion] = []
    ) {
        self.updatedAt = updatedAt
        self.platformAccounts = platformAccounts
        self.localFavorites = localFavorites
        self.localFavoriteDeletions = localFavoriteDeletions
        self.readLater = readLater
        self.readLaterDeletions = readLaterDeletions
        self.readingHistory = readingHistory
        self.readingHistoryDeletions = readingHistoryDeletions
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt
        case platformAccounts
        case localFavorites
        case localFavoriteDeletions
        case readLater
        case readLaterDeletions
        case readingHistory
        case readingHistoryDeletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        platformAccounts = try container.decode([WatchPlatformAccount].self, forKey: .platformAccounts)
        localFavorites = try container.decodeIfPresent([WatchLocalFavoriteItem].self, forKey: .localFavorites) ?? []
        localFavoriteDeletions = try container.decodeIfPresent(
            [WatchLocalFavoriteDeletion].self,
            forKey: .localFavoriteDeletions
        ) ?? []
        readLater = try container.decodeIfPresent([WatchReadLaterItem].self, forKey: .readLater) ?? []
        readLaterDeletions = try container.decodeIfPresent(
            [WatchReadLaterDeletion].self,
            forKey: .readLaterDeletions
        ) ?? []
        readingHistory = try container.decodeIfPresent(
            [WatchReadingHistoryRecord].self,
            forKey: .readingHistory
        ) ?? []
        readingHistoryDeletions = try container.decodeIfPresent(
            [WatchReadingHistoryDeletion].self,
            forKey: .readingHistoryDeletions
        ) ?? []
    }
}

nonisolated struct WatchPlatformAccount: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var platformID: String
    var title: String
    var username: String
    var displayName: String
    var credentialState: String
    var credential: WatchPlatformCredential
    var loggedInAt: Date
}

nonisolated struct WatchPlatformCredential: Codable, Equatable, Sendable {
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

    var hasSensitiveData: Bool {
        !isEmpty
    }

    var secrets: WatchPlatformCredentialSecrets {
        WatchPlatformCredentialSecrets(
            token: token,
            refreshToken: refreshToken,
            tokenType: tokenType,
            password: password,
            cookies: cookies
        )
    }

    func removingSecrets() -> WatchPlatformCredential {
        var copy = self
        copy.token = nil
        copy.refreshToken = nil
        copy.tokenType = nil
        copy.password = nil
        copy.cookies = []
        return copy
    }

    func applying(_ secrets: WatchPlatformCredentialSecrets) -> WatchPlatformCredential {
        var copy = self
        copy.token = secrets.token
        copy.refreshToken = secrets.refreshToken
        copy.tokenType = secrets.tokenType
        copy.password = secrets.password
        copy.cookies = secrets.cookies
        return copy
    }
}

nonisolated struct WatchPlatformCredentialSecrets: Codable, Equatable, Sendable {
    var token: String?
    var refreshToken: String?
    var tokenType: String?
    var password: String?
    var cookies: [WatchStoredHTTPCookie]
}

nonisolated struct WatchPlatformAccountProfile: Codable, Equatable, Sendable {
    var email: String?
    var username: String?
    var nickname: String?

    nonisolated init(email: String?, username: String?, nickname: String?) {
        self.email = email
        self.username = username
        self.nickname = nickname
    }
}

nonisolated struct WatchStoredHTTPCookie: Codable, Equatable, Identifiable, Sendable {
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

nonisolated struct WatchLocalFavoriteItem: Codable, Equatable, Identifiable, Hashable, Sendable {
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

nonisolated struct WatchLocalFavoriteDeletion: Codable, Equatable, Identifiable, Hashable, Sendable {
    var syncID: String
    var deletedAt: Date

    var id: String { syncID }

    nonisolated init(syncID: String, deletedAt: Date) {
        self.syncID = syncID
        self.deletedAt = deletedAt
    }
}

nonisolated struct WatchReadLaterItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var platformID: String
    var title: String
    var subtitle: String
    var coverURLString: String
    var tags: [String]
    var pageCount: Int?
    var likesCount: Int?
    var language: String?
    var addedAt: Date

    nonisolated init(
        id: String,
        platformID: String,
        title: String,
        subtitle: String,
        coverURLString: String,
        tags: [String],
        pageCount: Int?,
        likesCount: Int?,
        language: String? = nil,
        addedAt: Date
    ) {
        self.id = id
        self.platformID = platformID
        self.title = title
        self.subtitle = subtitle
        self.coverURLString = coverURLString
        self.tags = tags
        self.pageCount = pageCount
        self.likesCount = likesCount
        self.language = language
        self.addedAt = addedAt
    }

    var syncID: String {
        "\(platformID)-\(id)"
    }
}

nonisolated struct WatchReadLaterDeletion: Codable, Equatable, Identifiable, Hashable, Sendable {
    var syncID: String
    var deletedAt: Date

    var id: String { syncID }

    nonisolated init(syncID: String, deletedAt: Date) {
        self.syncID = syncID
        self.deletedAt = deletedAt
    }
}

nonisolated struct WatchReadingProgress: Hashable, Codable, Sendable {
    var chapterIndex: Int
    var pageIndex: Int
    var totalPages: Int
    var totalChapters: Int

    var progressText: String {
        guard totalPages > 0 else { return "第 \(chapterIndex + 1) 章" }
        return "第 \(chapterIndex + 1)/\(max(totalChapters, 1)) 章 · \(pageIndex + 1)/\(totalPages) 页"
    }
}

nonisolated struct WatchReadingHistoryRecord: Identifiable, Hashable, Codable, Sendable {
    var comicID: String
    var platformID: String
    var title: String
    var subtitle: String
    var coverURLString: String?
    var tags: [String]
    var pageCount: Int?
    var favoriteDate: Date?
    var language: String?
    var viewedAt: Date
    var progress: WatchReadingProgress

    var id: String {
        "\(platformID)-\(comicID)"
    }

    nonisolated init(
        comicID: String,
        platformID: String,
        title: String,
        subtitle: String,
        coverURLString: String?,
        tags: [String],
        pageCount: Int?,
        favoriteDate: Date?,
        language: String? = nil,
        viewedAt: Date,
        progress: WatchReadingProgress
    ) {
        self.comicID = comicID
        self.platformID = platformID
        self.title = title
        self.subtitle = subtitle
        self.coverURLString = coverURLString
        self.tags = tags
        self.pageCount = pageCount
        self.favoriteDate = favoriteDate
        self.language = language
        self.viewedAt = viewedAt
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey {
        case comicID
        case platformID
        case title
        case subtitle
        case coverURLString
        case tags
        case pageCount
        case favoriteDate
        case language
        case viewedAt
        case progress
        case item
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let legacyItem = try container.decodeIfPresent(LegacyItem.self, forKey: .item) {
            comicID = legacyItem.id
            platformID = legacyItem.platform.rawValue
            title = legacyItem.title
            subtitle = legacyItem.subtitle
            coverURLString = legacyItem.coverURLString
            tags = legacyItem.tags
            pageCount = legacyItem.pageCount
            favoriteDate = legacyItem.favoriteDate
            language = nil
        } else {
            comicID = try container.decode(String.self, forKey: .comicID)
            platformID = try container.decode(String.self, forKey: .platformID)
            title = try container.decode(String.self, forKey: .title)
            subtitle = try container.decode(String.self, forKey: .subtitle)
            coverURLString = try container.decodeIfPresent(String.self, forKey: .coverURLString)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
            favoriteDate = try container.decodeIfPresent(Date.self, forKey: .favoriteDate)
            language = try container.decodeIfPresent(String.self, forKey: .language)
        }
        viewedAt = try container.decode(Date.self, forKey: .viewedAt)
        progress = try container.decode(WatchReadingProgress.self, forKey: .progress)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(comicID, forKey: .comicID)
        try container.encode(platformID, forKey: .platformID)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(coverURLString, forKey: .coverURLString)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encodeIfPresent(favoriteDate, forKey: .favoriteDate)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encode(viewedAt, forKey: .viewedAt)
        try container.encode(progress, forKey: .progress)
    }

    private nonisolated struct LegacyItem: Codable, Sendable {
        var id: String
        var platform: WatchComicPlatform
        var title: String
        var subtitle: String
        var coverURLString: String?
        var tags: [String]
        var pageCount: Int?
        var favoriteDate: Date?
    }
}

nonisolated struct WatchReadingHistoryDeletion: Codable, Equatable, Identifiable, Hashable, Sendable {
    var syncID: String
    var deletedAt: Date

    var id: String { syncID }

    nonisolated init(syncID: String, deletedAt: Date) {
        self.syncID = syncID
        self.deletedAt = deletedAt
    }
}

nonisolated enum WatchComicPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
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
            "绅士漫画"
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
            "绅士漫画账号"
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

nonisolated enum WatchDiscoveryKind: String, CaseIterable, Codable, Identifiable {
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

nonisolated struct WatchAccountSyncMessage: Sendable {
    let kind: String?
    let data: [String: Data]
}

nonisolated enum WatchAccountSyncEnvelope {
    static let messageKindKey = "picax.message.kind"
    static let snapshotDataKey = "picax.accountSnapshot.data"
    static let localFavoritesDataKey = "picax.localFavorites.data"
    static let localFavoriteDeletionsDataKey = "picax.localFavoriteDeletions.data"
    static let readLaterDataKey = "picax.readLater.data"
    static let readLaterDeletionsDataKey = "picax.readLater.deletions.data"
    static let readingHistoryDataKey = "picax.readingHistory.data"
    static let readingHistoryDeletionsDataKey = "picax.readingHistory.deletions.data"
    static let accountSnapshotKind = "accountSnapshot"
    static let requestSnapshotKind = "requestAccountSnapshot"
    static let localFavoritesSyncKind = "localFavoritesSync"
    static let readLaterSyncKind = "readLaterSync"
    static let readingHistorySyncKind = "readingHistorySync"
    private static let dataKeys = [
        snapshotDataKey,
        localFavoritesDataKey,
        localFavoriteDeletionsDataKey,
        readLaterDataKey,
        readLaterDeletionsDataKey,
        readingHistoryDataKey,
        readingHistoryDeletionsDataKey
    ]

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

    static func message(
        forReadLater readLater: [WatchReadLaterItem],
        deletions: [WatchReadLaterDeletion] = []
    ) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(readLater) else {
            return [messageKindKey: readLaterSyncKind]
        }
        var message: [String: Any] = [
            messageKindKey: readLaterSyncKind,
            readLaterDataKey: data
        ]
        if let deletionData = try? JSONEncoder().encode(deletions) {
            message[readLaterDeletionsDataKey] = deletionData
        }
        return message
    }

    static func message(
        forReadingHistory readingHistory: [WatchReadingHistoryRecord],
        deletions: [WatchReadingHistoryDeletion] = []
    ) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(readingHistory) else {
            return [messageKindKey: readingHistorySyncKind]
        }
        var message: [String: Any] = [
            messageKindKey: readingHistorySyncKind,
            readingHistoryDataKey: data
        ]
        if let deletionData = try? JSONEncoder().encode(deletions) {
            message[readingHistoryDeletionsDataKey] = deletionData
        }
        return message
    }

    static func receivedMessage(from message: [String: Any]) -> WatchAccountSyncMessage {
        WatchAccountSyncMessage(
            kind: message[messageKindKey] as? String,
            data: dataKeys.reduce(into: [:]) { values, key in
                values[key] = message[key] as? Data
            }
        )
    }

    static func snapshot(from message: WatchAccountSyncMessage) -> WatchAccountSnapshot? {
        guard let data = message.data[snapshotDataKey] else { return nil }
        return try? JSONDecoder().decode(WatchAccountSnapshot.self, from: data)
    }

    static func localFavorites(from message: WatchAccountSyncMessage) -> [WatchLocalFavoriteItem]? {
        guard let data = message.data[localFavoritesDataKey] else { return nil }
        return try? JSONDecoder().decode([WatchLocalFavoriteItem].self, from: data)
    }

    static func localFavoriteDeletions(from message: WatchAccountSyncMessage) -> [WatchLocalFavoriteDeletion] {
        guard let data = message.data[localFavoriteDeletionsDataKey],
              let deletions = try? JSONDecoder().decode([WatchLocalFavoriteDeletion].self, from: data) else {
            return []
        }
        return deletions
    }

    static func readLater(from message: WatchAccountSyncMessage) -> [WatchReadLaterItem]? {
        guard let data = message.data[readLaterDataKey] else { return nil }
        return try? JSONDecoder().decode([WatchReadLaterItem].self, from: data)
    }

    static func readLaterDeletions(from message: WatchAccountSyncMessage) -> [WatchReadLaterDeletion] {
        guard let data = message.data[readLaterDeletionsDataKey],
              let deletions = try? JSONDecoder().decode([WatchReadLaterDeletion].self, from: data) else {
            return []
        }
        return deletions
    }

    static func readingHistory(from message: WatchAccountSyncMessage) -> [WatchReadingHistoryRecord]? {
        guard let data = message.data[readingHistoryDataKey] else { return nil }
        return try? JSONDecoder().decode([WatchReadingHistoryRecord].self, from: data)
    }

    static func readingHistoryDeletions(
        from message: WatchAccountSyncMessage
    ) -> [WatchReadingHistoryDeletion] {
        guard let data = message.data[readingHistoryDeletionsDataKey],
              let deletions = try? JSONDecoder().decode(
                [WatchReadingHistoryDeletion].self,
                from: data
              ) else {
            return []
        }
        return deletions
    }

    static func isSnapshotRequest(_ message: WatchAccountSyncMessage) -> Bool {
        message.kind == requestSnapshotKind
    }

    static func isLocalFavoritesSync(_ message: WatchAccountSyncMessage) -> Bool {
        message.kind == localFavoritesSyncKind
    }

    static func isReadLaterSync(_ message: WatchAccountSyncMessage) -> Bool {
        message.kind == readLaterSyncKind
    }

    static func isReadingHistorySync(_ message: WatchAccountSyncMessage) -> Bool {
        message.kind == readingHistorySyncKind
    }
}

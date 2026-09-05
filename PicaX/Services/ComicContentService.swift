import CFNetwork
import Foundation

enum AppNetworkSettings {
    private enum Key {
        nonisolated static let useProxy = "settings.network.useProxy"
        nonisolated static let proxyHost = "settings.network.proxyHost"
        nonisolated static let proxyPort = "settings.network.proxyPort"
        nonisolated static let imageQuality = "settings.network.imageQuality"
        nonisolated static let retryCount = "settings.network.retryCount"
    }

    private nonisolated static var defaults: UserDefaults {
        .standard
    }

    nonisolated static var retryAttempts: Int {
        let retryCount = defaults.object(forKey: Key.retryCount) == nil ? 2 : defaults.integer(forKey: Key.retryCount)
        return min(max(retryCount, 0), 5) + 1
    }

    nonisolated static var picacgImageQuality: String {
        switch defaults.string(forKey: Key.imageQuality) ?? "均衡" {
        case "省流":
            return "low"
        case "高清":
            return "high"
        case "原图":
            return "original"
        default:
            return "middle"
        }
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90

        let host = (defaults.string(forKey: Key.proxyHost) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if defaults.bool(forKey: Key.useProxy), !host.isEmpty {
            let storedPort = defaults.object(forKey: Key.proxyPort) == nil ? 7890 : defaults.integer(forKey: Key.proxyPort)
            let port = min(max(storedPort, 1), 65535)
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        }

        return URLSession(configuration: configuration)
    }
}

struct ComicContentService: Sendable {
    let session: URLSession
    private let localStore: LocalFavoritesStore

    nonisolated init(session: URLSession? = nil, localStore: LocalFavoritesStore = LocalFavoritesStore()) {
        self.session = session ?? AppNetworkSettings.makeSession()
        self.localStore = localStore
    }

    nonisolated func warmNhentaiTagNameCache(for items: [ComicListItem]) {
        NhentaiTagNameCacheWarmupService.warm(items: items)
    }

    var localFolders: [LocalFavoriteFolder] {
        localStore.folders
    }

    func loadExplore(platform: ComicPlatform, entry: ComicExploreEntry, account: PlatformAccount?, page: Int = 1) async throws -> [ComicListItem] {
        guard ComicExploreEntry.availableEntries(for: platform).contains(entry) else {
            throw ComicContentError.unsupported("\(platform.title) 当前没有\(entry.title)入口。")
        }
        switch platform {
        case .picacg:
            return try await loadPicacgExplore(entry: entry, page: page, account: account)
        case .nhentai:
            return try await loadNhentaiExplore(entry: entry, page: page)
        case .eHentai:
            return try await loadEhentaiExplore(entry: entry, page: page)
        case .htManga:
            return try await loadHtMangaExplore(entry: entry, page: page)
        case .jmComic:
            return try await loadJmComicExplore(entry: entry, page: page)
        case .local:
            return []
        case .hitomi:
            return try await loadHitomiExplore(entry: entry, page: page)
        }
    }

    func loadEhentaiSubscription(page: Int = 1) async throws -> [ComicListItem] {
        try await loadEhentaiWatched(page: page)
    }

    func loadFavorites(account: PlatformAccount, folder: PlatformFavoriteFolder? = nil) async throws -> [ComicListItem] {
        try await loadFavoritePage(account: account, folder: folder, page: 1).items
    }

    func loadFavoritePage(account: PlatformAccount, folder: PlatformFavoriteFolder? = nil, page: Int = 1) async throws -> ComicFavoritePage {
        let page = max(page, 1)
        switch account.platform {
        case .picacg:
            return try await loadPicacgFavorites(account: account, page: page)
        case .nhentai:
            return try await loadNhentaiFavorites(account: account, page: page)
        case .eHentai:
            return try await loadEhentaiFavorites(account: account, folderID: folder?.id, page: page)
        case .htManga:
            return try await loadHtMangaFavorites(account: account, folderID: folder?.id, page: page)
        case .jmComic:
            return try await loadJmComicFavorites(account: account, folderID: folder?.id, page: page)
        case .hitomi, .local:
            throw ComicContentError.unsupported("Hitomi 没有平台收藏接口。")
        }
    }

    func loadLocalFavorites(folder: LocalFavoriteFolder) -> [ComicListItem] {
        localStore.items(folderID: folder.id)
    }

    func addLocalFavorite(item: ComicListItem, folder: LocalFavoriteFolder) {
        localStore.add(item: item, folderID: folder.id)
    }

    func supportsPlatformFavorite(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .nhentai, .eHentai, .jmComic, .htManga:
            true
        case .hitomi, .local:
            false
        }
    }

    func supportsPlatformFavoriteFolders(platform: ComicPlatform) -> Bool {
        switch platform {
        case .eHentai, .jmComic, .htManga:
            true
        case .picacg, .nhentai, .hitomi, .local:
            false
        }
    }

    func supportsLike(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .jmComic:
            true
        case .nhentai, .eHentai, .htManga, .hitomi, .local:
            false
        }
    }

    func supportsCommentPosting(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .jmComic:
            true
        case .eHentai:
            true
        case .nhentai, .htManga, .hitomi, .local:
            false
        }
    }

    func setComicLiked(item: ComicListItem, isLiked: Bool, account: PlatformAccount?) async throws {
        switch item.platform {
        case .picacg:
            try await togglePicacgComicLike(item: item, account: account)
        case .jmComic:
            if isLiked {
                try await likeJmComic(item: item)
            }
        case .nhentai, .eHentai, .htManga, .hitomi, .local:
            throw ComicContentError.unsupported("\(item.platformTitle) 当前没有可用点赞接口。")
        }
    }

    func loadPlatformFavoriteFolders(item: ComicListItem, account: PlatformAccount?) async throws -> [PlatformFavoriteFolder] {
        try await loadPlatformFavoriteFolders(platform: item.platform, account: account)
    }

    func loadPlatformFavoriteFolders(platform: ComicPlatform, account: PlatformAccount?) async throws -> [PlatformFavoriteFolder] {
        switch platform {
        case .picacg:
            _ = try await picacgToken(account: account)
            return [PlatformFavoriteFolder(id: "default", title: "云端收藏夹", subtitle: "PicACG 默认收藏", platform: .picacg)]
        case .nhentai:
            guard account != nil else {
                throw ComicContentError.loginRequired("NHentai 收藏需要先登录平台账号。")
            }
            return [PlatformFavoriteFolder(id: "default", title: "云端收藏夹", subtitle: "NHentai 默认收藏", platform: .nhentai)]
        case .eHentai:
            return try await loadEhentaiFavoriteFolders(account: account)
        case .jmComic:
            return try await loadJmComicFavoriteFolders(account: account)
        case .htManga:
            return try await loadHtMangaFavoriteFolders(account: account)
        case .hitomi, .local:
            throw ComicContentError.unsupported("\(platform.title) 当前没有可用平台收藏写入接口。")
        }
    }

    func addPlatformFavorite(item: ComicListItem, folder: PlatformFavoriteFolder, account: PlatformAccount?) async throws {
        switch item.platform {
        case .picacg:
            try await addPicacgFavorite(item: item, account: account)
        case .nhentai:
            try await addNhentaiFavorite(item: item, account: account)
        case .eHentai:
            try await addEhentaiFavorite(item: item, folderID: folder.id, account: account)
        case .jmComic:
            try await addJmComicFavorite(item: item, folderID: folder.id, account: account)
        case .htManga:
            try await addHtMangaFavorite(item: item, folderID: folder.id, account: account)
        case .hitomi, .local:
            throw ComicContentError.unsupported("\(item.platformTitle) 当前没有可用平台收藏写入接口。")
        }
    }

    func validateLogin(platform: ComicPlatform, username: String, password: String) async throws -> PlatformAccount {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            throw PlatformAccountError.emptyUsername
        }
        guard !trimmedPassword.isEmpty else {
            throw PlatformAccountError.emptyPassword
        }

        switch platform {
        case .picacg:
            let token = try await picacgLoginToken(email: trimmedUsername, password: trimmedPassword)
            let profile = try await loadPicacgProfile(token: token)
            let account = PlatformAccount(
                platform: platform,
                username: trimmedUsername,
                credential: PlatformCredential(
                    token: token,
                    refreshToken: nil,
                    tokenType: nil,
                    password: nil,
                    cookies: [],
                    userAgent: nil,
                    baseURL: "https://picaapi.picacomic.com",
                    source: .api,
                    profile: PlatformAccountProfile(email: profile.email, username: profile.id, nickname: profile.name)
                )
            )
            if UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.picacgAutoPunchIn) {
                try? await picacgPunchIn(account: account)
            }
            return account
        case .htManga:
            let cookies = HTTPCookieStorage()
            try await htMangaLogin(username: trimmedUsername, password: trimmedPassword, baseURL: htMangaBaseURL, cookies: cookies)
            let account = PlatformAccount(
                platform: platform,
                username: trimmedUsername,
                credential: PlatformCredential(
                    token: nil,
                    refreshToken: nil,
                    tokenType: nil,
                    password: nil,
                    cookies: storedCookies(from: cookies, baseURLs: [htMangaBaseURL]),
                    userAgent: nil,
                    baseURL: htMangaBaseURL,
                    source: .api,
                    profile: PlatformAccountProfile(email: nil, username: trimmedUsername, nickname: nil)
                )
            )
            guard account.hasReusableCredential else { throw PlatformAccountError.emptyCredential }
            return account
        case .nhentai:
            throw ComicContentError.loginRequired("NHentai 账号校验需要 Web 登录后的 access_token，请通过网页登录。")
        case .eHentai:
            throw ComicContentError.loginRequired("E-Hentai 账号校验需要网页登录 cookie，请通过网页登录。")
        case .jmComic:
            let cookies = HTTPCookieStorage()
            let loginInfo = try await jmLoginInfo(username: trimmedUsername, password: trimmedPassword, cookies: cookies)
            let account = PlatformAccount(
                platform: platform,
                username: trimmedUsername,
                credential: PlatformCredential(
                    token: nil,
                    refreshToken: nil,
                    tokenType: nil,
                    password: trimmedPassword,
                    cookies: storedCookies(from: cookies, baseURLs: [loginInfo.baseURL]),
                    userAgent: nil,
                    baseURL: loginInfo.baseURL,
                    source: .api,
                    profile: PlatformAccountProfile(email: nil, username: loginInfo.userID, nickname: trimmedUsername)
                )
            )
            guard account.hasReusableCredential else { throw PlatformAccountError.emptyCredential }
            if UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.jmAutoCheckIn) {
                _ = try? await jmComicCheckIn(account: account)
            }
            return account
        case .hitomi, .local:
            throw ComicContentError.unsupported("Hitomi 没有账号密码登录接口。")
        }
    }

    func loadDetail(item: ComicListItem, account: PlatformAccount?) async throws -> ComicDetailInfo {
        switch item.platform {
        case .picacg:
            return try await loadPicacgDetail(item: item, account: account)
        case .nhentai:
            return try await loadNhentaiDetail(item: item)
        case .eHentai:
            return try await loadEhentaiDetail(item: item, account: account)
        case .htManga:
            return try await loadHtMangaDetail(item: item)
        case .jmComic:
            return try await loadJmComicDetail(item: item)
        case .local:
            guard let record = PicaXSQLiteStore.loadDownloadRecords().first(where: { $0.item.readingHistoryID == item.readingHistoryID }),
                  let detail = record.detail else { throw ComicContentError.invalidResponse("本地漫画文件已不可用。") }
            return detail
        case .hitomi:
            return try await loadHitomiDetail(item: item)
        }
    }

    func loadTagComics(tag: ComicTagReference, account: PlatformAccount?, page: Int = 1) async throws -> [ComicListItem] {
        switch tag.platform {
        case .picacg:
            if let author = tag.query.removingPrefix("picacg:a:") {
                return try await loadPicacgFilteredComics(filter: "a", value: author, page: page, account: account)
            }
            if let creatorID = tag.query.removingPrefix("picacg:ca:") {
                return try await loadPicacgFilteredComics(filter: "ca", value: creatorID, page: page, account: account)
            }
            if let category = tag.query.removingPrefix("category:") {
                return try await loadPicacgCategoryComics(category: category, page: page, account: account)
            }
            return try await searchPicacg(keyword: tag.query, page: page, account: account)
        case .nhentai:
            return try await searchNhentai(query: searchKeywordByTranslatingChineseTerms(tag.query, for: .nhentai), page: page)
        case .eHentai:
            return try await searchEhentai(query: searchKeywordByTranslatingChineseTerms(tag.query, for: .eHentai), page: page)
        case .htManga:
            return try await searchHtManga(tag: tag, page: page)
        case .jmComic:
            return try await searchJmComic(query: BlockingKeywordService.jmKeywordByApplyingBlocks(to: tag.query), page: page)
        case .local:
            return []
        case .hitomi:
            return try await searchHitomi(tag: tag, page: page)
        }
    }

    func searchComics(
        platform: ComicPlatform,
        query: ComicSearchClause,
        account: PlatformAccount?,
        page: Int = 1,
        options: ComicSearchAdvancedOptions? = nil
    ) async throws -> [ComicListItem] {
        let trimmed = query.keyword(for: platform).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let resolvedOptions = options ?? ComicSearchAdvancedOptions()

        switch platform {
        case .picacg:
            return try await searchPicacg(keyword: trimmed, page: page, account: account, sort: resolvedOptions.sortValue(for: platform))
        case .nhentai:
            let translatedKeyword = searchKeywordByTranslatingChineseTerms(trimmed, for: platform)
            return try await searchNhentai(query: resolvedOptions.keyword(translatedKeyword, for: platform), page: page, sort: resolvedOptions.sortValue(for: platform))
        case .eHentai:
            let translatedKeyword = searchKeywordByTranslatingChineseTerms(trimmed, for: platform)
            return try await searchEhentai(query: resolvedOptions.keyword(translatedKeyword, for: platform), page: page)
        case .htManga:
            let tag = ComicTagReference(title: trimmed, query: trimmed, platform: platform, urlString: nil)
            return try await searchHtManga(tag: tag, page: page)
        case .jmComic:
            return try await searchJmComic(
                query: BlockingKeywordService.jmKeywordByApplyingBlocks(to: trimmed),
                page: page,
                sort: resolvedOptions.sortValue(for: platform)
            )
        case .local:
            return PicaXSQLiteStore.loadDownloadRecords().filter {
                $0.item.platform == .local
            }.map(\.item).filter { item in
                query.terms.allSatisfy { item.title.localizedCaseInsensitiveContains($0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) }
            }.dropFirst((max(page, 1) - 1) * 30).prefix(30).map { $0 }
        case .hitomi:
            return try await searchHitomi(terms: query.terms, page: page)
        }
    }

    private func searchKeywordByTranslatingChineseTerms(_ keyword: String, for platform: ComicPlatform) -> String {
        guard SearchSettingsKey.translatesChineseSearchTerms() else { return keyword }
        switch platform {
        case .nhentai:
            return NhentaiTagSuggestionService.searchQueryByTranslatingChineseTerms(keyword)
        case .eHentai:
            return EhTagTranslationService.searchQueryByTranslatingChineseTerms(keyword)
        case .picacg, .htManga, .jmComic, .hitomi, .local:
            return keyword
        }
    }

    func loadCategories(platform: ComicPlatform, account: PlatformAccount?) async throws -> [ComicCategoryItem] {
        switch platform {
        case .picacg:
            return try await loadPicacgCategories(account: account)
        default:
            return defaultCategories(platform: platform)
        }
    }

    func loadComments(item: ComicListItem, account: PlatformAccount?, page: Int = 1) async throws -> [ComicComment] {
        switch item.platform {
        case .picacg:
            return try await loadPicacgComments(item: item, account: account, page: page)
        case .nhentai:
            return try await loadNhentaiComments(item: item)
        case .eHentai:
            return try await loadEhentaiComments(item: item, account: account)
        case .jmComic:
            return try await loadJmComicComments(item: item, page: page)
        case .htManga, .hitomi, .local:
            throw ComicContentError.unsupported("\(item.platformTitle) 没有可用评论接口。")
        }
    }

    func supportsChapterComments(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .nhentai, .eHentai, .jmComic:
            true
        case .htManga, .hitomi, .local:
            false
        }
    }

    func loadChapterComments(
        item: ComicListItem,
        chapter: ComicChapter,
        account: PlatformAccount?,
        page: Int = 1
    ) async throws -> [ComicComment] {
        switch item.platform {
        case .picacg:
            return try await loadPicacgChapterComments(item: item, chapter: chapter, account: account, page: page)
        case .jmComic:
            return try await loadJmComicChapterComments(chapter: chapter, page: page)
        case .nhentai, .eHentai:
            return try await loadComments(item: item, account: account, page: page)
        case .htManga, .hitomi, .local:
            throw ComicContentError.unsupported("\(item.platformTitle) 没有可用章节评论接口。")
        }
    }

    func loadChapterImages(item: ComicListItem, chapter: ComicChapter, account: PlatformAccount?) async throws -> [ComicChapterImage] {
        let urls: [String]
        switch item.platform {
        case .picacg:
            urls = try await loadPicacgChapterImages(item: item, chapter: chapter, account: account)
        case .nhentai:
            urls = try await loadNhentaiImages(item: item)
        case .eHentai:
            urls = try await loadEhentaiImages(item: item, account: account)
        case .htManga:
            urls = try await loadHtMangaImages(item: item)
        case .jmComic:
            urls = try await loadJmComicChapterImages(chapter: chapter)
        case .local:
            guard let record = PicaXSQLiteStore.loadDownloadRecords().first(where: { $0.item.readingHistoryID == item.readingHistoryID }),
                  let index = record.chapters.first(where: { $0.chapter.id == chapter.id })?.index else {
                throw ComicContentError.invalidResponse("本地章节已不可用。")
            }
            return await DownloadService.localChapterImages(item: item, chapter: chapter, chapterIndex: index)
        case .hitomi:
            urls = try await loadHitomiImages(item: item)
        }
        return urls.enumerated().map { index, url in
            ComicChapterImage(id: "\(chapter.id)-\(index + 1)", urlString: url)
        }
    }

    func prefetchImages(urlStrings: [String]) async {
        for urlString in urlStrings {
            guard !Task.isCancelled, let url = URL.picaxResolved(from: urlString) else { continue }
            guard url.picaxLocalFileURL == nil else { continue }
            _ = try? await ImageCacheService.prefetchImageData(for: url)
        }
    }

    func loadImageData(urlString: String, storesInCache: Bool = true) async throws -> Data {
        guard let url = URL.picaxResolved(from: urlString) else {
            throw ComicContentError.invalidURL(urlString)
        }

        return try await ImageCacheService.data(for: url, storesInCache: storesInCache)
    }

    func postComment(item: ComicListItem, content: String, account: PlatformAccount?) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComicContentError.invalidResponse("请输入评论内容。")
        }

        switch item.platform {
        case .picacg:
            try await postPicacgComment(item: item, content: trimmed, account: account)
        case .eHentai:
            try await postEhentaiComment(item: item, content: trimmed, account: account)
        case .jmComic:
            try await postJmComicComment(item: item, content: trimmed, account: account)
        case .nhentai, .htManga, .hitomi, .local:
            throw ComicContentError.unsupported("\(item.platformTitle) 当前不支持发送评论。")
        }
    }

    func loadPicacgProfile(account: PlatformAccount?) async throws -> PicacgUserProfile {
        let token = try await picacgToken(account: account)
        return try await loadPicacgProfile(token: token)
    }

    func loadPicacgProfile(token: String) async throws -> PicacgUserProfile {
        let json = try await picacgJSON(path: "users/profile", token: token)
        guard let user = json.value(at: ["data", "user"]) as? [String: Any] else {
            throw ComicContentError.invalidResponse("PicACG 用户资料响应缺少 user。")
        }
        return picacgProfile(from: user)
    }

    func loadPicacgUserComments(account: PlatformAccount?, page: Int = 1) async throws -> PicacgUserCommentsPageData {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "users/my-comments?page=\(max(page, 1))", token: token)
        guard let comments = json.value(at: ["data", "comments"]) as? [String: Any],
              let docs = comments["docs"] as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("PicACG 我的评论响应缺少 comments。")
        }
        return PicacgUserCommentsPageData(
            comments: docs.compactMap { picacgUserComment(from: $0) },
            page: comments.intValue(for: "page") ?? page,
            pages: comments.intValue(for: "pages") ?? page
        )
    }

    func picacgPunchIn(account: PlatformAccount?) async throws {
        let token = try await picacgToken(account: account)
        _ = try await picacgJSON(path: "users/punch-in", method: "POST", token: token)
    }

    func jmComicCheckIn(account: PlatformAccount?) async throws -> String {
        guard let account else {
            throw ComicContentError.loginRequired("JMComic 签到需要先登录平台账号。")
        }
        let context = try await jmAuthenticatedContext(account: account)
        let cookies = context.cookies
        let loginInfo = context.loginInfo
        guard let userID = loginInfo.userID, !userID.isEmpty else {
            throw ComicContentError.invalidResponse("JMComic 登录响应缺少用户 ID。")
        }
        guard let daily = try await jmJSON(path: "daily?user_id=\(userID.urlEncoded)", cookies: cookies, baseURL: loginInfo.baseURL) as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 签到响应不是对象。")
        }
        guard let dailyID = jmString(daily["daily_id"]), !dailyID.isEmpty else {
            throw ComicContentError.invalidResponse("JMComic 签到响应缺少 daily_id。")
        }
        guard let result = try await jmJSON(
            path: "daily_chk",
            method: "POST",
            body: "user_id=\(userID.urlEncoded)&daily_id=\(dailyID.urlEncoded)&",
            cookies: cookies,
            baseURL: loginInfo.baseURL
        ) as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 签到结果不是对象。")
        }
        return jmString(result["msg"]) ?? "签到完成"
    }

    func refreshJmAPIEndpoints() async throws -> JmAPIUpdateResult {
        let baseURLs = try await loadRemoteJmAPIBaseURLs()
        UserDefaults.standard.set(baseURLs.joined(separator: "\n"), forKey: PlatformFeatureSettingsKey.jmCustomAPIBaseURLs)
        let appVersion = try? await loadRemoteJmAppVersion(baseURLs: baseURLs)
        if let appVersion {
            UserDefaults.standard.set(appVersion, forKey: PlatformFeatureSettingsKey.jmAppVersion)
        }
        return JmAPIUpdateResult(baseURLs: baseURLs, appVersion: appVersion)
    }

    func refreshJmAppVersion() async throws -> String {
        let version = try await loadRemoteJmAppVersion(baseURLs: PlatformFeatureSettings.jmAPIBaseURLs())
        UserDefaults.standard.set(version, forKey: PlatformFeatureSettingsKey.jmAppVersion)
        return version
    }

    func testPicacgAPIChannels(account: PlatformAccount?) async throws -> [SourceRouteSpeedTestResult] {
        let token = try await picacgToken(account: account)
        var results: [SourceRouteSpeedTestResult] = []

        for channel in ["1", "2", "3"] {
            try Task.checkCancellation()
            let startedAt = Date()
            do {
                _ = try await picacgJSON(path: "categories", token: token, appChannel: channel)
                results.append(
                    SourceRouteSpeedTestResult(
                        id: channel,
                        endpoint: "picaapi.picacomic.com",
                        milliseconds: max(Int(Date().timeIntervalSince(startedAt) * 1_000), 1),
                        errorMessage: nil
                    )
                )
            } catch where error.isTaskCancellation {
                throw CancellationError()
            } catch {
                results.append(
                    SourceRouteSpeedTestResult(
                        id: channel,
                        endpoint: "picaapi.picacomic.com",
                        milliseconds: nil,
                        errorMessage: (error as? URLError)?.code == .timedOut ? "超时" : "失败"
                    )
                )
            }
        }

        return results
    }

    func testJmAPIEndpoints() async -> [SourceRouteSpeedTestResult] {
        let configuredBaseURLs = PlatformFeatureSettings.jmAPIBaseURLs()
        let candidates = JmAPIEndpoint.allCases.compactMap { endpoint -> SourceRouteSpeedTestCandidate? in
            guard endpoint != .auto else { return nil }
            let baseURL = endpoint.dynamicIndex.flatMap { index in
                configuredBaseURLs.indices.contains(index) ? configuredBaseURLs[index] : nil
            } ?? endpoint.baseURLString
            guard let baseURL,
                  let url = URL(string: "\(PlatformFeatureSettings.normalizedBaseURL(baseURL, fallback: ""))/latest?page=1") else {
                return nil
            }
            let time = Int(Date().timeIntervalSince1970)
            var request = speedTestRequest(url: url)
            jmHeaders(time: time, post: false).forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
            return SourceRouteSpeedTestCandidate(id: endpoint.id, request: request, acceptsClientError: false)
        }
        return await testSourceRoutes(candidates)
    }

    func testJmImageEndpoints(customBaseURL: String) async -> [SourceRouteSpeedTestResult] {
        let candidates = JmImageEndpoint.allCases.compactMap { endpoint -> SourceRouteSpeedTestCandidate? in
            let baseURL = endpoint.baseURLString ?? PlatformFeatureSettings.normalizedBaseURL(
                customBaseURL,
                fallback: JmImageEndpoint.defaultBaseURL
            )
            guard let url = URL(string: baseURL) else { return nil }
            var request = speedTestRequest(url: url)
            request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            return SourceRouteSpeedTestCandidate(id: endpoint.id, request: request, acceptsClientError: true)
        }
        return await testSourceRoutes(candidates)
    }

    func testEhentaiSites() async -> [SourceRouteSpeedTestResult] {
        let candidates = EhentaiSite.allCases.compactMap { site -> SourceRouteSpeedTestCandidate? in
            guard let url = URL(string: site.rawValue) else { return nil }
            var request = speedTestRequest(url: url)
            webHeaders(referer: site.rawValue).forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
            return SourceRouteSpeedTestCandidate(id: site.id, request: request, acceptsClientError: false)
        }
        return await testSourceRoutes(candidates)
    }

    func testHtMangaAPIBaseURLs(_ baseURLs: [String]) async -> [SourceRouteSpeedTestResult] {
        let candidates = uniqueBaseURLs(baseURLs).compactMap { baseURL -> SourceRouteSpeedTestCandidate? in
            guard let url = URL(string: "\(baseURL)/albums.html") else { return nil }
            var request = speedTestRequest(url: url)
            webHeaders(referer: baseURL).forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
            return SourceRouteSpeedTestCandidate(id: baseURL, request: request, acceptsClientError: false)
        }
        return await testSourceRoutes(candidates)
    }

    private func speedTestRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func testSourceRoutes(_ candidates: [SourceRouteSpeedTestCandidate]) async -> [SourceRouteSpeedTestResult] {
        await withTaskGroup(of: SourceRouteSpeedTestResult.self) { group in
            for candidate in candidates {
                group.addTask {
                    await self.measureSourceRoute(candidate)
                }
            }

            var resultsByID: [String: SourceRouteSpeedTestResult] = [:]
            for await result in group {
                resultsByID[result.id] = result
            }
            return candidates.compactMap { resultsByID[$0.id] }
        }
    }

    private func measureSourceRoute(_ candidate: SourceRouteSpeedTestCandidate) async -> SourceRouteSpeedTestResult {
        let startedAt = Date()
        do {
            try Task.checkCancellation()
            let (_, response) = try await session.data(for: candidate.request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw ComicContentError.invalidResponse("测速请求没有返回 HTTP 响应。")
            }
            let succeeds = (200..<300).contains(response.statusCode)
                || (candidate.acceptsClientError && (400..<500).contains(response.statusCode))
            guard succeeds else {
                throw ComicContentError.server("HTTP \(response.statusCode)")
            }
            let milliseconds = max(Int(Date().timeIntervalSince(startedAt) * 1_000), 1)
            return SourceRouteSpeedTestResult(
                id: candidate.id,
                endpoint: candidate.request.url?.host ?? candidate.request.url?.absoluteString ?? candidate.id,
                milliseconds: milliseconds,
                errorMessage: nil
            )
        } catch where error.isTaskCancellation {
            return SourceRouteSpeedTestResult(
                id: candidate.id,
                endpoint: candidate.request.url?.host ?? candidate.id,
                milliseconds: nil,
                errorMessage: "已取消"
            )
        } catch {
            let errorMessage: String
            if (error as? URLError)?.code == .timedOut {
                errorMessage = "超时"
            } else {
                errorMessage = "失败"
            }
            return SourceRouteSpeedTestResult(
                id: candidate.id,
                endpoint: candidate.request.url?.host ?? candidate.id,
                milliseconds: nil,
                errorMessage: errorMessage
            )
        }
    }

    func loadEhentaiProfiles() async throws -> [EhentaiProfile] {
        guard let url = URL(string: "\(ehentaiBaseURL)/uconfig.php") else {
            throw ComicContentError.invalidURL("E-Hentai Profile")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: ehentaiBaseURL))
        guard let selectHTML = html.firstRegexCapture(#"<select[^>]+name="profile_set"[^>]*>.*?</select>"#) else {
            throw ComicContentError.invalidResponse("E-Hentai 没有返回 Profile 列表。")
        }
        let profiles = selectHTML.regexMatches(#"<option[^>]+value="([^"]*)"[^>]*>.*?</option>"#, options: [.dotMatchesLineSeparators]).compactMap { row -> EhentaiProfile? in
            let id = row.firstRegexCapture(#"value="([^"]*)""#) ?? ""
            let title = row.strippingHTML.nilIfEmpty ?? (id.isEmpty ? "Do not modify" : id)
            return EhentaiProfile(id: id, title: title)
        }
        guard !profiles.isEmpty else {
            throw ComicContentError.invalidResponse("E-Hentai 没有返回 Profile 列表。")
        }
        return [EhentaiProfile(id: "", title: "Do not modify")] + profiles.filter { !$0.id.isEmpty }
    }

    func loadHtMangaAPIBaseURLs() async throws -> [String] {
        guard let url = URL(string: "https://raw.githubusercontent.com/ccbkv/PicaComicapitxt/refs/heads/main/htmanga_api_list.txt") else {
            throw ComicContentError.invalidURL("绅士漫画 API 分流")
        }
        let text = try await requestString(url: url, headers: webHeaders(referer: "https://github.com/ccbkv/PicaComicapitxt"))
        let values = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { value -> String? in
                if let data = Data(base64Encoded: value),
                   let decoded = String(data: data, encoding: .utf8),
                   !decoded.isEmpty {
                    return PlatformFeatureSettings.normalizedBaseURL(decoded, fallback: "")
                }
                return PlatformFeatureSettings.normalizedBaseURL(value, fallback: "")
            }
            .filter { URL(string: $0)?.host != nil }
        guard !values.isEmpty else {
            throw ComicContentError.invalidResponse("绅士漫画没有返回可用 API 分流。")
        }
        return uniqueBaseURLs(values)
    }
}

nonisolated private struct SourceRouteSpeedTestCandidate: Sendable {
    let id: String
    let request: URLRequest
    let acceptsClientError: Bool
}

struct ComicFavoritePage: Equatable {
    let items: [ComicListItem]
    let page: Int
    let hasMore: Bool
}

struct PicacgChapterInfo {
    let id: String
    let title: String
    let order: String
}

struct JmLoginInfo {
    let baseURL: String
    let userID: String?
}

enum NhentaiTagNameCacheWarmupService {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var warmingItemIDs = Set<String>()
    private nonisolated static let maxItemsPerBatch = 12

    nonisolated static func warm(items: [ComicListItem]) {
        let candidates = reserveCandidates(from: items)
        guard !candidates.isEmpty else { return }

        Task.detached(priority: .utility) {
            defer { release(candidates) }

            let session = AppNetworkSettings.makeSession()
            for item in candidates {
                if Task.isCancelled { break }
                guard let itemRecords = try? await tagRecords(for: item, session: session) else {
                    continue
                }
                PicaXSQLiteStore.upsertNhentaiTagNames(itemRecords)
            }
        }
    }

    private nonisolated static func reserveCandidates(from items: [ComicListItem]) -> [ComicListItem] {
        let nhentaiItems = items.filter { $0.platform == .nhentai }
        let cachedIDs = Set(PicaXSQLiteStore.loadNhentaiTagNames(ids: nhentaiItems.flatMap(tagIDs(in:))).keys)
        var candidates: [ComicListItem] = []
        candidates.reserveCapacity(min(maxItemsPerBatch, nhentaiItems.count))

        lock.lock()
        defer { lock.unlock() }

        for item in nhentaiItems {
            guard candidates.count < maxItemsPerBatch else { break }
            let ids = tagIDs(in: item)
            guard ids.contains(where: { !cachedIDs.contains($0) }) else { continue }
            guard warmingItemIDs.insert(item.readingHistoryID).inserted else { continue }
            candidates.append(item)
        }

        return candidates
    }

    private nonisolated static func release(_ items: [ComicListItem]) {
        lock.lock()
        defer { lock.unlock() }
        for item in items {
            warmingItemIDs.remove(item.readingHistoryID)
        }
    }

    private nonisolated static func tagIDs(in item: ComicListItem) -> [Int] {
        item.tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("tag:") else { return nil }
            return Int(trimmed.dropFirst("tag:".count))
        }
    }

    private nonisolated static func tagRecords(for item: ComicListItem, session: URLSession) async throws -> [StoredNhentaiTagName] {
        let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let url = URL(string: "https://nhentai.net/api/v2/galleries/\(id)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = nhentaiHeaders
        let (data, response) = try await session.data(for: request)
        guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(statusCode) else {
            return []
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = json["tags"] as? [[String: Any]] else {
            return []
        }

        return tags.compactMap { tag in
            guard let id = tag.intValue(for: "id"), id > 0 else { return nil }
            let name = (tag["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let group = (tag["type"] as? String ?? "tag")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return StoredNhentaiTagName(id: id, group: group.isEmpty ? "tag" : group, name: name)
        }
    }

    private nonisolated static var nhentaiHeaders: [String: String] {
        [
            "Accept": "application/json",
            "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
            "Referer": "https://nhentai.net/",
            "User-Agent": PlatformWebUserAgent.normalized(nil)
        ]
    }
}











nonisolated enum ComicContentError: LocalizedError, Sendable {
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

extension Dictionary where Key == String, Value == Any {
    nonisolated func value(at path: [String]) -> Any? {
        var current: Any? = self
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    nonisolated func intValue(for key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        if let value = self[key] as? Double { return Int(value) }
        return nil
    }
}

extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result = [T: Value]()
        for (key, value) in self {
            if let transformed = transform(key) {
                result[transformed] = value
            }
        }
        return result
    }
}

extension String {
    nonisolated var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    nonisolated var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .strippingHTML
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    nonisolated func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    nonisolated func regexMatches(_ pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            Range(match.range, in: self).map { String(self[$0]) }
        }
    }

    nonisolated func firstRegexCapture(_ pattern: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[captureRange])
    }

    nonisolated func firstRegexCapturePair(_ pattern: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 2,
              let firstRange = Range(match.range(at: 1), in: self),
              let secondRange = Range(match.range(at: 2), in: self) else {
            return nil
        }
        return (String(self[firstRange]), String(self[secondRange]))
    }
}

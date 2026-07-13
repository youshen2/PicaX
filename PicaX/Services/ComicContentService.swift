import CryptoKit
import CFNetwork
import Foundation

private enum AppNetworkSettings {
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

struct ComicContentService {
    private let session: URLSession
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
        case .hitomi:
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
        case .hitomi:
            false
        }
    }

    func supportsPlatformFavoriteFolders(platform: ComicPlatform) -> Bool {
        switch platform {
        case .eHentai, .jmComic, .htManga:
            true
        case .picacg, .nhentai, .hitomi:
            false
        }
    }

    func supportsLike(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .jmComic:
            true
        case .nhentai, .eHentai, .htManga, .hitomi:
            false
        }
    }

    func supportsCommentPosting(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .jmComic:
            true
        case .eHentai:
            true
        case .nhentai, .htManga, .hitomi:
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
        case .nhentai, .eHentai, .htManga, .hitomi:
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
        case .hitomi:
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
        case .hitomi:
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
        case .hitomi:
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
        case .hitomi:
            return try await searchHitomi(tag: tag, page: page)
        }
    }

    func searchComics(
        platform: ComicPlatform,
        keyword: String,
        account: PlatformAccount?,
        page: Int = 1,
        options: ComicSearchAdvancedOptions? = nil
    ) async throws -> [ComicListItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let resolvedOptions = options ?? ComicSearchAdvancedOptions()

        switch platform {
        case .picacg:
            return try await searchPicacg(keyword: trimmed, page: page, account: account, sort: resolvedOptions.sortValue(for: platform))
        case .nhentai:
            let translatedKeyword = searchKeywordByTranslatingChineseTerms(trimmed, for: platform)
            return try await searchNhentai(query: resolvedOptions.keyword(translatedKeyword, for: platform), page: page, sort: resolvedOptions.sortValue(for: platform))
        case .eHentai:
            return try await searchEhentai(query: searchKeywordByTranslatingChineseTerms(trimmed, for: platform), page: page)
        case .htManga:
            let tag = ComicTagReference(title: trimmed, query: trimmed, platform: platform, urlString: nil)
            return try await searchHtManga(tag: tag, page: page)
        case .jmComic:
            return try await searchJmComic(
                query: BlockingKeywordService.jmKeywordByApplyingBlocks(to: trimmed),
                page: page,
                sort: resolvedOptions.sortValue(for: platform)
            )
        case .hitomi:
            let tag = ComicTagReference(title: trimmed, query: trimmed, platform: platform, urlString: nil)
            return try await searchHitomi(tag: tag, page: page)
        }
    }

    private func searchKeywordByTranslatingChineseTerms(_ keyword: String, for platform: ComicPlatform) -> String {
        guard SearchSettingsKey.translatesChineseSearchTerms() else { return keyword }
        switch platform {
        case .nhentai:
            return NhentaiTagSuggestionService.searchQueryByTranslatingChineseTerms(keyword)
        case .eHentai:
            return EhTagTranslationService.searchQueryByTranslatingChineseTerms(keyword)
        case .picacg, .htManga, .jmComic, .hitomi:
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
        case .htManga, .hitomi:
            throw ComicContentError.unsupported("\(item.platformTitle) 没有可用评论接口。")
        }
    }

    func supportsChapterComments(platform: ComicPlatform) -> Bool {
        switch platform {
        case .picacg, .nhentai, .eHentai, .jmComic:
            true
        case .htManga, .hitomi:
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
        case .htManga, .hitomi:
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
        case .nhentai, .htManga, .hitomi:
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
            throw ComicContentError.invalidURL("HT Manga API 分流")
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
            throw ComicContentError.invalidResponse("HT Manga 没有返回可用 API 分流。")
        }
        return uniqueBaseURLs(values)
    }
}

struct ComicFavoritePage: Equatable {
    let items: [ComicListItem]
    let page: Int
    let hasMore: Bool
}

private struct PicacgChapterInfo {
    let id: String
    let title: String
    let order: String
}

private struct JmLoginInfo {
    let baseURL: String
    let userID: String?
}

private enum NhentaiTagNameCacheWarmupService {
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

private extension ComicContentService {
    func singleReaderChapter(title: String = "第 1 章") -> [ComicChapter] {
        [ComicChapter(id: "1", title: title, subtitle: nil)]
    }

    func loadPicacgExplore(entry: ComicExploreEntry, page: Int, account: PlatformAccount?) async throws -> [ComicListItem] {
        let token = try await picacgToken(account: account)
        switch entry {
        case .random:
            let json = try await picacgJSON(path: "comics/random", token: token)
            return try picacgItems(from: json, arrayPath: ["data", "comics"])
        case .latest:
            let sort = PlatformFeatureSettings.picacgDefaultSort()
            let json = try await picacgJSON(path: "comics?page=\(page)&s=\(sort)", token: token)
            return try picacgItems(from: json, arrayPath: ["data", "comics", "docs"])
        case .ranking:
            guard page == 1 else { return [] }
            let json = try await picacgJSON(path: "comics/leaderboard?tt=H24&ct=VC", token: token)
            return try picacgItems(from: json, arrayPath: ["data", "comics"])
        case .search:
            throw ComicContentError.unsupported("PicACG 搜索接口需要关键词和排序条件，当前入口页还没有筛选表单。")
        }
    }

    func loadPicacgFavorites(account: PlatformAccount, page: Int = 1) async throws -> ComicFavoritePage {
        let token = try await picacgToken(account: account)
        let sort = PlatformFeatureSettings.picacgFavoriteSort()
        let page = max(page, 1)
        let json = try await picacgJSON(path: "users/favourite?s=\(sort)&page=\(page)", token: token)
        let items = try picacgItems(from: json, arrayPath: ["data", "comics", "docs"], favoriteDate: Date())
        let pageCount = (json.value(at: ["data", "comics"]) as? [String: Any])?.intValue(for: "pages")
        return ComicFavoritePage(items: items, page: page, hasMore: pageCount.map { page < $0 } ?? !items.isEmpty)
    }

    func addPicacgFavorite(item: ComicListItem, account: PlatformAccount?) async throws {
        let token = try await picacgToken(account: account)
        _ = try await picacgJSON(path: "comics/\(item.id)/favourite", method: "POST", token: token, body: Data("{}".utf8))
    }

    func togglePicacgComicLike(item: ComicListItem, account: PlatformAccount?) async throws {
        let token = try await picacgToken(account: account)
        _ = try await picacgJSON(path: "comics/\(item.id)/like", method: "POST", token: token, body: Data("{}".utf8))
    }

    func picacgToken(account: PlatformAccount?) async throws -> String {
        guard let account else {
            throw ComicContentError.loginRequired("PicACG 接口需要先登录平台账号。")
        }
        if let password = account.credential.password?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty {
            return try await picacgLoginToken(email: account.username, password: password)
        }
        if let token = account.credential.token, !token.isEmpty {
            return token
        }
        throw ComicContentError.loginRequired("PicACG 登录状态无效，请重新登录。")
    }

    func picacgLoginToken(email: String, password: String) async throws -> String {
        let path = "auth/sign-in"
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        let json = try await picacgJSON(path: path, method: "POST", token: "", body: body)
        guard let token = json.value(at: ["data", "token"]) as? String, !token.isEmpty else {
            throw ComicContentError.invalidResponse("PicACG 登录返回信息不完整。")
        }
        return token
    }

    func picacgProfile(from user: [String: Any]) -> PicacgUserProfile {
        PicacgUserProfile(
            id: user["_id"] as? String ?? "",
            email: user["email"] as? String ?? "",
            name: user["name"] as? String ?? "",
            title: user["title"] as? String ?? "User",
            level: user.intValue(for: "level") ?? 0,
            exp: user.intValue(for: "exp") ?? 0,
            slogan: user["slogan"] as? String,
            avatarURLString: picacgImageURL(from: user["avatar"] as? [String: Any]),
            frameURLString: (user["character"] as? String)?.nilIfEmpty,
            isPunched: user["isPunched"] as? Bool
        )
    }

    func picacgUserComment(from doc: [String: Any]) -> PicacgUserComment? {
        guard let id = doc["_id"] as? String,
              let comic = doc["_comic"] as? [String: Any],
              let comicID = comic["_id"] as? String else {
            return nil
        }

        return PicacgUserComment(
            id: id,
            content: doc["content"] as? String ?? "",
            comicID: comicID,
            comicTitle: comic["title"] as? String ?? "Unknown",
            timeText: doc["created_at"] as? String,
            likesCount: doc.intValue(for: "likesCount") ?? 0,
            replyCount: doc.intValue(for: "commentsCount") ?? 0,
            isLiked: doc["isLiked"] as? Bool ?? false
        )
    }

    func picacgJSON(path: String, method: String = "GET", token: String, body: Data? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "https://picaapi.picacomic.com/\(path)") else {
            throw ComicContentError.invalidURL(path)
        }
        let headers = picacgHeaders(path: path, method: method, token: token)
        return try await requestJSON(url: url, method: method, headers: headers, body: body)
    }

    func picacgItems(from json: [String: Any], arrayPath: [String], favoriteDate: Date? = nil) throws -> [ComicListItem] {
        guard let docs = json.value(at: arrayPath) as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("PicACG 响应缺少漫画列表。")
        }

        return picacgItems(from: docs, favoriteDate: favoriteDate)
    }

    func picacgItems(from docs: [[String: Any]], favoriteDate: Date? = nil) -> [ComicListItem] {
        return docs.compactMap { doc in
            guard let id = doc["_id"] as? String else { return nil }
            let thumb = doc["thumb"] as? [String: Any]
            let fileServer = thumb?["fileServer"] as? String ?? ""
            let path = thumb?["path"] as? String ?? ""
            var tags = [String]()
            tags.append(contentsOf: doc["tags"] as? [String] ?? [])
            tags.append(contentsOf: doc["categories"] as? [String] ?? [])
            return ComicListItem(
                id: id,
                platform: .picacg,
                title: doc["title"] as? String ?? "Unknown",
                subtitle: doc["author"] as? String ?? "Unknown",
                coverURLString: picacgImageURL(fileServer: fileServer, path: path) ?? "",
                tags: tags,
                pageCount: doc.intValue(for: "pagesCount"),
                likesCount: doc.intValue(for: "likesCount") ?? doc.intValue(for: "totalLikes"),
                favoriteDate: favoriteDate
            )
        }
    }

    func loadPicacgCategories(account: PlatformAccount?) async throws -> [ComicCategoryItem] {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "categories", token: token)
        guard let categories = json.value(at: ["data", "categories"]) as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("PicACG 分类响应缺少 categories。")
        }

        return categories.compactMap { category in
            guard category["isWeb"] as? Bool != true,
                  let title = category["title"] as? String,
                  !title.isEmpty else {
                return nil
            }

            let thumb = category["thumb"] as? [String: Any]
            let fileServer = thumb?["fileServer"] as? String ?? ""
            let path = thumb?["path"] as? String ?? ""
            let coverURLString = picacgImageURL(fileServer: fileServer, path: path)

            return ComicCategoryItem(
                title: title,
                query: "category:\(title)",
                platform: .picacg,
                subtitle: "PicACG 分类",
                coverURLString: coverURLString,
                groupTitle: nil
            )
        }
    }

    func loadPicacgCategoryComics(category: String, page: Int, account: PlatformAccount?) async throws -> [ComicListItem] {
        try await loadPicacgFilteredComics(filter: "c", value: category, page: page, account: account)
    }

    func loadPicacgFilteredComics(filter: String, value: String, page: Int, account: PlatformAccount?) async throws -> [ComicListItem] {
        let token = try await picacgToken(account: account)
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        let sort = PlatformFeatureSettings.picacgDefaultSort()
        let json = try await picacgJSON(path: "comics?page=\(page)&\(filter)=\(encodedValue)&s=\(sort)", token: token)
        return try picacgItems(from: json, arrayPath: ["data", "comics", "docs"])
    }

    func loadPicacgComments(item: ComicListItem, account: PlatformAccount?, page: Int) async throws -> [ComicComment] {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "comics/\(item.id)/comments?page=\(page)", token: token)
        guard let docs = json.value(at: ["data", "comments", "docs"]) as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("PicACG 评论响应缺少 comments。")
        }
        return docs.map { picacgComment(from: $0) }
    }

    func loadPicacgChapterComments(item: ComicListItem, chapter: ComicChapter, account: PlatformAccount?, page: Int) async throws -> [ComicComment] {
        try await loadPicacgComments(item: item, account: account, page: page)
    }

    func picacgComment(from doc: [String: Any]) -> ComicComment {
        let user = doc["_user"] as? [String: Any]
        return ComicComment(
            id: doc["_id"] as? String ?? UUID().uuidString,
            author: user?["name"] as? String ?? "Unknown",
            content: doc["content"] as? String ?? "",
            timeText: doc["created_at"] as? String,
            avatarURLString: picacgImageURL(from: user?["avatar"] as? [String: Any]),
            likesCount: doc.intValue(for: "likesCount"),
            replyCount: doc.intValue(for: "commentsCount"),
            replies: [],
            frameURLString: (user?["character"] as? String)?.nilIfEmpty
        )
    }

    func picacgUploaderInfo(from user: [String: Any]?) -> ComicUploaderInfo? {
        guard let user,
              let id = (user["_id"] as? String)?.nilIfEmpty else {
            return nil
        }

        let name = (user["name"] as? String)?.nilIfEmpty ?? id
        return ComicUploaderInfo(
            id: id,
            name: name,
            title: (user["title"] as? String)?.nilIfEmpty ?? "Unknown",
            level: user.intValue(for: "level") ?? 0,
            exp: user.intValue(for: "exp") ?? 0,
            slogan: (user["slogan"] as? String)?.nilIfEmpty,
            avatarURLString: picacgImageURL(from: user["avatar"] as? [String: Any]),
            frameURLString: (user["character"] as? String)?.nilIfEmpty,
            tag: ComicTagReference(title: name, query: "picacg:ca:\(id)", platform: .picacg, urlString: nil)
        )
    }

    func postPicacgComment(item: ComicListItem, content: String, account: PlatformAccount?) async throws {
        let token = try await picacgToken(account: account)
        let body = try JSONSerialization.data(withJSONObject: ["content": content])
        _ = try await picacgJSON(path: "comics/\(item.id)/comments", method: "POST", token: token, body: body)
    }

    func searchPicacg(keyword: String, page: Int, account: PlatformAccount?, sort: String? = nil) async throws -> [ComicListItem] {
        let token = try await picacgToken(account: account)
        let resolvedSort = sort ?? PlatformFeatureSettings.picacgDefaultSort()
        let body = try JSONSerialization.data(withJSONObject: [
            "keyword": keyword,
            "sort": resolvedSort
        ])
        let json = try await picacgJSON(path: "comics/advanced-search?page=\(page)", method: "POST", token: token, body: body)
        return try picacgItems(from: json, arrayPath: ["data", "comics", "docs"])
    }

    func loadPicacgDetail(item: ComicListItem, account: PlatformAccount?) async throws -> ComicDetailInfo {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "comics/\(item.id)", token: token)
        guard let doc = json.value(at: ["data", "comic"]) as? [String: Any] else {
            throw ComicContentError.invalidResponse("PicACG 详情响应缺少 comic。")
        }

        let detailItem = picacgItems(from: [doc]).first ?? item
        let eps = try await loadPicacgChapters(comicID: item.id, token: token)
        let relatedDocs = json.value(at: ["data", "recommendation"]) as? [[String: Any]] ?? []
        let related = picacgItems(from: relatedDocs)
        let author = (doc["author"] as? String)?.nilIfEmpty
        let chineseTeam = (doc["chineseTeam"] as? String)?.nilIfEmpty
        let categories = doc["categories"] as? [String] ?? []
        let tags = doc["tags"] as? [String] ?? []
        let tagGroups = [
            ComicTagGroup(title: "作者", tags: picacgScopedTagRefs(author.map { [$0] } ?? [], prefix: "picacg:a:")),
            ComicTagGroup(title: "汉化", tags: tagRefs(chineseTeam.map { [$0] } ?? [], platform: .picacg)),
            ComicTagGroup(title: "分类", tags: tagRefs(categories, platform: .picacg, prefix: "category:")),
            ComicTagGroup(title: "标签", tags: tagRefs(tags, platform: .picacg))
        ].filter { !$0.tags.isEmpty }
        let uploader = picacgUploaderInfo(from: doc["_creator"] as? [String: Any])

        return ComicDetailInfo(
            item: detailItem,
            description: doc["description"] as? String ?? "",
            tagGroups: tagGroups,
            chapters: eps.map { chapter in
                ComicChapter(id: chapter.id, title: chapter.title, subtitle: chapter.order)
            },
            related: related,
            updatedText: doc["updated_at"] as? String,
            isLiked: doc["isLiked"] as? Bool,
            uploader: uploader
        )
    }

    func loadPicacgChapters(comicID: String, token: String) async throws -> [PicacgChapterInfo] {
        var page = 1
        var result = [(id: String?, title: String, order: Int?)]()
        while true {
            let json = try await picacgJSON(path: "comics/\(comicID)/eps?page=\(page)", token: token)
            guard let eps = json.value(at: ["data", "eps"]) as? [String: Any],
                  let docs = eps["docs"] as? [[String: Any]] else {
                throw ComicContentError.invalidResponse("PicACG 章节响应缺少 eps。")
            }
            result.append(contentsOf: docs.compactMap { doc in
                guard let title = doc["title"] as? String else { return nil }
                return (id: doc["_id"] as? String, title: title, order: doc.intValue(for: "order"))
            })
            let pages = eps.intValue(for: "pages") ?? page
            if page >= pages { break }
            page += 1
        }
        return result.reversed().enumerated().map { index, chapter in
            let order = chapter.order.map(String.init) ?? "\(index + 1)"
            return PicacgChapterInfo(id: chapter.id ?? order, title: chapter.title, order: order)
        }
    }

    func loadPicacgChapterImages(item: ComicListItem, chapter: ComicChapter, account: PlatformAccount?) async throws -> [String] {
        let token = try await picacgToken(account: account)
        var page = 1
        var result = [String]()
        let order = chapter.subtitle?.nilIfEmpty ?? chapter.id
        while true {
            let json = try await picacgJSON(path: "comics/\(item.id)/order/\(order)/pages?page=\(page)", token: token)
            guard let pages = json.value(at: ["data", "pages"]) as? [String: Any],
                  let docs = pages["docs"] as? [[String: Any]] else {
                throw ComicContentError.invalidResponse("PicACG 图片响应缺少 pages。")
            }
            result.append(contentsOf: docs.compactMap { doc in
                guard let media = doc["media"] as? [String: Any] else { return nil }
                let fileServer = media["fileServer"] as? String ?? ""
                let path = media["path"] as? String ?? ""
                return picacgImageURL(fileServer: fileServer, path: path)
            })
            let pagesCount = pages.intValue(for: "pages") ?? page
            if page >= pagesCount { break }
            page += 1
        }
        return result
    }

    func picacgHeaders(path: String, method: String, token: String) -> [String: String] {
        let apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let time = "\(Int(Date().timeIntervalSince1970))"
        let signatureInput = (path + time + nonce + method.uppercased() + apiKey).lowercased()
        let secret = #"~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"#
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signatureInput.utf8), using: key).map { String(format: "%02x", $0) }.joined()

        return [
            "api-key": apiKey,
            "accept": "application/vnd.picacomic.com.v1+json",
            "app-channel": PlatformFeatureSettings.picacgAppChannel(),
            "authorization": token,
            "time": time,
            "nonce": nonce,
            "app-version": "2.2.1.3.3.4",
            "app-uuid": "defaultUuid",
            "image-quality": AppNetworkSettings.picacgImageQuality,
            "app-platform": "android",
            "app-build-version": "45",
            "Content-Type": "application/json; charset=UTF-8",
            "user-agent": "okhttp/3.8.1",
            "version": "v1.4.1",
            "Host": "picaapi.picacomic.com",
            "signature": signature
        ]
    }

    func picacgImageURL(from data: [String: Any]?) -> String? {
        let fileServer = data?["fileServer"] as? String ?? ""
        let path = data?["path"] as? String ?? ""
        return picacgImageURL(fileServer: fileServer, path: path)
    }

    func picacgImageURL(fileServer: String, path: String) -> String? {
        var server = fileServer.trimmingCharacters(in: .whitespacesAndNewlines)
        var imagePath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !imagePath.isEmpty else { return nil }

        while server.hasSuffix("/") {
            server.removeLast()
        }
        if server.hasSuffix("/static") {
            server.removeLast("/static".count)
        }
        while imagePath.hasPrefix("/") {
            imagePath.removeFirst()
        }

        var allowedPathSegment = CharacterSet.urlPathAllowed
        allowedPathSegment.remove(charactersIn: "#?")
        let encodedPath = imagePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: allowedPathSegment) ?? String(segment)
            }
            .joined(separator: "/")

        return "\(server)/static/\(encodedPath)"
    }
}

private extension ComicContentService {
    func loadNhentaiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let sort: String
        switch entry {
        case .latest:
            sort = "date"
        case .ranking:
            sort = "popular-today"
        case .random:
            throw ComicContentError.unsupported("NHentai 参考项目没有随机漫画列表接口；随机只用于收藏随机详情。")
        case .search:
            throw ComicContentError.unsupported("NHentai 搜索接口需要关键词和筛选条件，当前入口页还没有筛选表单。")
        }
        let query = " ".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "%20"
        guard let url = URL(string: "https://nhentai.net/api/v2/search?query=\(query)&page=\(page)&sort=\(sort)") else {
            throw ComicContentError.invalidURL("nhentai search")
        }
        let json = try await requestJSON(url: url, headers: nhentaiAPIHeaders())
        return try nhentaiItems(from: json)
    }

    func searchNhentai(query: String, page: Int, sort: String = "date") async throws -> [ComicListItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://nhentai.net/api/v2/search?query=\(encoded)&page=\(page)&sort=\(sort)") else {
            throw ComicContentError.invalidURL("nhentai tag \(query)")
        }
        let json = try await requestJSON(url: url, headers: nhentaiAPIHeaders())
        return try nhentaiItems(from: json)
    }

    func loadNhentaiFavorites(account: PlatformAccount, page: Int = 1) async throws -> ComicFavoritePage {
        let headers = try nhentaiAuthHeaders(account: account)
        let page = max(page, 1)
        guard let url = URL(string: "https://nhentai.net/api/v2/favorites?page=\(page)") else {
            throw ComicContentError.invalidURL("nhentai favorites")
        }
        let json: [String: Any]
        do {
            json = try await requestJSON(url: url, headers: headers)
        } catch {
            guard isUnauthorized(error), let refreshedHeaders = try await refreshedNhentaiAuthHeaders(account: account) else {
                throw error
            }
            json = try await requestJSON(url: url, headers: refreshedHeaders)
        }
        let items = try nhentaiItems(from: json, favoriteDate: Date())
        let pageCount = json.intValue(for: "num_pages")
        return ComicFavoritePage(items: items, page: page, hasMore: pageCount.map { page < $0 } ?? !items.isEmpty)
    }

    func addNhentaiFavorite(item: ComicListItem, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("NHentai 收藏需要先登录平台账号。")
        }
        let headers = try nhentaiAuthHeaders(account: account)
        guard let url = URL(string: "https://nhentai.net/api/v2/galleries/\(item.id)/favorite") else {
            throw ComicContentError.invalidURL("nhentai favorite \(item.id)")
        }
        do {
            _ = try await requestData(url: url, method: "POST", headers: headers)
        } catch {
            guard isUnauthorized(error), let refreshedHeaders = try await refreshedNhentaiAuthHeaders(account: account) else {
                throw error
            }
            _ = try await requestData(url: url, method: "POST", headers: refreshedHeaders)
        }
    }

    func nhentaiAuthHeaders(account: PlatformAccount) throws -> [String: String] {
        let token = account.credential.token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            account.credential.cookies.first { $0.name == "access_token" }?.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let token else {
            throw ComicContentError.loginRequired("NHentai 登录状态无效，请重新登录。")
        }
        var headers = nhentaiAPIHeaders(userAgent: account.credential.userAgent)
        headers["Authorization"] = "User \(token)"
        let cookieHeader = nhentaiCookieHeader(account: account, accessToken: token)
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    func refreshedNhentaiAuthHeaders(account: PlatformAccount) async throws -> [String: String]? {
        let refreshToken = account.credential.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            account.credential.cookies.first { $0.name == "refresh_token" }?.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let refreshToken else { return nil }
        guard let url = URL(string: "https://nhentai.net/api/v2/auth/refresh") else {
            throw ComicContentError.invalidURL("nhentai refresh")
        }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        var headers = nhentaiAPIHeaders(userAgent: account.credential.userAgent)
        let cookieHeader = nhentaiCookieHeader(account: account, refreshToken: refreshToken)
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        let json = try await requestJSON(
            url: url,
            method: "POST",
            headers: headers.merging(["Content-Type": "application/json"]) { _, new in new },
            body: body
        )
        guard let token = (json["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        let nextRefreshToken = (json["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? refreshToken
        var updatedAccount = account
        updatedAccount.credential.token = token
        updatedAccount.credential.refreshToken = nextRefreshToken
        updatedAccount.credential.tokenType = "User"
        updatedAccount.credential.cookies.removeAll { $0.name == "access_token" || $0.name == "refresh_token" }
        updatedAccount.credential.cookies.append(
            StoredHTTPCookie(name: "access_token", value: token, domain: ".nhentai.net", isSecure: true)
        )
        updatedAccount.credential.cookies.append(
            StoredHTTPCookie(name: "refresh_token", value: nextRefreshToken, domain: ".nhentai.net", isSecure: true)
        )
        PicaXSQLiteStore.upsertPlatformAccount(updatedAccount)
        NotificationCenter.default.post(name: .picaxPlatformAccountsDidChange, object: nil)
        return try nhentaiAuthHeaders(account: updatedAccount)
    }

    func nhentaiCookieHeader(
        account: PlatformAccount,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) -> String {
        var values = [String: String]()
        for cookie in account.credential.cookies {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard domain == "nhentai.net" || domain.hasSuffix(".nhentai.net"),
                  cookie.expiresDate.map({ $0 > Date() }) ?? true,
                  !cookie.value.isEmpty else { continue }
            values[cookie.name] = cookie.value
        }
        if let accessToken, !accessToken.isEmpty {
            values["access_token"] = accessToken
        }
        if let refreshToken, !refreshToken.isEmpty {
            values["refresh_token"] = refreshToken
        }
        return values.keys.sorted().compactMap { name in
            values[name].map { "\(name)=\($0)" }
        }.joined(separator: "; ")
    }

    func nhentaiItems(from json: [String: Any], favoriteDate: Date? = nil) throws -> [ComicListItem] {
        guard let result = json["result"] as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("NHentai 响应缺少 result。")
        }
        var cachedTagRecords: [StoredNhentaiTagName] = []
        let items = result.map { doc in
            let id = "\(doc.intValue(for: "id") ?? 0)"
            let thumbnail = doc["thumbnail"] as? String ?? ""
            let tagRecords = nhentaiTagNameRecords(from: doc["tags"] as? [[String: Any]] ?? [])
            cachedTagRecords.append(contentsOf: tagRecords)
            return ComicListItem(
                id: id,
                platform: .nhentai,
                title: doc["english_title"] as? String ?? doc["japanese_title"] as? String ?? id,
                subtitle: id,
                coverURLString: absoluteNhentaiThumbnail(thumbnail),
                tags: nhentaiListTags(from: doc, tagRecords: tagRecords),
                pageCount: doc.intValue(for: "num_pages"),
                likesCount: nil,
                favoriteDate: favoriteDate
            )
        }
        PicaXSQLiteStore.upsertNhentaiTagNames(cachedTagRecords)
        return items
    }

    func loadNhentaiDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        guard let url = URL(string: "https://nhentai.net/api/v2/galleries/\(item.id)") else {
            throw ComicContentError.invalidURL("nhentai detail \(item.id)")
        }
        let json = try await requestJSON(url: url, headers: nhentaiAPIHeaders())
        let title = json.value(at: ["title", "english"]) as? String ??
            json.value(at: ["title", "japanese"]) as? String ??
            item.title
        let subtitle = json.value(at: ["title", "japanese"]) as? String ?? json["scanlator"] as? String ?? item.subtitle
        let coverPath = json.value(at: ["cover", "path"]) as? String ?? json.value(at: ["thumbnail", "path"]) as? String ?? item.coverURLString
        let tags = json["tags"] as? [[String: Any]] ?? []
        PicaXSQLiteStore.upsertNhentaiTagNames(nhentaiTagNameRecords(from: tags))
        let grouped = Dictionary(grouping: tags) { tag in
            tag["type"] as? String ?? "tag"
        }
        let tagGroups = grouped.keys.sorted().map { key in
            ComicTagGroup(
                title: nhentaiTagGroupTitle(key),
                tags: tagRefs(grouped[key]?.compactMap { $0["name"] as? String } ?? [], platform: .nhentai)
            )
        }.filter { !$0.tags.isEmpty }
        let detailItem = ComicListItem(
            id: item.id,
            platform: .nhentai,
            title: title,
            subtitle: subtitle,
            coverURLString: absoluteNhentaiThumbnail(coverPath),
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: json.intValue(for: "num_pages"),
            likesCount: json.intValue(for: "num_favorites"),
            favoriteDate: item.favoriteDate
        )
        return ComicDetailInfo(
            item: detailItem,
            description: subtitle == title ? "" : subtitle,
            tagGroups: tagGroups,
            chapters: singleReaderChapter(),
            related: [],
            updatedText: (json.intValue(for: "upload_date")).map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .abbreviated, time: .omitted) }
        )
    }

    func nhentaiListTags(from doc: [String: Any], tagRecords: [StoredNhentaiTagName]) -> [String] {
        let tagIDs = nhentaiTagIDs(from: doc)
        if !tagIDs.isEmpty {
            return tagIDs.prefix(6).map { "tag:\($0)" }
        }
        return tagRecords.prefix(6).map(\.name)
    }

    func nhentaiTagIDs(from doc: [String: Any]) -> [Int] {
        if let ids = doc["tag_ids"] as? [Int] {
            return ids
        }
        if let ids = doc["tag_ids"] as? [NSNumber] {
            return ids.map(\.intValue)
        }
        return []
    }

    func nhentaiTagNameRecords(from tags: [[String: Any]]) -> [StoredNhentaiTagName] {
        tags.compactMap { tag in
            guard let id = tag.intValue(for: "id"), id > 0 else { return nil }
            let name = (tag["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let group = (tag["type"] as? String ?? "tag")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return StoredNhentaiTagName(id: id, group: group.isEmpty ? "tag" : group, name: name)
        }
    }

    func nhentaiTagGroupTitle(_ key: String) -> String {
        switch key {
        case "tag": "标签"
        case "artist": "作者"
        case "group": "社团"
        case "parody": "原作"
        case "character": "角色"
        case "language": "语言"
        case "category": "分类"
        default: key
        }
    }

    func absoluteNhentaiThumbnail(_ path: String) -> String {
        if path.hasPrefix("http") { return path }
        if path.hasPrefix("/") { return "https://t.nhentai.net\(path)" }
        return "https://t.nhentai.net/\(path)"
    }

    func absoluteNhentaiImage(_ path: String) -> String {
        if path.hasPrefix("http") { return path }
        if path.hasPrefix("/") { return "https://i.nhentai.net\(path)" }
        return "https://i.nhentai.net/\(path)"
    }

    func loadNhentaiImages(item: ComicListItem) async throws -> [String] {
        guard let url = URL(string: "https://nhentai.net/api/v2/galleries/\(item.id)") else {
            throw ComicContentError.invalidURL("nhentai images \(item.id)")
        }
        let json = try await requestJSON(url: url, headers: nhentaiAPIHeaders())
        let pages = json["pages"] as? [[String: Any]] ?? []
        return pages.compactMap { page in
            guard let path = page["path"] as? String, !path.isEmpty else { return nil }
            return absoluteNhentaiImage(path)
        }
    }

    func loadNhentaiComments(item: ComicListItem) async throws -> [ComicComment] {
        guard let url = URL(string: "https://nhentai.net/api/v2/galleries/\(item.id)/comments") else {
            throw ComicContentError.invalidURL("nhentai comments \(item.id)")
        }
        let json = try await requestJSON(url: url, headers: nhentaiAPIHeaders())
        guard let docs = json["result"] as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("NHentai 评论加载失败。")
        }
        return docs.map { doc in
            let poster = doc["poster"] as? [String: Any]
            let avatarPath = poster?["avatar_url"] as? String ?? ""
            let avatarURL = avatarPath.isEmpty ? nil : "https://i3.nhentai.net/\(avatarPath)"
            return ComicComment(
                id: "\(doc.intValue(for: "id") ?? Int.random(in: 0...Int.max))",
                author: poster?["username"] as? String ?? "Unknown",
                content: doc["body"] as? String ?? "",
                timeText: doc["post_date"].map { "\($0)" },
                avatarURLString: avatarURL,
                likesCount: nil,
                replyCount: nil,
                replies: []
            )
        }
    }

    func nhentaiAPIHeaders(userAgent: String? = nil) -> [String: String] {
        [
            "Accept": "application/json",
            "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
            "Referer": "https://nhentai.net/",
            "User-Agent": userAgent?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) GSA/300.0.598994205 Mobile/15E148 Safari/604"
        ]
    }
}

private extension ComicContentService {
    var ehentaiBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .eHentai)
    }

    func loadEhentaiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let urlString: String
        let pageIndex = max(0, page - 1)
        switch entry {
        case .latest:
            urlString = pageIndex == 0 ? "\(ehentaiBaseURL)/" : "\(ehentaiBaseURL)/?page=\(pageIndex)"
        case .ranking:
            urlString = pageIndex == 0 ? "\(ehentaiBaseURL)/popular" : "\(ehentaiBaseURL)/popular?page=\(pageIndex)"
        case .random, .search:
            throw ComicContentError.unsupported("E-Hentai 当前入口不可用。")
        }
        guard let url = URL(string: urlString) else { throw ComicContentError.invalidURL(urlString) }
        let html = try await requestString(url: url, headers: webHeaders(referer: ehentaiBaseURL))
        return parseEhentaiGalleries(html)
    }

    func searchEhentai(query: String, page: Int) async throws -> [ComicListItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let pageIndex = max(0, page - 1)
        let pageQuery = pageIndex == 0 ? "" : "&page=\(pageIndex)"
        guard let url = URL(string: "\(ehentaiBaseURL)/?f_search=\(encoded)\(pageQuery)") else {
            throw ComicContentError.invalidURL("ehentai search \(query)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: ehentaiBaseURL))
        return parseEhentaiGalleries(html)
    }

    func loadEhentaiWatched(page: Int) async throws -> [ComicListItem] {
        let pageIndex = max(0, page - 1)
        let urlString = pageIndex == 0 ? "\(ehentaiBaseURL)/watched" : "\(ehentaiBaseURL)/watched?page=\(pageIndex)"
        guard let url = URL(string: urlString) else {
            throw ComicContentError.invalidURL(urlString)
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: ehentaiBaseURL))
        return parseEhentaiGalleries(html)
    }

    func loadEhentaiFavorites(account: PlatformAccount, folderID: String? = nil, page: Int = 1) async throws -> ComicFavoritePage {
        let headers = try ehentaiAccountHeaders(account: account, referer: ehentaiBaseURL)
        let page = max(page, 1)
        let pageIndex = max(page - 1, 0)
        var queryItems = [String]()
        if let folderID, folderID != "-1" {
            queryItems.append("favcat=\(folderID.urlEncoded)")
        }
        if pageIndex > 0 {
            queryItems.append("page=\(pageIndex)")
        }
        let path = queryItems.isEmpty ? "favorites.php" : "favorites.php?\(queryItems.joined(separator: "&"))"
        guard let url = URL(string: "\(ehentaiBaseURL)/\(path)") else {
            throw ComicContentError.invalidURL("ehentai favorites")
        }
        let html = try await requestString(url: url, headers: headers)
        guard !html.contains("You are not currently logged in") else {
            throw ComicContentError.loginRequired("E-Hentai 登录状态无效，请重新登录。")
        }
        let items = parseEhentaiGalleries(html, favoriteDate: Date())
        return ComicFavoritePage(items: items, page: page, hasMore: ehentaiHasNextPage(html))
    }

    func loadEhentaiFavoriteFolders(account: PlatformAccount?) async throws -> [PlatformFavoriteFolder] {
        guard let account else {
            throw ComicContentError.loginRequired("E-Hentai 收藏需要先登录平台账号。")
        }
        let headers = try ehentaiAccountHeaders(account: account, referer: ehentaiBaseURL)
        guard let url = URL(string: "\(ehentaiBaseURL)/favorites.php") else {
            throw ComicContentError.invalidURL("ehentai favorite folders")
        }
        let html = try await requestString(url: url, headers: headers)
        let names = parseEhentaiFavoriteFolderNames(html)
        return ([PlatformFavoriteFolder(id: "-1", title: "全部", subtitle: "E-Hentai 收藏夹", platform: .eHentai)] +
                names.enumerated().map { index, title in
                    PlatformFavoriteFolder(id: "\(index)", title: title, subtitle: "E-Hentai 收藏夹", platform: .eHentai)
                })
    }

    func addEhentaiFavorite(item: ComicListItem, folderID: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("E-Hentai 收藏需要先登录平台账号。")
        }
        guard let parts = ehentaiGalleryIDAndToken(from: item.id) else {
            throw ComicContentError.invalidURL(item.id)
        }
        let headers = try ehentaiAccountHeaders(account: account, referer: item.id)
        let folder = folderID == "-1" ? "0" : folderID
        guard let url = URL(string: "\(ehentaiBaseURL)/gallerypopups.php?gid=\(parts.gid)&t=\(parts.token)&act=addfav") else {
            throw ComicContentError.invalidURL("ehentai favorite \(item.id)")
        }
        let body = "favcat=\(folder.urlEncoded)&favnote=&apply=Add+to+Favorites&update=1"
        _ = try await requestData(
            url: url,
            method: "POST",
            headers: headers.merging(["Content-Type": "application/x-www-form-urlencoded"]) { _, new in new },
            body: Data(body.utf8)
        )
    }

    func parseEhentaiGalleries(_ html: String, favoriteDate: Date? = nil) -> [ComicListItem] {
        let rowBlocks = html.regexMatches(#"<tr\b[^>]*>.*?</tr>"#, options: [.dotMatchesLineSeparators])
        let thumbnailBlocks = html.regexMatches(#"<div\b[^>]*class="[^"]*\bgl1t\b[^"]*"[^>]*>.*?(?=<div\b[^>]*class="[^"]*\bgl1t\b|\z)"#, options: [.dotMatchesLineSeparators])
        var seen = Set<String>()
        return (rowBlocks + thumbnailBlocks).compactMap { block in
            guard let item = ehentaiGalleryItem(from: block, favoriteDate: favoriteDate),
                  seen.insert(item.id).inserted else {
                return nil
            }
            return item
        }
    }

    func ehentaiGalleryItem(from block: String, favoriteDate: Date?) -> ComicListItem? {
        guard let link = block.firstRegexCapture(#"href="(https?://[^"]+/g/[0-9]+/[^"/?#]+/?)"#)?.htmlDecoded else {
            return nil
        }
        let title = block.firstRegexCapture(#"class="[^"]*\bglink\b[^"]*"[^>]*>(.*?)</"#)?.htmlDecoded ??
            block.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded ??
            link
        let cover = block.firstRegexCapture(#"data-src="([^"]+)""#) ??
            block.firstRegexCapture(#"src="([^"]+)""#) ??
            ""
        let uploader = block.firstRegexCapture(#"class="[^"]*\bglname\b[^"]*"[^>]*>.*?</[^>]+>"#)?.strippingHTML ?? ""
        let tags = ehentaiGalleryTags(from: block)
        return ComicListItem(
            id: link,
            platform: .eHentai,
            title: title,
            subtitle: uploader,
            coverURLString: cover,
            tags: tags.map(\.title),
            pageCount: nil,
            likesCount: nil,
            favoriteDate: favoriteDate
        )
    }

    func ehentaiGalleryTags(from block: String) -> [ComicTagReference] {
        let tagPattern = #"<div\b[^>]*class="[^"]*\bgt[lr]?\b[^"]*"[^>]*title="([^"]+)"[^>]*>.*?</div>"#
        var primaryTags = [ComicTagReference]()
        var secondaryTags = [ComicTagReference]()
        for tagHTML in block.regexMatches(tagPattern, options: [.dotMatchesLineSeparators]) {
            guard let rawTitle = tagHTML.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded else {
                continue
            }
            let parts = rawTitle.split(separator: ":", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { continue }
            let namespace = parts[0]
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard namespace != "language", !value.isEmpty else { continue }
            let query = "\(namespace):\(value)"
            let tag = ComicTagReference(
                title: EhTagTranslationService.translatedTagTitle(title: value, query: query, namespace: namespace),
                query: query,
                platform: .eHentai,
                urlString: nil
            )
            if ["character", "artist", "cosplayer", "group"].contains(namespace) {
                secondaryTags.append(tag)
            } else {
                primaryTags.append(tag)
            }
        }
        return primaryTags + secondaryTags
    }

    func ehentaiHasNextPage(_ html: String) -> Bool {
        guard let button = html.regexMatches(#"<a\b[^>]*id="dnext"[^>]*>"#).first else {
            return false
        }
        return button.contains("href=") && !button.contains(#"href="""#)
    }

    func parseEhentaiFavoriteFolderNames(_ html: String) -> [String] {
        let names = html.regexMatches(#"<div class="fp".*?</div>"#, options: [.dotMatchesLineSeparators]).compactMap { row -> String? in
            let values = row.regexMatches(#"<[^>]+>(.*?)</[^>]+>"#, options: [.dotMatchesLineSeparators])
                .map(\.strippingHTML)
                .filter { !$0.isEmpty }
            guard values.count >= 3 else { return nil }
            let count = values[0]
            let name = values[2]
            return count.isEmpty ? name : "\(name) (\(count))"
        }
        if names.count >= 10 {
            return Array(names.prefix(10))
        }
        return names + (names.count..<10).map { "Favorite \($0)" }
    }

    func ehentaiAccountHeaders(account: PlatformAccount, referer: String) throws -> [String: String] {
        let names = Set(account.credential.cookies.map(\.name))
        guard names.contains("ipb_member_id"), names.contains("ipb_pass_hash") else {
            throw ComicContentError.loginRequired("E-Hentai 登录状态无效，请重新登录。")
        }
        let cookieHeader = ehentaiCookieHeader(cookies: account.credential.cookies)
        guard !cookieHeader.isEmpty else {
            throw ComicContentError.loginRequired("E-Hentai 登录状态无效，请重新登录。")
        }
        return webHeaders(referer: referer, userAgent: account.credential.userAgent)
            .merging(["Cookie": cookieHeader]) { _, new in new }
    }

    func ehentaiCookieHeader(cookies: [StoredHTTPCookie]) -> String {
        var values = [String: StoredHTTPCookie]()
        for cookie in cookies where !cookie.name.isEmpty && !cookie.value.isEmpty {
            if let current = values[cookie.name] {
                let currentDomain = current.domain
                if !cookie.domain.hasPrefix(".") && currentDomain.hasPrefix(".") {
                    values[cookie.name] = cookie
                } else if cookie.domain.count > currentDomain.count {
                    values[cookie.name] = cookie
                }
            } else {
                values[cookie.name] = cookie
            }
        }
        values["nw"] = StoredHTTPCookie(name: "nw", value: UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.ehentaiIgnoresContentWarning) ? "1" : "0", domain: ".e-hentai.org")
        let profile = (UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.ehentaiProfile) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty {
            values["sp"] = StoredHTTPCookie(name: "sp", value: profile, domain: ".e-hentai.org")
        }
        return values.values
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    func ehentaiGalleryIDAndToken(from value: String) -> (gid: String, token: String)? {
        guard let match = value.firstRegexCapturePair(#"/g/([0-9]+)/([^/?#]+)"#) else {
            return nil
        }
        return (match.0, match.1)
    }

    func loadEhentaiDetail(item: ComicListItem, account: PlatformAccount?) async throws -> ComicDetailInfo {
        guard let url = URL(string: item.id) else {
            throw ComicContentError.invalidURL(item.id)
        }
        let html = try await requestString(url: url, headers: ehentaiRequestHeaders(account: account, referer: ehentaiBaseURL))
        if html.contains("Content Warning"), html.contains("Never Warn Me Again") {
            throw ComicContentError.server("E-Hentai 返回 Content Warning，需要网页登录确认。")
        }

        let title = html.firstRegexCapture(#"<h1 id="gn"[^>]*>(.*?)</h1>"#)?.htmlDecoded ?? item.title
        let subtitle = html.firstRegexCapture(#"<h1 id="gj"[^>]*>(.*?)</h1>"#)?.htmlDecoded
        let prefersJapaneseTitle = UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.ehentaiPrefersJapaneseTitle)
        let displayTitle = prefersJapaneseTitle ? (subtitle?.nilIfEmpty ?? title) : title
        let displayDescription = prefersJapaneseTitle ? title : (subtitle ?? "")
        let cover = html.firstRegexCapture(#"<div id="gd1"[^>]*>.*?url\((https?://[^)]+)\)"#) ?? item.coverURLString
        let uploader = html.firstRegexCapture(#"<div id="gdn"[^>]*>.*?<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? item.subtitle
        let pages = html.firstRegexCapture(#"<td class="gdt2">([0-9,]+)\s+pages</td>"#)
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .flatMap(Int.init)
        let time = html.firstRegexCapture(#"<td class="gdt2">([0-9]{4}-[0-9]{2}-[0-9]{2}[^<]*)</td>"#)?.htmlDecoded
        let tagGroups = parseEhentaiTagGroups(html, platform: .eHentai)
        let detailItem = ComicListItem(
            id: item.id,
            platform: .eHentai,
            title: displayTitle,
            subtitle: uploader,
            coverURLString: cover,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: pages ?? item.pageCount,
            likesCount: item.likesCount,
            favoriteDate: item.favoriteDate
        )
        return ComicDetailInfo(
            item: detailItem,
            description: displayDescription,
            tagGroups: tagGroups,
            chapters: singleReaderChapter(),
            related: [],
            updatedText: time
        )
    }

    func parseEhentaiTagGroups(_ html: String, platform: ComicPlatform) -> [ComicTagGroup] {
        html.regexMatches(#"<tr\b[^>]*>.*?</tr>"#, options: [.dotMatchesLineSeparators]).compactMap { row in
            guard row.contains(#"class="tc""#) || row.contains(#"id="td_"#) || row.contains(#"id="ta_""#) else { return nil }
            let namespace = (row.firstRegexCapture(#"<td\b[^>]*class="[^"]*\btc\b[^"]*"[^>]*>([^<:]+):?</td>"#)?.htmlDecoded ?? "标签")
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\t"))
                .lowercased()
            let translatedTitle = EhTagTranslationService.translatedGroupTitle(namespace)
            let tags = ehentaiDetailTags(from: row, namespace: namespace, platform: platform)
            return tags.isEmpty ? nil : ComicTagGroup(title: translatedTitle, tags: tags)
        }
    }

    func ehentaiDetailTags(from row: String, namespace: String, platform: ComicPlatform) -> [ComicTagReference] {
        let tagBlocks = row.regexMatches(#"<div\b[^>]*class="[^"]*\bgt[lr]?\b[^"]*"[^>]*>.*?</div>"#, options: [.dotMatchesLineSeparators])
        let sourceBlocks = tagBlocks.isEmpty
            ? row.regexMatches(#"<a\b[^>]*id="ta_[^"]*"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators])
            : tagBlocks
        return sourceBlocks.compactMap { ehentaiDetailTag(from: $0, namespace: namespace, platform: platform) }
    }

    func ehentaiDetailTag(from tagHTML: String, namespace: String, platform: ComicPlatform) -> ComicTagReference? {
        let displayTitle = tagHTML.strippingHTML
        let titleValue = tagHTML.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded
        let searchValue = tagHTML.firstRegexCapture(#"[?&]f_search=([^"&]+)"#)
            .map {
                let value = $0.replacingOccurrences(of: "+", with: " ")
                return value.removingPercentEncoding ?? value
            }
        let rawQuery = (titleValue ?? searchValue ?? displayTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty else { return nil }

        let query = rawQuery.contains(":") ? rawQuery : "\(namespace):\(rawQuery)"
        let fallbackTitle = query.split(separator: ":", maxSplits: 1).last.map(String.init) ?? rawQuery
        let title = displayTitle.nilIfEmpty ?? fallbackTitle
        return ComicTagReference(
            title: EhTagTranslationService.translatedTagTitle(title: title, query: query, namespace: namespace),
            query: query,
            platform: platform,
            urlString: nil
        )
    }

    func loadEhentaiComments(item: ComicListItem, account: PlatformAccount?) async throws -> [ComicComment] {
        guard let account else {
            throw ComicContentError.loginRequired("E-Hentai 评论需要先登录平台账号。")
        }
        guard let baseURL = URL(string: item.id) else {
            throw ComicContentError.invalidURL(item.id)
        }
        let separator = baseURL.query == nil ? "?" : "&"
        guard let url = URL(string: "\(item.id)\(separator)hc=1") else {
            throw ComicContentError.invalidURL("\(item.id)?hc=1")
        }
        let headers = try ehentaiAccountHeaders(account: account, referer: item.id)
        let html = try await requestString(url: url, headers: headers)
        guard !html.contains("You are not currently logged in") else {
            throw ComicContentError.loginRequired("E-Hentai 登录状态无效，请重新登录。")
        }
        return parseEhentaiComments(html)
    }

    func postEhentaiComment(item: ComicListItem, content: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("E-Hentai 评论需要先登录平台账号。")
        }
        guard let url = URL(string: item.id) else {
            throw ComicContentError.invalidURL(item.id)
        }
        let body = "commenttext_new=\(content.urlEncoded)"
        let headers = try ehentaiAccountHeaders(account: account, referer: item.id)
        let data = try await requestData(
            url: url,
            method: "POST",
            headers: headers.merging(["Content-Type": "application/x-www-form-urlencoded"]) { _, new in new },
            body: Data(body.utf8)
        )
        let html = String(data: data, encoding: .utf8) ?? ""
        if let message = html.firstRegexCapture(#"<p class="br"[^>]*>(.*?)</p>"#)?.strippingHTML, !message.isEmpty {
            throw ComicContentError.server(message)
        }
    }

    func parseEhentaiComments(_ html: String) -> [ComicComment] {
        html.regexMatches(#"<div\b[^>]*class="[^"]*\bc1\b[^"]*"[^>]*>.*?(?=<a\b[^>]*name="(?:comment_)?[0-9]+"|<div\b[^>]*class="[^"]*\bc1\b|\z)"#, options: [.dotMatchesLineSeparators])
            .enumerated()
            .compactMap { index, row -> ComicComment? in
                guard let contentHTML = row.firstRegexCapture(#"<div\b[^>]*class="[^"]*\bc6\b[^"]*"[^>]*>(.*?)</div>"#),
                      !contentHTML.strippingHTML.isEmpty else {
                    return nil
                }
                let id = row.firstRegexCapture(#"name="(?:comment_)?([0-9]+)""#) ??
                    row.firstRegexCapture(#"comment_vote_(?:up|down)_([0-9]+)""#) ??
                    "\(index)"
                let header = row.firstRegexCapture(#"<div\b[^>]*class="[^"]*\bc3\b[^"]*"[^>]*>(.*?)</div>"#)?.htmlDecoded ?? ""
                let author = row.firstRegexCapture(#"<div\b[^>]*class="[^"]*\bc3\b[^"]*"[^>]*>.*?<a[^>]*>(.*?)</a>"#)?.htmlDecoded ??
                    header.firstRegexCapture(#"by\s+(.+)$"#)?.trimmingCharacters(in: .whitespacesAndNewlines) ??
                    "未知"
                let time = header.firstRegexCapture(#"Posted on\s*(.*?)\s*by"#)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = contentHTML.htmlDecoded.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                let score = row.firstRegexCapture(#"<div\b[^>]*class="[^"]*\bc5\b[^"]*"[^>]*>.*?<span[^>]*>(-?[0-9]+)</span>"#).flatMap(Int.init)
                return ComicComment(
                    id: id,
                    author: author,
                    content: content,
                    timeText: time,
                    avatarURLString: nil,
                    likesCount: score,
                    replyCount: nil,
                    replies: []
                )
            }
    }
}

private extension ComicContentService {
    var htMangaBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .htManga)
    }

    func loadHtMangaExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let base = htMangaBaseURL
        let path: String
        switch entry {
        case .ranking:
            path = "/albums-favorite_ranking-type-day.html"
        case .latest:
            path = "/albums.html"
        case .random, .search:
            throw ComicContentError.unsupported("HT Manga 当前入口不可用。")
        }
        let urlString = htMangaPagedURL(base + path, page: page)
        guard let url = URL(string: urlString) else { throw ComicContentError.invalidURL(urlString) }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        return parseHtMangaList(html, baseURL: base)
    }

    func loadHtMangaFavorites(account: PlatformAccount, folderID: String? = nil, page: Int = 1) async throws -> ComicFavoritePage {
        let base = htMangaBaseURL
        let cookies = try htMangaCookieStorage(account: account)
        let folderID = folderID?.nilIfEmpty ?? "0"
        let page = max(page, 1)
        guard let url = URL(string: "\(base)/users-users_fav-page-\(page)-c-\(folderID.urlEncoded).html") else {
            throw ComicContentError.invalidURL("htmanga favorites")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base, userAgent: account.credential.userAgent), cookies: cookies)
        let items = parseHtMangaList(html, baseURL: base, favoriteDate: Date())
        return ComicFavoritePage(items: items, page: page, hasMore: !items.isEmpty)
    }

    func loadHtMangaFavoriteFolders(account: PlatformAccount?) async throws -> [PlatformFavoriteFolder] {
        guard let account else {
            throw ComicContentError.loginRequired("HT Manga 收藏需要先登录平台账号。")
        }
        let base = htMangaBaseURL
        let cookies = try htMangaCookieStorage(account: account)
        guard let url = URL(string: "\(base)/users-addfav-id-210814.html") else {
            throw ComicContentError.invalidURL("htmanga folders")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base, userAgent: account.credential.userAgent), cookies: cookies)
        let folders = html.regexMatches(#"<option[^>]+value="([^"]+)"[^>]*>.*?</option>"#, options: [.dotMatchesLineSeparators]).compactMap { row -> PlatformFavoriteFolder? in
            guard let id = row.firstRegexCapture(#"value="([^"]+)""#), !id.isEmpty else { return nil }
            let title = row.strippingHTML
            return PlatformFavoriteFolder(id: id, title: title.isEmpty ? "云端收藏夹" : title, subtitle: "HT Manga 收藏夹", platform: .htManga)
        }
        return folders.isEmpty ? [PlatformFavoriteFolder(id: "0", title: "云端收藏夹", subtitle: "HT Manga 默认收藏", platform: .htManga)] : folders
    }

    func addHtMangaFavorite(item: ComicListItem, folderID: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("HT Manga 收藏需要先登录平台账号。")
        }
        let base = htMangaBaseURL
        let cookies = try htMangaCookieStorage(account: account)
        guard let url = URL(string: "\(base)/users-save_fav-id-\(item.id).html") else {
            throw ComicContentError.invalidURL("htmanga favorite \(item.id)")
        }
        let body = "favc_id=\(folderID.urlEncoded)"
        _ = try await requestData(
            url: url,
            method: "POST",
            headers: webHeaders(referer: base, userAgent: account.credential.userAgent)
                .merging(["Content-Type": "application/x-www-form-urlencoded"]) { _, new in new },
            body: Data(body.utf8),
            cookies: cookies
        )
    }

    func htMangaLogin(account: PlatformAccount, baseURL: String, cookies: HTTPCookieStorage) async throws {
        let storedCookies = try htMangaCookieStorage(account: account)
        for cookie in storedCookies.cookies ?? [] {
            cookies.setCookie(cookie)
        }
    }

    func htMangaLogin(username: String, password: String, baseURL: String, cookies: HTTPCookieStorage) async throws {
        guard let url = URL(string: "\(baseURL)/users-check_login.html") else {
            throw ComicContentError.invalidURL("htmanga login")
        }
        let bodyString = "login_name=\(username.urlEncoded)&login_pass=\(password.urlEncoded)"
        let data = try await requestData(
            url: url,
            method: "POST",
            headers: webHeaders(referer: baseURL).merging(["Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"]) { _, new in new },
            body: Data(bodyString.utf8),
            cookies: cookies
        )
        guard let text = String(data: data, encoding: .utf8), text.contains("登錄成功") || text.contains("登录成功") else {
            throw ComicContentError.loginRequired("HT Manga 登录失败。")
        }
    }

    func htMangaCookieStorage(account: PlatformAccount) throws -> HTTPCookieStorage {
        guard !account.credential.cookies.isEmpty else {
            throw ComicContentError.loginRequired("HT Manga 登录状态无效，请重新登录。")
        }
        return account.credential.cookieStorage()
    }

    func parseHtMangaList(_ html: String, baseURL: String, favoriteDate: Date? = nil) -> [ComicListItem] {
        let rows = html.regexMatches(#"<li>.*?</li>"#, options: [.dotMatchesLineSeparators]) +
            html.regexMatches(#"<div class="asTB".*?</div>\s*</div>"#, options: [.dotMatchesLineSeparators])
        return rows.compactMap { row in
            guard let link = row.firstRegexCapture(#"href="([^"]*aid-[0-9]+[^"]*)""#),
                  let id = link.firstRegexCapture(#"aid-([0-9]+)"#) else {
                return nil
            }
            let title = row.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded ??
                row.firstRegexCapture(#"<p class="l_title">\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ??
                row.firstRegexCapture(#"<div class="title">\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ??
                id
            let image = row.firstRegexCapture(#"<img[^>]+src="([^"]+)""#) ?? ""
            let pages = row.firstRegexCapture(#"(?:頁數|页数|页)：?([0-9]+)"#).flatMap(Int.init)
            return ComicListItem(
                id: id,
                platform: .htManga,
                title: title,
                subtitle: id,
                coverURLString: absoluteURL(image, baseURL: baseURL),
                tags: [],
                pageCount: pages,
                likesCount: nil,
                favoriteDate: favoriteDate
            )
        }
    }

    func loadEhentaiImages(item: ComicListItem, account: PlatformAccount?) async throws -> [String] {
        var pageCount = item.pageCount ?? 0
        if pageCount <= 0 {
            guard let url = URL(string: item.id) else {
                throw ComicContentError.invalidURL(item.id)
            }
            let html = try await requestString(url: url, headers: ehentaiRequestHeaders(account: account, referer: ehentaiBaseURL))
            if html.contains("Content Warning"), html.contains("Never Warn Me Again") {
                throw ComicContentError.server("E-Hentai 返回 Content Warning，需要网页登录确认。")
            }
            pageCount = ehentaiPageCount(from: html) ?? ehentaiReaderLinks(from: html).count
        }
        guard pageCount > 0 else {
            throw ComicContentError.invalidResponse("E-Hentai 章节没有返回图片。")
        }
        return try await EhentaiLazyImageResolver.shared.registerGallery(
            galleryURLString: item.id,
            pageCount: pageCount,
            baseURLString: ehentaiBaseURL,
            apiURLString: ehentaiAPIURL,
            headers: ehentaiRequestHeaders(account: account, referer: item.id),
            prefersOriginalImage: UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.ehentaiPrefersOriginalImage)
        )
    }

    func ehentaiRequestHeaders(account: PlatformAccount?, referer: String) -> [String: String] {
        var headers = webHeaders(referer: referer, userAgent: account?.credential.userAgent)
        if let account {
            let cookieHeader = ehentaiCookieHeader(cookies: account.credential.cookies)
            if !cookieHeader.isEmpty {
                headers["Cookie"] = cookieHeader
            }
        }
        return headers
    }

    func ehentaiPageCount(from html: String) -> Int? {
        html.firstRegexCapture(#"<td class="gdt2">([0-9,]+)\s+pages</td>"#)
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .flatMap(Int.init)
    }

    func ehentaiReaderLinks(from html: String) -> [String] {
        var links = html.regexMatches(
            #"<a\b[^>]*href="((?:https?://[^"]+)?/s/[^"]+)"[^>]*>\s*<div\b[^>]*class="[^"]*(?:gdtm|gdtl|gt100|gt200)[^"]*""#,
            options: [.dotMatchesLineSeparators]
        )
        .compactMap { $0.firstRegexCapture(#"href="([^"]+)""#)?.htmlDecoded }

        if links.isEmpty {
            links = html.regexMatches(#"href="((?:https?://[^"]+)?/s/[^"]+)""#)
                .compactMap { $0.firstRegexCapture(#"href="([^"]+)""#)?.htmlDecoded }
        }

        var seen = Set<String>()
        return links.compactMap { link in
            let absoluteLink = absoluteURL(link, baseURL: ehentaiBaseURL)
            return seen.insert(absoluteLink).inserted ? absoluteLink : nil
        }
    }

    var ehentaiAPIURL: String {
        if URL(string: ehentaiBaseURL)?.host?.lowercased().contains("exhentai") == true {
            return "https://exhentai.org/api.php"
        }
        return "https://api.e-hentai.org/api.php"
    }

    func loadHtMangaDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        let base = htMangaBaseURL
        guard let url = URL(string: "\(base)/photos-index-page-1-aid-\(item.id).html") else {
            throw ComicContentError.invalidURL("htmanga detail \(item.id)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        let title = html.firstRegexCapture(#"<div class="userwrap"[^>]*>.*?<h2[^>]*>(.*?)</h2>"#)?.htmlDecoded ?? item.title
        let cover = html.firstRegexCapture(#"<div class="asTBcell uwthumb"[^>]*>.*?<img[^>]+src="([^"]+)""#).map { absoluteURL($0, baseURL: base) } ?? item.coverURLString
        let labels = html.regexMatches(#"<label[^>]*>.*?</label>"#, options: [.dotMatchesLineSeparators]).map(\.htmlDecoded)
        let category = labels.first { $0.contains("分類") || $0.contains("分类") }?.components(separatedBy: "：").last ?? ""
        let pages = labels.first { $0.contains("頁數") || $0.contains("页数") }?.firstRegexCapture(#"([0-9]+)"#).flatMap(Int.init)
        let description = html.firstRegexCapture(#"<div class="asTBcell uwconn"[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? ""
        let uploader = html.firstRegexCapture(#"<div class="asTBcell uwuinfo"[^>]*>.*?<a[^>]*>\s*<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? item.subtitle
        let tags = html.regexMatches(#"<a class="tagshow"[^>]*href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators]).compactMap { row -> ComicTagReference? in
            guard let link = row.firstRegexCapture(#"href="([^"]+)""#) else { return nil }
            let title = row.strippingHTML
            return ComicTagReference(title: title, query: title, platform: .htManga, urlString: absoluteURL(link, baseURL: base))
        }
        let tagGroups = [
            ComicTagGroup(title: "分类", tags: category.isEmpty ? [] : tagRefs([category], platform: .htManga)),
            ComicTagGroup(title: "标签", tags: tags)
        ].filter { !$0.tags.isEmpty }
        let detailItem = ComicListItem(
            id: item.id,
            platform: .htManga,
            title: title,
            subtitle: uploader,
            coverURLString: cover,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: pages ?? item.pageCount,
            likesCount: nil,
            favoriteDate: item.favoriteDate
        )
        return ComicDetailInfo(
            item: detailItem,
            description: description,
            tagGroups: tagGroups,
            chapters: singleReaderChapter(),
            related: [],
            updatedText: nil
        )
    }

    func loadHtMangaImages(item: ComicListItem) async throws -> [String] {
        let base = htMangaBaseURL
        guard let url = URL(string: "\(base)/photos-gallery-aid-\(item.id).html") else {
            throw ComicContentError.invalidURL("htmanga images \(item.id)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        return html.regexMatches(#"(?<=//)[\w./\[\]()-]+"#).map { "https://\($0)" }
    }

    func searchHtManga(tag: ComicTagReference, page: Int) async throws -> [ComicListItem] {
        let base = htMangaBaseURL
        let urlString: String
        if let tagURL = tag.urlString, !tagURL.isEmpty {
            urlString = htMangaPagedURL(tagURL, page: page)
        } else {
            let encoded = tag.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag.query
            urlString = htMangaPagedURL("\(base)/search/?q=\(encoded)&f=_all&s=create_time_DESC&syn=yes", page: page)
        }
        guard let url = URL(string: urlString) else {
            throw ComicContentError.invalidURL("htmanga tag \(tag.query)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        return parseHtMangaList(html, baseURL: base)
    }

    func htMangaPagedURL(_ rawURL: String, page: Int) -> String {
        guard page > 1 else { return rawURL }
        if rawURL.contains("/search/") {
            return rawURL.contains("?") ? "\(rawURL)&p=\(page)" : "\(rawURL)?p=\(page)"
        }
        if rawURL.contains("ranking") {
            return rawURL.replacingOccurrences(of: "ranking", with: "ranking-page-\(page)")
        }
        if rawURL.contains("index-page-") {
            return rawURL.replacingOccurrences(of: #"index-page-\d+"#, with: "index-page-\(page)", options: .regularExpression)
        }
        if rawURL.hasSuffix("/albums.html") {
            return rawURL.replacingOccurrences(of: "/albums.html", with: "/albums-index-page-\(page).html")
        }
        return rawURL.replacingOccurrences(of: "index", with: "index-page-\(page)")
    }
}

actor EhentaiLazyImageResolver {
    static let shared = EhentaiLazyImageResolver()
    nonisolated static let scheme = "picax-ehentai-image"

    private let session = AppNetworkSettings.makeSession()
    private var contexts: [String: Context] = [:]
    private var readerLinksByURL: [String: [String]] = [:]
    private var loadingReaderLinkURLs = Set<String>()
    private var authByContextKey: [String: GalleryAuth] = [:]
    private var loadingAuthKeys = Set<String>()

    nonisolated static func isLazyImageURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    func registerGallery(
        galleryURLString: String,
        pageCount: Int,
        baseURLString: String,
        apiURLString: String,
        headers: [String: String],
        prefersOriginalImage: Bool
    ) throws -> [String] {
        guard let gid = Self.galleryID(from: galleryURLString) else {
            throw ComicContentError.invalidURL(galleryURLString)
        }
        let key = Self.contextKey(
            galleryURLString: galleryURLString,
            baseURLString: baseURLString,
            apiURLString: apiURLString,
            headers: headers,
            prefersOriginalImage: prefersOriginalImage
        )
        contexts[key] = Context(
            key: key,
            galleryURLString: galleryURLString,
            gid: gid,
            pageCount: pageCount,
            baseURLString: baseURLString,
            apiURLString: apiURLString,
            headers: headers,
            prefersOriginalImage: prefersOriginalImage
        )
        return (1...pageCount).map { Self.lazyImageURLString(key: key, page: $0) }
    }

    func data(for url: URL) async throws -> Data {
        guard let request = Self.lazyImageRequest(from: url),
              let context = contexts[request.key] else {
            throw ComicContentError.invalidResponse("E-Hentai 图片上下文已失效，请重新进入章节。")
        }
        let resolvedImage = try await resolveImage(page: request.page, context: context)
        return try await imageData(resolvedImage, context: context)
    }

    private func resolveImage(page: Int, context: Context) async throws -> ResolvedImage {
        let readerLink = try await readerLink(galleryURLString: context.galleryURLString, page: page, context: context)
        let imgKey = try imageKey(from: readerLink)
        let auth = try await galleryAuth(context: context, readerLink: readerLink)

        switch auth {
        case .mpv(let mpvKey, let imageKeys):
            guard imageKeys.indices.contains(page - 1) else {
                throw ComicContentError.invalidResponse("E-Hentai MPV 图片列表缺少第 \(page) 页。")
            }
            let image = try await mpvImage(
                page: page,
                imgKey: imageKeys[page - 1],
                mpvKey: mpvKey,
                nl: nil,
                context: context
            )
            return ResolvedImage(
                imageURLString: image.url,
                originalURLString: nil,
                nl: image.nl,
                readerLink: readerLink,
                imgKey: imgKey,
                page: page,
                usesMPV: true,
                mpvImageKey: imageKeys[page - 1],
                mpvKey: mpvKey
            )
        case .showKey(let showKey):
            let image: ResolvedImage
            do {
                image = try await showPageImage(
                    page: page,
                    imgKey: imgKey,
                    showKey: showKey,
                    readerLink: readerLink,
                    context: context
                )
            } catch {
                image = try await htmlImage(
                    page: page,
                    imgKey: imgKey,
                    readerLink: readerLink,
                    context: context
                )
            }

            if image.imageURLString.contains("509.gif") {
                throw ComicContentError.server("E-Hentai 图片配额已用尽。")
            }
            if context.prefersOriginalImage,
               let originalURLString = image.originalURLString,
               URL(string: originalURLString) != nil {
                var originalImage = image
                originalImage.imageURLString = originalURLString
                return originalImage
            }
            return image
        }
    }

    private func imageData(_ initialImage: ResolvedImage, context: Context) async throws -> Data {
        var image = initialImage
        var retryCount = 0
        while true {
            do {
                return try await downloadImageData(imageURLString: image.imageURLString, referer: image.readerLink, context: context)
            } catch {
                retryCount += 1
                guard retryCount < 4, let nl = image.nl else {
                    throw error
                }
                if image.usesMPV, let mpvImageKey = image.mpvImageKey, let mpvKey = image.mpvKey {
                    let next = try await mpvImage(
                        page: image.page,
                        imgKey: mpvImageKey,
                        mpvKey: mpvKey,
                        nl: nl,
                        context: context
                    )
                    image.imageURLString = next.url
                    image.nl = next.nl
                } else {
                    let next = try await imageLinkWithNL(
                        gid: context.gid,
                        imgKey: image.imgKey,
                        page: image.page,
                        nl: nl,
                        context: context
                    )
                    image.imageURLString = next.url
                    image.nl = next.nl ?? image.nl
                }
            }
        }
    }

    private func readerLink(galleryURLString: String, page: Int, context: Context) async throws -> String {
        let firstPageLinks = try await readerLinks(galleryURLString: galleryURLString, page: 1, context: context)
        if firstPageLinks.indices.contains(page - 1) {
            return firstPageLinks[page - 1]
        }

        let urlsOnePage = firstPageLinks.count
        guard urlsOnePage > 0 else {
            throw ComicContentError.invalidResponse("E-Hentai 章节没有返回阅读页。")
        }
        let shouldLoadPage = (page - 1) / urlsOnePage + 1
        let links = try await readerLinks(galleryURLString: galleryURLString, page: shouldLoadPage, context: context)
        let index = (page - 1) % urlsOnePage
        guard links.indices.contains(index) else {
            throw ComicContentError.invalidResponse("E-Hentai 章节第 \(page) 页没有返回阅读页。")
        }
        return links[index]
    }

    private func readerLinks(galleryURLString: String, page: Int, context: Context) async throws -> [String] {
        let urlString = galleryPageURL(galleryURLString, page: page)
        if let cachedLinks = readerLinksByURL[urlString] {
            return cachedLinks
        }
        while loadingReaderLinkURLs.contains(urlString) {
            try await Task.sleep(nanoseconds: 200_000_000)
            if let cachedLinks = readerLinksByURL[urlString] {
                return cachedLinks
            }
        }

        loadingReaderLinkURLs.insert(urlString)
        do {
            let html = try await requestString(urlString: urlString, context: context, referer: galleryURLString)
            let links = readerLinks(from: html, baseURLString: context.baseURLString)
            readerLinksByURL[urlString] = links
            loadingReaderLinkURLs.remove(urlString)
            return links
        } catch {
            loadingReaderLinkURLs.remove(urlString)
            throw error
        }
    }

    private func galleryAuth(context: Context, readerLink: String) async throws -> GalleryAuth {
        if let auth = authByContextKey[context.key] {
            return auth
        }
        while loadingAuthKeys.contains(context.key) {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let auth = authByContextKey[context.key] {
                return auth
            }
        }

        loadingAuthKeys.insert(context.key)
        do {
            let html = try await requestString(urlString: readerLink, context: context, referer: context.galleryURLString)
            let auth = try parseGalleryAuth(from: html)
            authByContextKey[context.key] = auth
            loadingAuthKeys.remove(context.key)
            return auth
        } catch {
            loadingAuthKeys.remove(context.key)
            throw error
        }
    }

    private func parseGalleryAuth(from html: String) throws -> GalleryAuth {
        if let showKey = html.firstRegexCapture(#"showkey\s*=\s*"([^"]+)""#) ??
            html.firstRegexCapture(#"showkey="([^"]+)""#) {
            return .showKey(showKey)
        }

        guard let mpvKey = html.firstRegexCapture(#"mpvkey\s*=\s*"([^"]+)""#),
              let imageListText = html.firstRegexCapture(#"imagelist\s*=\s*(\[.*?\])\s*;"#, options: [.dotMatchesLineSeparators]),
              let imageListData = imageListText.data(using: .utf8),
              let imageList = try? JSONSerialization.jsonObject(with: imageListData) as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("E-Hentai 阅读页缺少 showkey 或 mpvkey。")
        }

        let imageKeys = imageList.compactMap { $0["k"] as? String }
        guard !imageKeys.isEmpty else {
            throw ComicContentError.invalidResponse("E-Hentai MPV 图片列表为空。")
        }
        return .mpv(mpvKey: mpvKey, imageKeys: imageKeys)
    }

    private func showPageImage(
        page: Int,
        imgKey: String,
        showKey: String,
        readerLink: String,
        context: Context
    ) async throws -> ResolvedImage {
        let json = try await apiRequest(
            [
                "gid": Int(context.gid) ?? 0,
                "imgkey": imgKey,
                "method": "showpage",
                "page": page,
                "showkey": showKey
            ],
            context: context,
            referer: readerLink
        )
        guard let i3 = json["i3"] as? String else {
            throw ComicContentError.invalidResponse("E-Hentai API 响应缺少 i3。")
        }
        let image = i3.firstRegexCapture(#"src="([^"]+)""#)?.htmlDecoded ?? ""
        guard !image.isEmpty else {
            throw ComicContentError.invalidResponse("E-Hentai API 没有返回图片地址。")
        }

        let i6 = json["i6"] as? String ?? ""
        let nl = i6.firstRegexCapture(#"nl\('(.+?)'\)"#)
        let originalImage = originalImage(from: i6, baseURLString: context.baseURLString)
        return ResolvedImage(
            imageURLString: absoluteURL(image, baseURLString: context.baseURLString),
            originalURLString: originalImage,
            nl: nl,
            readerLink: readerLink,
            imgKey: imgKey,
            page: page,
            usesMPV: false,
            mpvImageKey: nil,
            mpvKey: nil
        )
    }

    private func htmlImage(
        page: Int,
        imgKey: String,
        readerLink: String,
        context: Context
    ) async throws -> ResolvedImage {
        let html = try await requestString(urlString: readerLink, context: context, referer: context.galleryURLString)
        guard let image = readerImage(from: html, baseURLString: context.baseURLString) else {
            throw ComicContentError.invalidResponse("E-Hentai 阅读页没有返回图片。")
        }
        return ResolvedImage(
            imageURLString: image,
            originalURLString: originalImage(from: html, baseURLString: context.baseURLString),
            nl: loadFailNL(from: html),
            readerLink: readerLink,
            imgKey: imgKey,
            page: page,
            usesMPV: false,
            mpvImageKey: nil,
            mpvKey: nil
        )
    }

    private func mpvImage(
        page: Int,
        imgKey: String,
        mpvKey: String,
        nl: String?,
        context: Context
    ) async throws -> (url: String, nl: String?) {
        var payload: [String: Any] = [
            "gid": Int(context.gid) ?? 0,
            "imgkey": imgKey,
            "method": "imagedispatch",
            "page": page,
            "mpvkey": mpvKey
        ]
        if let nl {
            payload["nl"] = nl
        }
        let json = try await apiRequest(payload, context: context, referer: context.galleryURLString)
        return (
            absoluteURL("\(json["i"] ?? "")", baseURLString: context.baseURLString),
            "\(json["s"] ?? "")".nilIfEmpty
        )
    }

    private func imageLinkWithNL(
        gid: String,
        imgKey: String,
        page: Int,
        nl: String,
        context: Context
    ) async throws -> (url: String, nl: String?) {
        let urlString = "\(context.baseURLString)/s/\(imgKey)/\(gid)-\(page)?nl=\(nl.urlEncoded)"
        let html = try await requestString(urlString: urlString, context: context, referer: context.galleryURLString)
        guard let image = readerImage(from: html, baseURLString: context.baseURLString) else {
            throw ComicContentError.invalidResponse("E-Hentai 重试页没有返回图片。")
        }
        return (image, loadFailNL(from: html))
    }

    private func downloadImageData(imageURLString: String, referer: String, context: Context) async throws -> Data {
        guard let url = URL(string: imageURLString) else {
            throw ComicContentError.invalidURL(imageURLString)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        headers(for: url, context: context, referer: referer, acceptsImage: true).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let (data, response) = try await dataResponseWithRetry(for: request)
        if let statusCode = response?.statusCode, !(200..<300).contains(statusCode) {
            throw ComicContentError.server("HTTP \(statusCode)")
        }
        if let contentType = response?.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            throw ComicContentError.invalidResponse("E-Hentai 返回了 HTML 而不是图片。")
        }
        if isLikelyHTML(data) {
            throw ComicContentError.invalidResponse("E-Hentai 返回了 HTML 而不是图片。")
        }
        return data
    }

    private func apiRequest(_ payload: [String: Any], context: Context, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: context.apiURLString) else {
            throw ComicContentError.invalidURL(context.apiURLString)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        var requestHeaders = headers(for: url, context: context, referer: referer, acceptsImage: false)
        requestHeaders["Accept"] = "application/json,text/plain,*/*"
        requestHeaders["Content-Type"] = "application/json"
        requestHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await dataResponseWithRetry(for: request)
        if let statusCode = response?.statusCode, !(200..<300).contains(statusCode) {
            throw ComicContentError.server("HTTP \(statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComicContentError.invalidResponse("E-Hentai API 返回不是 JSON 对象。")
        }
        if let error = json["error"] as? String, !error.isEmpty {
            throw ComicContentError.server(error)
        }
        return json
    }

    private func requestString(urlString: String, context: Context, referer: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ComicContentError.invalidURL(urlString)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        headers(for: url, context: context, referer: referer, acceptsImage: false).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let (data, response) = try await dataResponseWithRetry(for: request)
        if let statusCode = response?.statusCode, !(200..<300).contains(statusCode) {
            throw ComicContentError.server("HTTP \(statusCode)")
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ComicContentError.invalidResponse("接口返回无法按文本解析。")
        }
        if text.contains("Content Warning"), text.contains("Never Warn Me Again") {
            throw ComicContentError.server("E-Hentai 返回 Content Warning，需要网页登录确认。")
        }
        return text
    }

    private func dataResponseWithRetry(for request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        var lastError: Error?
        let attempts = AppNetworkSettings.retryAttempts

        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                if let statusCode = httpResponse?.statusCode,
                   shouldRetry(statusCode: statusCode),
                   attempt < attempts - 1 {
                    lastError = ComicContentError.server("HTTP \(statusCode)")
                    continue
                }
                return (data, httpResponse)
            } catch {
                lastError = error
                if attempt >= attempts - 1 {
                    break
                }
            }
        }

        throw lastError ?? ComicContentError.server("请求失败。")
    }

    private func headers(for url: URL, context: Context, referer: String, acceptsImage: Bool) -> [String: String] {
        var values = context.headers
        values["Referer"] = referer
        values["User-Agent"] = values["User-Agent"] ?? PlatformWebUserAgent.defaultBrowser
        if let host = url.host {
            values["Host"] = host
        }
        if acceptsImage {
            values["Accept"] = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
        }
        return values
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    private func galleryPageURL(_ rawURL: String, page: Int) -> String {
        guard page > 1 else { return rawURL }
        let separator = rawURL.contains("?") ? "&" : "?"
        return "\(rawURL)\(separator)p=\(page - 1)"
    }

    private func readerLinks(from html: String, baseURLString: String) -> [String] {
        var links = html.regexMatches(
            #"<div\b[^>]*id="gdt"[^>]*>.*?</div>\s*(?:<script|<div\b[^>]*class="gtb"|<table|\z)"#,
            options: [.dotMatchesLineSeparators]
        )
        .flatMap {
            $0.regexMatches(#"<a\b[^>]*href="((?:https?://[^"]+)?/s/[^"]+)""#)
                .compactMap { $0.firstRegexCapture(#"href="([^"]+)""#)?.htmlDecoded }
        }

        if links.isEmpty {
            links = html.regexMatches(#"href="((?:https?://[^"]+)?/s/[^"]+)""#)
                .compactMap { $0.firstRegexCapture(#"href="([^"]+)""#)?.htmlDecoded }
        }

        var seen = Set<String>()
        return links.compactMap { link in
            let absoluteLink = absoluteURL(link, baseURLString: baseURLString)
            return seen.insert(absoluteLink).inserted ? absoluteLink : nil
        }
    }

    private func imageKey(from readerLink: String) throws -> String {
        if let url = URL(string: readerLink) {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2, components[0] == "s" {
                return components[1]
            }
        }
        let parts = readerLink.split(separator: "/").map(String.init)
        guard parts.indices.contains(4), !parts[4].isEmpty else {
            throw ComicContentError.invalidResponse("E-Hentai 阅读页地址缺少图片 key。")
        }
        return parts[4]
    }

    private func readerImage(from html: String, baseURLString: String) -> String? {
        let image = html.firstRegexCapture(#"<div\b[^>]*id="i3"[^>]*>.*?<img\b[^>]+src="([^"]+)""#) ??
            html.firstRegexCapture(#"<img[^>]+id="img"[^>]+src="([^"]+)""#) ??
            html.firstRegexCapture(#"<img[^>]+src="([^"]+)"[^>]+id="img""#)
        return image.map { absoluteURL($0.htmlDecoded, baseURLString: baseURLString) }
    }

    private func originalImage(from html: String, baseURLString: String) -> String? {
        html.regexMatches(#"<a[^>]+href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators])
            .first { $0.strippingHTML.lowercased().contains("original") }
            .flatMap { $0.firstRegexCapture(#"href="([^"]+)""#)?.htmlDecoded }
            .map { absoluteURL($0, baseURLString: baseURLString) }
    }

    private func loadFailNL(from html: String) -> String? {
        html.firstRegexCapture(#"<a\b[^>]*id="loadfail"[^>]*onclick="[^"]*'([^']+-[^']*)'"#)
    }

    private func absoluteURL(_ value: String, baseURLString: String) -> String {
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        if value.hasPrefix("/") { return baseURLString + value }
        return value.isEmpty ? "" : "\(baseURLString)/\(value)"
    }

    private func isLikelyHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(256), encoding: .utf8)?.lowercased() else {
            return false
        }
        return prefix.contains("<html") || prefix.contains("<!doctype html")
    }

    private struct Context {
        let key: String
        let galleryURLString: String
        let gid: String
        let pageCount: Int
        let baseURLString: String
        let apiURLString: String
        let headers: [String: String]
        let prefersOriginalImage: Bool
    }

    private struct LazyImageRequest {
        let key: String
        let page: Int
    }

    private struct ResolvedImage {
        var imageURLString: String
        let originalURLString: String?
        var nl: String?
        let readerLink: String
        let imgKey: String
        let page: Int
        let usesMPV: Bool
        let mpvImageKey: String?
        let mpvKey: String?
    }

    private enum GalleryAuth {
        case showKey(String)
        case mpv(mpvKey: String, imageKeys: [String])
    }

    private nonisolated static func lazyImageURLString(key: String, page: Int) -> String {
        "\(scheme)://image/\(key)/\(page).jpg"
    }

    private nonisolated static func lazyImageRequest(from url: URL) -> LazyImageRequest? {
        guard isLazyImageURL(url), url.host == "image" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        let pageText = components[1].split(separator: ".").first.map(String.init) ?? components[1]
        guard let page = Int(pageText), page > 0 else { return nil }
        return LazyImageRequest(key: components[0], page: page)
    }

    private nonisolated static func galleryID(from value: String) -> String? {
        value.firstRegexCapture(#"/g/([0-9]+)/"#)
    }

    private nonisolated static func contextKey(
        galleryURLString: String,
        baseURLString: String,
        apiURLString: String,
        headers: [String: String],
        prefersOriginalImage: Bool
    ) -> String {
        let headerKey = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        let source = [
            galleryURLString,
            baseURLString,
            apiURLString,
            headerKey,
            prefersOriginalImage ? "original" : "resampled"
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension ComicContentService {
    var jmBaseURLs: [String] {
        let configuredBaseURLs = PlatformFeatureSettings.jmAPIBaseURLs()
        let fallbackBaseURLs = JmAPIEndpoint.fallbackBaseURLs
        let endpointID = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.jmAPIEndpoint) ?? JmAPIEndpoint.auto.rawValue
        let autoSelect = UserDefaults.standard.object(forKey: PlatformFeatureSettingsKey.jmAutoSelectAPIEndpoint) == nil
            ? true
            : UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.jmAutoSelectAPIEndpoint)
        guard let endpoint = JmAPIEndpoint(rawValue: endpointID) else {
            return uniqueBaseURLs(configuredBaseURLs + fallbackBaseURLs)
        }
        if endpoint == .auto || autoSelect {
            return uniqueBaseURLs(configuredBaseURLs + fallbackBaseURLs)
        }
        let selectedBaseURL = endpoint.dynamicIndex.flatMap { index in
            configuredBaseURLs.indices.contains(index) ? configuredBaseURLs[index] : nil
        } ?? endpoint.baseURLString
        guard let selectedBaseURL else {
            return uniqueBaseURLs(configuredBaseURLs + fallbackBaseURLs)
        }
        return uniqueBaseURLs([selectedBaseURL] + configuredBaseURLs + fallbackBaseURLs)
    }

    var jmImageBaseURL: String {
        let endpointID = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.jmImageEndpoint) ?? JmImageEndpoint.mspProxy3.rawValue
        let endpoint = JmImageEndpoint(rawValue: endpointID) ?? .mspProxy3
        if let baseURL = endpoint.baseURLString {
            return baseURL
        }
        let customBaseURL = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.jmCustomImageBaseURL) ?? ""
        return PlatformFeatureSettings.normalizedBaseURL(customBaseURL, fallback: JmImageEndpoint.defaultBaseURL)
    }

    var jmAppVersion: String {
        let value = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.jmAppVersion) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "2.0.26" : trimmed
    }
    var jmSecret: String { "185Hcomic3PAPP7R" }
    var jmAuthKey: String { "18comicAPPContent" }
    var jmDomainDecryptSecret: String { "diosfjckwpqpdfjkvnqQjsik" }
    var jmRemoteDomainURLs: [String] {
        [
            "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
            "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt"
        ]
    }

    func loadJmComicExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        switch entry {
        case .latest, .search:
            return try await jmComicItems(from: jmJSON(path: "latest?page=\(page)"))
        case .ranking:
            return try await jmComicItems(from: jmJSON(path: "categories/filter?o=mv&c=0&page=\(page)"))
        case .random:
            var items = try await jmComicItems(from: jmJSON(path: "latest?page=\(page)"))
            items.shuffle()
            return items
        }
    }

    func loadJmComicFavorites(account: PlatformAccount, folderID: String? = nil, page: Int = 1) async throws -> ComicFavoritePage {
        let context = try await jmAuthenticatedContext(account: account)
        let cookies = context.cookies
        let baseURL = context.loginInfo.baseURL
        let sort = PlatformFeatureSettings.jmFavoriteSort()
        let folderID = folderID?.nilIfEmpty ?? "0"
        let page = max(page, 1)
        let json = try await jmJSON(path: "favorite?page=\(page)&folder_id=\(folderID.urlEncoded)&o=\(sort)", cookies: cookies, baseURL: baseURL)
        let items = try jmComicItems(from: json, favoriteDate: Date())
        return ComicFavoritePage(items: items, page: page, hasMore: !items.isEmpty)
    }

    func loadJmComicFavoriteFolders(account: PlatformAccount?) async throws -> [PlatformFavoriteFolder] {
        guard let account else {
            throw ComicContentError.loginRequired("JMComic 收藏需要先登录平台账号。")
        }
        let context = try await jmAuthenticatedContext(account: account)
        let cookies = context.cookies
        let baseURL = context.loginInfo.baseURL
        guard let json = try await jmJSON(path: "favorite", cookies: cookies, baseURL: baseURL) as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 收藏夹响应不是对象。")
        }
        let folders = (json["folder_list"] as? [[String: Any]] ?? []).compactMap { folder -> PlatformFavoriteFolder? in
            guard let id = jmString(folder["FID"]), !id.isEmpty else { return nil }
            let title = jmString(folder["name"]) ?? id
            return PlatformFavoriteFolder(id: id, title: title, subtitle: "JMComic 收藏夹", platform: .jmComic)
        }
        return [PlatformFavoriteFolder(id: "0", title: "全部收藏", subtitle: "JMComic 默认收藏", platform: .jmComic)] + folders
    }

    func addJmComicFavorite(item: ComicListItem, folderID: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("JMComic 收藏需要先登录平台账号。")
        }
        let context = try await jmAuthenticatedContext(account: account)
        let cookies = context.cookies
        let baseURL = context.loginInfo.baseURL
        let id = jmComicID(from: item.id)
        let first = try await jmJSON(path: "favorite", method: "POST", body: "aid=\(id.urlEncoded)", cookies: cookies, baseURL: baseURL) as? [String: Any]
        if jmString(first?["type"]) != "add" {
            _ = try await jmJSON(path: "favorite", method: "POST", body: "aid=\(id.urlEncoded)", cookies: cookies, baseURL: baseURL)
        }
        if folderID != "0" {
            _ = try await jmJSON(path: "favorite_folder", method: "POST", body: "type=move&folder_id=\(folderID.urlEncoded)&aid=\(id.urlEncoded)", cookies: cookies, baseURL: baseURL)
        }
    }

    func likeJmComic(item: ComicListItem) async throws {
        let id = jmComicID(from: item.id)
        _ = try await jmJSON(path: "like", method: "POST", body: "id=\(id.urlEncoded)")
    }

    @discardableResult
    func jmLogin(account: PlatformAccount, cookies: HTTPCookieStorage) async throws -> String {
        let context = try await jmAuthenticatedContext(account: account)
        for cookie in context.cookies.cookies ?? [] {
            cookies.setCookie(cookie)
        }
        return context.loginInfo.baseURL
    }

    func jmLoginInfo(account: PlatformAccount, cookies: HTTPCookieStorage) async throws -> JmLoginInfo {
        let context = try await jmAuthenticatedContext(account: account)
        for cookie in context.cookies.cookies ?? [] {
            cookies.setCookie(cookie)
        }
        return context.loginInfo
    }

    func jmLoginInfo(username: String, password: String, cookies: HTTPCookieStorage) async throws -> JmLoginInfo {
        let body = "username=\(username.urlEncoded)&password=\(password.urlEncoded)"
        var lastError: Error?
        for baseURL in jmBaseURLs {
            do {
                let json = try await jmJSON(path: "login", method: "POST", body: body, cookies: cookies, baseURL: baseURL)
                guard let dict = json as? [String: Any],
                      let username = dict["username"] as? String,
                      !username.isEmpty else {
                    throw ComicContentError.invalidResponse("JMComic 登录响应缺少用户信息。")
                }
                return JmLoginInfo(baseURL: baseURL, userID: jmString(dict["uid"]))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ComicContentError.loginRequired("JMComic 登录失败。")
    }

    func jmStoredLoginInfo(account: PlatformAccount) throws -> JmLoginInfo {
        let baseURL = account.credential.baseURL?.nilIfEmpty ?? jmBaseURLs.first ?? "https://18comic.vip"
        return JmLoginInfo(baseURL: baseURL, userID: account.credential.profile?.username)
    }

    func jmAuthenticatedContext(account: PlatformAccount) async throws -> (cookies: HTTPCookieStorage, loginInfo: JmLoginInfo) {
        if !account.credential.cookies.isEmpty {
            return (account.credential.cookieStorage(), try jmStoredLoginInfo(account: account))
        }

        guard let password = account.credential.password?.nilIfEmpty else {
            throw ComicContentError.loginRequired("JMComic 登录信息已失效，请重新登录。")
        }

        let cookies = HTTPCookieStorage()
        let loginInfo = try await jmLoginInfo(username: account.username, password: password, cookies: cookies)
        return (cookies, loginInfo)
    }

    func loadJmComicDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        let id = jmComicID(from: item.id)
        guard let json = try await jmJSON(path: "album?id=\(id)") as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 详情响应不是对象。")
        }

        let authors = jmStringArray(json["author"])
        let tags = jmStringArray(json["tags"])
        let works = jmStringArray(json["works"])
        let actors = jmStringArray(json["actors"])
        let series = json["series"] as? [[String: Any]] ?? []
        let related = try jmComicItems(from: json["related_list"] as? [[String: Any]] ?? [])
        let likes = jmInt(json["likes"])
        let views = jmInt(json["total_views"])
        let comments = jmInt(json["comment_total"])
        let chapters = jmChapters(series: series, fallbackID: id)
        let tagGroups = [
            ComicTagGroup(title: "作者", tags: tagRefs(authors, platform: .jmComic)),
            ComicTagGroup(title: "标签", tags: tagRefs(tags, platform: .jmComic)),
            ComicTagGroup(title: "作品", tags: tagRefs(works, platform: .jmComic)),
            ComicTagGroup(title: "角色", tags: tagRefs(actors, platform: .jmComic))
        ].filter { !$0.tags.isEmpty }

        let detailItem = ComicListItem(
            id: id,
            platform: .jmComic,
            title: jmString(json["name"]) ?? item.title,
            subtitle: authors.first ?? item.subtitle,
            coverURLString: jmCoverURL(id: id),
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: nil,
            likesCount: likes,
            favoriteDate: item.favoriteDate
        )

        let infoText = [
            views.map { "阅读 \($0)" },
            likes.map { "喜欢 \($0)" },
            comments.map { "评论 \($0)" }
        ].compactMap { $0 }.joined(separator: " · ")

        return ComicDetailInfo(
            item: detailItem,
            description: jmString(json["description"]) ?? "",
            tagGroups: tagGroups,
            chapters: chapters,
            related: related,
            updatedText: infoText.isEmpty ? nil : infoText,
            isLiked: jmBool(json["liked"])
        )
    }

    func searchJmComic(query: String, page: Int, sort: String = "mr") async throws -> [ComicListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await jmComicItems(from: jmJSON(path: "latest?page=\(page)"))
        }
        let encoded = trimmed.urlEncoded.replacingOccurrences(of: "%20", with: "+")
        let json = try await jmJSON(path: "search?&search_query=\(encoded)&o=\(sort)&page=\(page)")
        return try jmComicItems(from: json)
    }

    func loadJmComicComments(item: ComicListItem, page: Int) async throws -> [ComicComment] {
        let id = jmComicID(from: item.id)
        guard let json = try await jmJSON(path: "forum?mode=manhua&aid=\(id)&page=\(page)") as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 评论响应不是对象。")
        }
        guard let list = json["list"] as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("JMComic 评论响应缺少 list。")
        }
        return list.map { jmComment(from: $0) }
    }

    func loadJmComicChapterComments(chapter: ComicChapter, page: Int) async throws -> [ComicComment] {
        let id = jmComicID(from: chapter.subtitle ?? chapter.id)
        guard let json = try await jmJSON(path: "forum?mode=manhua&aid=\(id)&page=\(page)") as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 章节评论响应不是对象。")
        }
        guard let list = json["list"] as? [[String: Any]] else {
            throw ComicContentError.invalidResponse("JMComic 章节评论响应缺少 list。")
        }
        return list.map { jmComment(from: $0) }
    }

    func postJmComicComment(item: ComicListItem, content: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("JMComic 评论需要先登录平台账号。")
        }
        let cookies = HTTPCookieStorage()
        let baseURL = try await jmLogin(account: account, cookies: cookies)
        let id = jmComicID(from: item.id)
        _ = try await jmJSON(path: "comment", method: "POST", body: "comment=\(content.urlEncoded)&status=undefined&aid=\(id.urlEncoded)", cookies: cookies, baseURL: baseURL)
    }

    func jmComment(from doc: [String: Any]) -> ComicComment {
        let replies = (doc["replys"] as? [[String: Any]] ?? []).map { reply in
            ComicComment(
                id: jmString(reply["CID"]) ?? UUID().uuidString,
                author: jmString(reply["username"]) ?? "Unknown",
                content: jmCommentContent(reply["content"]),
                timeText: jmString(reply["addtime"]),
                avatarURLString: jmAvatarURL(jmString(reply["photo"]) ?? ""),
                likesCount: nil,
                replyCount: nil,
                replies: []
            )
        }
        return ComicComment(
            id: jmString(doc["CID"]) ?? UUID().uuidString,
            author: jmString(doc["username"]) ?? "Unknown",
            content: jmCommentContent(doc["content"]),
            timeText: jmString(doc["addtime"]),
            avatarURLString: jmAvatarURL(jmString(doc["photo"]) ?? ""),
            likesCount: nil,
            replyCount: replies.isEmpty ? nil : replies.count,
            replies: replies
        )
    }

    func jmCommentContent(_ value: Any?) -> String {
        (jmString(value) ?? "").strippingHTML
    }

    func jmAvatarURL(_ imageName: String) -> String? {
        imageName.isEmpty ? nil : "\(jmImageBaseURL)/media/users/\(imageName)"
    }

    func jmJSON(path: String, method: String = "GET", body: String? = nil, cookies: HTTPCookieStorage? = nil, baseURL: String? = nil) async throws -> Any {
        if let baseURL {
            return try await jmJSON(path: path, method: method, body: body, cookies: cookies, baseURL: baseURL)
        }

        var lastError: Error?
        for baseURL in jmBaseURLs {
            do {
                return try await jmJSON(path: path, method: method, body: body, cookies: cookies, baseURL: baseURL)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ComicContentError.server("JMComic 请求失败。")
    }

    func jmJSON(path: String, method: String, body: String?, cookies: HTTPCookieStorage?, baseURL: String) async throws -> Any {
        let time = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw ComicContentError.invalidURL("JMComic \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = Data(body.utf8)
        }
        jmHeaders(time: time, post: method.uppercased() == "POST").forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookies {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies.cookies(for: url) ?? [])
            cookieHeader.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }

        let (data, response) = try await dataResponseWithRetry(for: request, cookies: cookies)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                let message = jmPlainErrorMessage(data) ?? "JMComic 登录状态无效。"
                throw ComicContentError.loginRequired(message)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ComicContentError.server("JMComic HTTP \(httpResponse.statusCode)")
            }
        }

        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 响应不是 JSON 对象。")
        }
        guard let encrypted = envelope["data"] as? String, !encrypted.isEmpty else {
            if let dataList = envelope["data"] as? [Any], dataList.isEmpty {
                throw ComicContentError.invalidResponse("JMComic 返回空数据。")
            }
            throw ComicContentError.invalidResponse("JMComic 响应缺少 data。")
        }
        let decoded = try jmDecrypt(encrypted, time: time)
        guard let decodedData = decoded.data(using: .utf8) else {
            throw ComicContentError.invalidResponse("JMComic 解密结果无法转为 UTF-8。")
        }
        return try JSONSerialization.jsonObject(with: decodedData)
    }

    func jmDecrypt(_ input: String, time: Int) throws -> String {
        guard let encrypted = Data(base64Encoded: input) else {
            throw ComicContentError.invalidResponse("JMComic data 不是有效 Base64。")
        }
        let key = Insecure.MD5.hash(data: Data("\(time)\(jmSecret)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let service = try AESECBService(key: Data(key.utf8), usesPKCS7Padding: false)
        let decrypted = try service.decrypt(encrypted)
        let text = String(decoding: decrypted, as: UTF8.self)
        guard let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else {
            throw ComicContentError.invalidResponse("JMComic 解密结果缺少 JSON 结束符。")
        }
        return String(text[...end])
    }

    func jmDecrypt(_ input: String, secret: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encrypted = Data(base64Encoded: trimmed) else {
            throw ComicContentError.invalidResponse("JMComic 域名数据不是有效 Base64。")
        }
        let key = Insecure.MD5.hash(data: Data(secret.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let service = try AESECBService(key: Data(key.utf8), usesPKCS7Padding: false)
        let decrypted = try service.decrypt(encrypted)
        let text = String(decoding: decrypted, as: UTF8.self)
        guard let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else {
            throw ComicContentError.invalidResponse("JMComic 域名解密结果缺少 JSON 结束符。")
        }
        return String(text[...end])
    }

    func loadRemoteJmAPIBaseURLs() async throws -> [String] {
        var lastError: Error?
        for urlString in jmRemoteDomainURLs {
            do {
                guard let url = URL(string: urlString) else { continue }
                let encrypted = try await requestString(url: url, headers: jmRemoteHeaders)
                let decoded = try jmDecrypt(encrypted, secret: jmDomainDecryptSecret)
                guard let data = decoded.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let domains = json["Server"] as? [String] else {
                    throw ComicContentError.invalidResponse("JMComic 域名响应缺少 Server。")
                }
                let baseURLs = domains.prefix(4).map {
                    PlatformFeatureSettings.normalizedBaseURL($0, fallback: "")
                }.filter {
                    URL(string: $0)?.host != nil
                }
                if !baseURLs.isEmpty {
                    return Array(baseURLs)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ComicContentError.server("JMComic API 域名更新失败。")
    }

    func loadRemoteJmAppVersion(baseURLs: [String]) async throws -> String {
        var lastError: Error?
        for baseURL in uniqueBaseURLs(baseURLs + jmBaseURLs) {
            do {
                guard let url = URL(string: "\(baseURL)/static/jmapp3apk/version.json") else { continue }
                let data = try await requestData(url: url, headers: jmRemoteHeaders)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = json["version"] as? String,
                      !version.isEmpty else {
                    throw ComicContentError.invalidResponse("JMComic App 版本响应缺少 version。")
                }
                return version
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ComicContentError.server("JMComic App 版本更新失败。")
    }

    func loadJmComicChapterImages(chapter: ComicChapter) async throws -> [String] {
        let id = jmComicID(from: chapter.subtitle ?? chapter.id)
        guard let json = try await jmJSON(path: "chapter?&id=\(id)") as? [String: Any] else {
            throw ComicContentError.invalidResponse("JMComic 章节响应不是对象。")
        }
        let images = jmStringArray(json["images"])
        return images.map { "\(jmImageBaseURL)/media/photos/\(id)/\($0)" }
    }

    func jmHeaders(time: Int, post: Bool) -> [String: String] {
        let token = Insecure.MD5.hash(data: Data("\(time)\(jmAuthKey)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        var headers = [
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            "Connection": "keep-alive",
            "Origin": "https://localhost",
            "Referer": "https://localhost/",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "cross-site",
            "Sec-Fetch-Storage-Access": "active",
            "X-Requested-With": "com.example.app",
            "Authorization": "Bearer",
            "token": token,
            "tokenparam": "\(time),\(jmAppVersion)",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.0.0 Mobile Safari/537.36"
        ]
        if post {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        }
        return headers
    }

    var jmRemoteHeaders: [String: String] {
        [
            "Accept": "application/json,text/plain,*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.0.0 Mobile Safari/537.36"
        ]
    }

    func uniqueBaseURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for value in values {
            let normalized = PlatformFeatureSettings.normalizedBaseURL(value, fallback: "")
            guard URL(string: normalized)?.host != nil, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    func jmPlainErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return json["errorMsg"] as? String ?? json["message"] as? String
    }

    func jmComicItems(from value: Any, favoriteDate: Date? = nil) throws -> [ComicListItem] {
        let rows: [[String: Any]]
        if let list = value as? [[String: Any]] {
            rows = list
        } else if let dict = value as? [String: Any],
                  let content = dict["content"] as? [[String: Any]] {
            rows = content
        } else if let dict = value as? [String: Any],
                  let list = dict["list"] as? [[String: Any]] {
            rows = list
        } else {
            throw ComicContentError.invalidResponse("JMComic 列表响应缺少漫画数组。")
        }
        return rows.compactMap { jmComicItem(from: $0, favoriteDate: favoriteDate) }
    }

    func jmComicItem(from comic: [String: Any], favoriteDate: Date?) -> ComicListItem? {
        guard let id = jmString(comic["id"]), !id.isEmpty else { return nil }
        let categoryNames = [
            jmCategoryName(comic["category"]),
            jmCategoryName(comic["category_sub"])
        ].compactMap { $0 }
        return ComicListItem(
            id: id,
            platform: .jmComic,
            title: jmString(comic["name"]) ?? id,
            subtitle: jmString(comic["author"]) ?? "Unknown",
            coverURLString: jmCoverURL(id: id),
            tags: categoryNames,
            pageCount: nil,
            likesCount: nil,
            favoriteDate: favoriteDate
        )
    }

    func jmChapters(series: [[String: Any]], fallbackID: String) -> [ComicChapter] {
        guard !series.isEmpty else {
            return [ComicChapter(id: fallbackID, title: "第 1 话", subtitle: fallbackID)]
        }
        let orderedChapters: [(order: Int, chapter: ComicChapter)] = series.enumerated().compactMap { index, value in
            guard let id = jmString(value["id"]) else { return nil }
            let fallbackTitle = "第 \(jmString(value["sort"]) ?? "\(index + 1)") 话"
            let title = jmString(value["name"]).flatMap(\.nilIfEmpty) ?? fallbackTitle
            let order = jmInt(value["sort"]) ?? index + 1
            return (order, ComicChapter(id: id, title: title, subtitle: id))
        }
        return orderedChapters
            .sorted { $0.order < $1.order }
            .map(\.chapter)
    }

    func jmCoverURL(id: String) -> String {
        "\(jmImageBaseURL)/media/albums/\(id)_3x4.jpg"
    }

    func jmComicID(from rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "jm", with: "", options: [.caseInsensitive])
    }

    func jmCategoryName(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        return jmString(dict["title"]) ?? jmString(dict["name"])
    }

    func jmStringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.compactMap(jmString).filter { !$0.isEmpty }
        }
        return jmString(value).map { [$0] } ?? []
    }

    func jmString(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            return "\(Int(double))"
        }
        return nil
    }

    func jmInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    func jmBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

private extension ComicContentService {
    var hitomiDataDomain: String {
        let value = UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.hitomiDataDomain) ?? ""
        return PlatformFeatureSettings.normalizedDomain(value, fallback: "gold-usergeneratedcontent.net")
    }

    var hitomiPublicBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .hitomi)
    }

    func loadHitomiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let path: String
        switch entry {
        case .latest:
            path = "index-all.nozomi"
        case .ranking:
            path = "popular/today-all.nozomi"
        case .random:
            path = "index-all.nozomi"
        case .search:
            throw ComicContentError.unsupported("Hitomi 搜索入口需要关键词；标签页已接入二进制索引。")
        }

        let pageSize = 24
        var ids = try await hitomiIDsFromNozomi(path: path, maxIDs: page * pageSize + pageSize)
        if entry == .random {
            ids.shuffle()
        }
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return [] }
        return try await hitomiItems(for: Array(ids.dropFirst(start)), limit: pageSize)
    }

    func loadHitomiDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        let id = try hitomiID(from: item.id)
        let brief = try await hitomiBrief(id: id)
        let jsURL = try hitomiURL(path: "galleries/\(id).js")
        let script = try await requestString(url: jsURL, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        guard let start = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}") else {
            throw ComicContentError.invalidResponse("Hitomi galleries.js 缺少 JSON 数据。")
        }
        let jsonData = Data(script[start...end].utf8)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ComicContentError.invalidResponse("Hitomi 详情 JSON 无法解析。")
        }

        let files = json["files"] as? [[String: Any]] ?? []
        let artists = hitomiNamedTags(json["artists"], key: "artist", namespace: "artist")
        let groups = hitomiNamedTags(json["groups"], key: "group", namespace: "group")
        let parodys = hitomiNamedTags(json["parodys"], key: "parody", namespace: "parody")
        let characters = hitomiNamedTags(json["characters"], key: "character", namespace: "character")
        let tags = hitomiGalleryTags(json["tags"])
        let type = (json["type"] as? String ?? brief.type).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = (json["language"] as? String ?? brief.language).trimmingCharacters(in: .whitespacesAndNewlines)
        let typeTags = type.isEmpty ? [] : [ComicTagReference(title: type, query: type.lowercased(), platform: .hitomi, urlString: nil)]
        let languageTags = language.isEmpty ? [] : [ComicTagReference(title: language, query: "language:\(language.lowercased())", platform: .hitomi, urlString: nil)]
        let tagGroups = [
            ComicTagGroup(title: "类型", tags: typeTags),
            ComicTagGroup(title: "语言", tags: languageTags),
            ComicTagGroup(title: "作者", tags: artists),
            ComicTagGroup(title: "分组", tags: groups),
            ComicTagGroup(title: "原作", tags: parodys),
            ComicTagGroup(title: "角色", tags: characters),
            ComicTagGroup(title: "标签", tags: tags.isEmpty ? brief.tags : tags)
        ].filter { !$0.tags.isEmpty }

        let detailItem = ComicListItem(
            id: brief.item.id,
            platform: .hitomi,
            title: json["title"] as? String ?? brief.item.title,
            subtitle: artists.first?.title ?? brief.item.subtitle,
            coverURLString: brief.item.coverURLString.isEmpty ? item.coverURLString : brief.item.coverURLString,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: files.count,
            likesCount: nil,
            favoriteDate: item.favoriteDate
        )

        var relatedItems = [ComicListItem]()
        for relatedID in hitomiRelatedIDs(json["related"]).prefix(6) {
            if let related = try? await hitomiBrief(id: "\(relatedID)") {
                relatedItems.append(related.item)
            }
        }

        return ComicDetailInfo(
            item: detailItem,
            description: "",
            tagGroups: tagGroups,
            chapters: singleReaderChapter(),
            related: relatedItems,
            updatedText: json["date"] as? String ?? brief.updatedText
        )
    }

    func searchHitomi(tag: ComicTagReference, page: Int) async throws -> [ComicListItem] {
        let ids = try await hitomiSearchIDs(query: tag.query)
        let pageSize = 24
        let start = max(0, (page - 1) * pageSize)
        guard start < ids.count else { return [] }
        return try await hitomiItems(for: Array(ids.dropFirst(start)), limit: pageSize)
    }

    func hitomiItems(for ids: [Int], limit: Int) async throws -> [ComicListItem] {
        var items = [ComicListItem]()
        for id in ids.prefix(limit * 2) {
            if let brief = try? await hitomiBrief(id: "\(id)") {
                items.append(brief.item)
            }
            if items.count >= limit {
                break
            }
        }
        guard !items.isEmpty else {
            throw ComicContentError.invalidResponse("Hitomi 没有返回可展示的漫画。")
        }
        return items
    }

    func hitomiBrief(id: String) async throws -> HitomiBrief {
        let url = try hitomiURL(path: "galleryblock/\(id).html")
        let html = try await requestString(url: url, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        let title = html.firstRegexCapture(#"<h1[^>]*class="[^"]*lillie[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? id
        let linkPath = html.firstRegexCapture(#"<h1[^>]*class="[^"]*lillie[^"]*"[^>]*>\s*<a[^>]+href="([^"]+)""#) ?? "/galleries/\(id).html"
        let artist = html.firstRegexCapture(#"<div[^>]*class="[^"]*artist-list[^"]*"[^>]*>.*?<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? "N/A"
        let coverSource = html.firstRegexCapture(#"<div[^>]*class="[^"]*(?:dj-img1|cg-img1)[^"]*"[^>]*>.*?<source[^>]+data-srcset="([^"]+)""#)
        let tags = hitomiBriefTags(html)
        let item = ComicListItem(
            id: absoluteURL(linkPath, baseURL: hitomiPublicBaseURL),
            platform: .hitomi,
            title: title,
            subtitle: artist,
            coverURLString: hitomiCoverURL(from: coverSource),
            tags: tags.map(\.title),
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
        return HitomiBrief(
            item: item,
            type: hitomiTableValue(html, label: "Type"),
            language: hitomiTableValue(html, label: "Language"),
            tags: tags,
            updatedText: html.firstRegexCapture(#"<div[^>]*class="[^"]*dj-content[^"]*"[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded
        )
    }

    func hitomiSearchIDs(query: String) async throws -> [Int] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ")
        guard !normalized.isEmpty else {
            return try await hitomiIDsFromNozomi(path: "index-all.nozomi", maxIDs: 80)
        }
        if normalized.contains(":") {
            return try await hitomiIDsForNamespacedQuery(normalized)
        }

        let version = try await hitomiIndexVersion()
        let key = Array(SHA256.hash(data: Data(normalized.utf8)).prefix(4))
        let node = try await hitomiIndexNode(field: "galleries", address: 0, version: version)
        guard let dataRange = try await hitomiBSearch(field: "galleries", key: key, node: node, version: version) else {
            return []
        }
        return try await hitomiIDsFromIndexData(offset: dataRange.offset, length: dataRange.length, version: version)
    }

    func hitomiIDsForNamespacedQuery(_ query: String) async throws -> [Int] {
        let parts = query.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let namespace = parts[0]
        let value = parts[1]
        if namespace == "language" {
            return try await hitomiIDsFromNozomi(path: "n/index-\(value).nozomi", maxIDs: 120)
        }
        let area: String
        let tag: String
        if namespace == "female" || namespace == "male" {
            area = "tag"
            tag = query
        } else {
            area = namespace
            tag = value
        }
        return try await hitomiIDsFromNozomi(path: "n/\(area)/\(tag)-all.nozomi", maxIDs: 120)
    }

    func hitomiIDsFromNozomi(path: String, maxIDs: Int) async throws -> [Int] {
        let url = try hitomiURL(path: path)
        let end = max(3, maxIDs * 4 - 1)
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: hitomiPublicBaseURL).merging(["Range": "bytes=0-\(end)"]) { _, new in new })
        return hitomiIDs(fromBigEndianData: data)
    }

    func hitomiIndexVersion() async throws -> String {
        let url = try hitomiURL(path: "galleriesindex/version?_=\(Int(Date().timeIntervalSince1970))")
        return try await requestString(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hitomiIndexNode(field: String, address: Int, version: String) async throws -> HitomiIndexNode {
        let url = try hitomiURL(path: "galleriesindex/\(field).\(version).index")
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html").merging(["Range": "bytes=\(address)-\(address + 463)"]) { _, new in new })
        guard let node = hitomiDecodeNode(data) else {
            throw ComicContentError.invalidResponse("Hitomi 索引节点无法解析。")
        }
        return node
    }

    func hitomiBSearch(field: String, key: [UInt8], node: HitomiIndexNode, version: String) async throws -> (offset: Int, length: Int)? {
        let (found, index) = hitomiLocateKey(key, in: node)
        if found {
            guard index < node.data.count else { return nil }
            return node.data[index]
        }
        guard !node.subnodeAddresses.allSatisfy({ $0 == 0 }),
              index < node.subnodeAddresses.count,
              node.subnodeAddresses[index] > 0 else {
            return nil
        }
        let next = try await hitomiIndexNode(field: field, address: node.subnodeAddresses[index], version: version)
        return try await hitomiBSearch(field: field, key: key, node: next, version: version)
    }

    func hitomiIDsFromIndexData(offset: Int, length: Int, version: String) async throws -> [Int] {
        guard length > 4 else { return [] }
        let url = try hitomiURL(path: "galleriesindex/galleries.\(version).data")
        let data = try await requestData(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/search.html").merging(["Range": "bytes=\(offset)-\(offset + length - 1)"]) { _, new in new })
        let bytes = [UInt8](data)
        guard let count = hitomiInt32BE(bytes, at: 0), count > 0, bytes.count >= count * 4 + 4 else {
            return []
        }
        return stride(from: 0, to: count, by: 1).compactMap { index in
            hitomiInt32BE(bytes, at: 4 + index * 4)
        }
    }

    func hitomiDecodeNode(_ data: Data) -> HitomiIndexNode? {
        let bytes = [UInt8](data)
        var position = 0
        guard let numberOfKeys = hitomiInt32BE(bytes, at: position), numberOfKeys >= 0, numberOfKeys <= 32 else { return nil }
        position += 4

        var keys = [[UInt8]]()
        for _ in 0..<numberOfKeys {
            guard let keySize = hitomiInt32BE(bytes, at: position), keySize > 0, keySize <= 32, position + 4 + keySize <= bytes.count else {
                return nil
            }
            position += 4
            keys.append(Array(bytes[position..<(position + keySize)]))
            position += keySize
        }

        guard let numberOfData = hitomiInt32BE(bytes, at: position), numberOfData >= 0, numberOfData <= 32 else { return nil }
        position += 4
        var dataRanges = [(offset: Int, length: Int)]()
        for _ in 0..<numberOfData {
            guard let offset = hitomiUInt64BE(bytes, at: position), let length = hitomiInt32BE(bytes, at: position + 8) else {
                return nil
            }
            position += 12
            dataRanges.append((offset: Int(offset), length: length))
        }

        var subnodeAddresses = [Int]()
        for _ in 0..<17 {
            guard let address = hitomiUInt64BE(bytes, at: position) else { return nil }
            position += 8
            subnodeAddresses.append(Int(address))
        }
        return HitomiIndexNode(keys: keys, data: dataRanges, subnodeAddresses: subnodeAddresses)
    }

    func hitomiLocateKey(_ key: [UInt8], in node: HitomiIndexNode) -> (found: Bool, index: Int) {
        var compareResult = -1
        var index = 0
        while index < node.keys.count {
            compareResult = hitomiCompare(key, node.keys[index])
            if compareResult <= 0 {
                break
            }
            index += 1
        }
        return (compareResult == 0, index)
    }

    func hitomiCompare(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        for index in 0..<min(lhs.count, rhs.count) {
            if lhs[index] < rhs[index] { return -1 }
            if lhs[index] > rhs[index] { return 1 }
        }
        return 0
    }

    func hitomiIDs(fromBigEndianData data: Data) -> [Int] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - (bytes.count % 4), by: 4).compactMap { offset in
            hitomiInt32BE(bytes, at: offset)
        }
    }

    func hitomiInt32BE(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        return Int(Int32(bitPattern: value))
    }

    func hitomiUInt64BE(_ bytes: [UInt8], at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        return bytes[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    func hitomiID(from target: String) throws -> String {
        if Int(target) != nil {
            return target
        }
        if let id = target.firstRegexCapture(#"([0-9]+)(?=\.html)"#) ?? target.firstRegexCapture(#"([0-9]+)"#) {
            return id
        }
        throw ComicContentError.invalidURL("Hitomi ID \(target)")
    }

    func hitomiURL(path: String) throws -> URL {
        var rawPath = path.hasPrefix("/") ? path : "/\(path)"
        if rawPath.contains("?") {
            let parts = rawPath.split(separator: "?", maxSplits: 1).map(String.init)
            rawPath = (parts.first ?? rawPath).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).map { "\($0)?\(parts.dropFirst().first ?? "")" } ?? rawPath
        } else {
            rawPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath
        }
        guard let url = URL(string: "https://ltn.\(hitomiDataDomain)\(rawPath)") else {
            throw ComicContentError.invalidURL("Hitomi \(path)")
        }
        return url
    }

    func hitomiHeaders(referer: String) -> [String: String] {
        webHeaders(referer: referer).merging(["Origin": hitomiPublicBaseURL]) { _, new in new }
    }

    func hitomiCoverURL(from source: String?) -> String {
        guard var cover = source?.trimmingCharacters(in: .whitespacesAndNewlines), !cover.isEmpty else {
            return ""
        }
        if cover.hasPrefix("//") {
            cover = String(cover.dropFirst(2))
            if let slash = cover.firstIndex(of: "/") {
                cover = String(cover[slash...])
            }
        }
        if let range = cover.range(of: #"2x.*"#, options: .regularExpression) {
            cover.removeSubrange(range)
        }
        cover = cover.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "avifbigtn", with: "webpbigtn")
            .replacingOccurrences(of: ".avif", with: ".webp")
        return cover.hasPrefix("http") ? cover : "https://atn.\(hitomiDataDomain)\(cover)"
    }

    func hitomiTableValue(_ html: String, label: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<tr>\s*<td>\s*"# + escaped + #"\s*</td>\s*<td[^>]*>(.*?)</td>"#
        return html.firstRegexCapture(pattern)?.htmlDecoded ?? ""
    }

    func hitomiBriefTags(_ html: String) -> [ComicTagReference] {
        let rows = html.regexMatches(#"<td[^>]*class="[^"]*(?:series-list|relatedtags)[^"]*"[^>]*>.*?</td>"#, options: [.dotMatchesLineSeparators])
        return rows.flatMap { row in
            row.regexMatches(#"<a[^>]+href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators]).compactMap { linkHTML -> ComicTagReference? in
                guard let link = linkHTML.firstRegexCapture(#"href="([^"]+)""#) else { return nil }
                let title = linkHTML.strippingHTML
                guard !title.isEmpty, title != "N/A" else { return nil }
                return ComicTagReference(title: title, query: hitomiQuery(title: title, link: link), platform: .hitomi, urlString: absoluteURL(link, baseURL: hitomiPublicBaseURL))
            }
        }
    }

    func hitomiNamedTags(_ value: Any?, key: String, namespace: String) -> [ComicTagReference] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let title = (item[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return nil
            }
            let url = (item["url"] as? String).map { absoluteURL($0, baseURL: "https://ltn.\(hitomiDataDomain)") }
            return ComicTagReference(title: title, query: "\(namespace):\(title.lowercased())", platform: .hitomi, urlString: url)
        }
    }

    func hitomiGalleryTags(_ value: Any?) -> [ComicTagReference] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let name = (item["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            let isFemale = hitomiBool(item["female"])
            let isMale = hitomiBool(item["male"])
            let title = name + (isFemale ? " ♀" : isMale ? " ♂" : "")
            let namespace = isFemale ? "female" : isMale ? "male" : "tag"
            let url = (item["url"] as? String).map { absoluteURL($0, baseURL: "https://ltn.\(hitomiDataDomain)") }
            return ComicTagReference(title: title, query: "\(namespace):\(name.lowercased())", platform: .hitomi, urlString: url)
        }
    }

    func hitomiQuery(title: String, link: String) -> String {
        let decoded = (link.removingPercentEncoding ?? link).lowercased()
        for namespace in ["artist", "group", "series", "character", "tag", "language"] {
            guard let range = decoded.range(of: "/\(namespace)/") else { continue }
            var value = String(decoded[range.upperBound...])
            if let end = value.range(of: "-all")?.lowerBound ?? value.range(of: ".html")?.lowerBound {
                value = String(value[..<end])
            }
            return namespace == "tag" ? value : "\(namespace):\(value)"
        }
        return title.lowercased()
    }

    func hitomiRelatedIDs(_ value: Any?) -> [Int] {
        if let values = value as? [Int] {
            return values
        }
        if let values = value as? [String] {
            return values.compactMap(Int.init)
        }
        return []
    }

    func hitomiBool(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int == 1 }
        if let string = value as? String { return string == "1" || string.lowercased() == "true" }
        return false
    }

    func loadHitomiImages(item: ComicListItem) async throws -> [String] {
        let id = try hitomiID(from: item.id)
        let jsURL = try hitomiURL(path: "galleries/\(id).js")
        let script = try await requestString(url: jsURL, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        guard let start = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}") else {
            throw ComicContentError.invalidResponse("Hitomi galleries.js 缺少 JSON 数据。")
        }
        let jsonData = Data(script[start...end].utf8)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ComicContentError.invalidResponse("Hitomi 详情 JSON 无法解析。")
        }
        let gg = try await hitomiGG(galleryID: id)
        let files = json["files"] as? [[String: Any]] ?? []
        return files.compactMap { file in
            guard let hash = file["hash"] as? String, !hash.isEmpty else { return nil }
            let name = file["name"] as? String ?? "\(hash).webp"
            let ext = (file.intValue(for: "haswebp") == 1) ? "webp" : (name.components(separatedBy: ".").last ?? "jpg")
            return hitomiImageURL(hash: hash, ext: ext, gg: gg)
        }
    }

    func hitomiGG(galleryID: String) async throws -> HitomiGGData {
        let url = try hitomiURL(path: "gg.js?_=1683939645979")
        let js = try await requestString(url: url, headers: hitomiHeaders(referer: "\(hitomiPublicBaseURL)/reader/\(galleryID).html"))
        let numbers = js.regexMatches(#"(?<=case )\d+"#)
        let b = js.firstRegexCapture(#"b: '(\d+)"#) ?? "0"
        let initialG = js.firstRegexCapture(#"var o = ([0-9]+)"#).flatMap(Int.init) ?? 1
        return HitomiGGData(numbers: Set(numbers), b: b, initialG: initialG)
    }

    func hitomiImageURL(hash: String, ext: String, gg: HitomiGGData) -> String {
        let path = "\(gg.b)/\(hitomiHashSuffix(hash))/\(hash)"
        let raw = "https://\(hitomiDataDomain)/\(path).\(ext)"
        return raw.replacingOccurrences(of: "https://", with: "https://\(hitomiSubdomain(from: raw, base: "w", gg: gg)).")
    }

    func hitomiHashSuffix(_ hash: String) -> String {
        guard hash.count >= 3 else { return "" }
        let lastTwoStart = hash.index(hash.endIndex, offsetBy: -3)
        let pairStart = hash.index(hash.endIndex, offsetBy: -2)
        let pair = String(hash[pairStart...])
        let single = String(hash[lastTwoStart])
        return Int(single + pair, radix: 16).map(String.init) ?? ""
    }

    func hitomiSubdomain(from url: String, base: String, gg: HitomiGGData) -> String {
        let pattern = #"/[0-9a-f]{61}([0-9a-f]{2})([0-9a-f])"#
        guard let match = url.firstRegexCapturePair(pattern),
              let value = Int(match.1 + match.0, radix: 16) else {
            return "a"
        }
        let bit = gg.numbers.contains("\(value)") ? (~gg.initialG & 1) : gg.initialG
        let character = bit == 0 ? "a" : "b"
        if base == "w" {
            return character == "a" ? "w1" : "w2"
        }
        return "\(character)\(base)"
    }
}

private extension ComicContentService {
    func requestJSON(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> [String: Any] {
        let data = try await requestData(url: url, method: method, headers: headers, body: body)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw ComicContentError.invalidResponse("接口返回不是 JSON 对象。")
        }
        if let message = json["message"] as? String, message != "success" {
            throw ComicContentError.server(message)
        }
        return json
    }

    func requestString(url: URL, headers: [String: String] = [:], cookies: HTTPCookieStorage? = nil) async throws -> String {
        let data = try await requestData(url: url, headers: headers, cookies: cookies)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ComicContentError.invalidResponse("接口返回无法按文本解析。")
        }
        return text
    }

    func requestData(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, cookies: HTTPCookieStorage? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookies {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies.cookies(for: url) ?? [])
            cookieHeader.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }
        let (data, response) = try await dataResponseWithRetry(for: request, cookies: cookies)
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ComicContentError.server("HTTP \(httpResponse.statusCode)")
            }
        }
        return data
    }

    func dataResponseWithRetry(for request: URLRequest, cookies: HTTPCookieStorage?) async throws -> (Data, URLResponse) {
        var lastError: Error?
        let attempts = AppNetworkSettings.retryAttempts

        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                saveCookies(from: response, requestURL: request.url, cookies: cookies)

                if let httpResponse = response as? HTTPURLResponse,
                   shouldRetry(statusCode: httpResponse.statusCode),
                   attempt < attempts - 1 {
                    lastError = ComicContentError.server("HTTP \(httpResponse.statusCode)")
                    continue
                }

                return (data, response)
            } catch {
                lastError = error
                if attempt >= attempts - 1 {
                    break
                }
            }
        }

        throw lastError ?? ComicContentError.server("请求失败。")
    }

    func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    func isUnauthorized(_ error: Error) -> Bool {
        if case ComicContentError.server(let message) = error {
            return message == "HTTP 401" || message == "HTTP 403"
        }
        return false
    }

    func saveCookies(from response: URLResponse, requestURL: URL?, cookies: HTTPCookieStorage?) {
        guard let cookies,
              let url = requestURL,
              let httpResponse = response as? HTTPURLResponse else {
            return
        }

        let fields = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, element in
            guard let key = element.key as? String else { return }
            result[key] = "\(element.value)"
        }
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        cookies.setCookies(responseCookies, for: url, mainDocumentURL: url)
    }

    func storedCookies(from storage: HTTPCookieStorage, baseURLs: [String]) -> [StoredHTTPCookie] {
        var values = [StoredHTTPCookie]()
        var seen = Set<String>()
        for baseURL in baseURLs {
            guard let url = URL(string: baseURL) else { continue }
            for cookie in storage.cookies(for: url) ?? [] {
                let stored = StoredHTTPCookie(cookie: cookie)
                guard !stored.value.isEmpty, seen.insert(stored.id).inserted else { continue }
                values.append(stored)
            }
        }
        return values
    }

    func storedCookies(from cookies: [HTTPCookie]) -> [StoredHTTPCookie] {
        var values = [StoredHTTPCookie]()
        var seen = Set<String>()
        for cookie in cookies {
            let stored = StoredHTTPCookie(cookie: cookie)
            guard !stored.value.isEmpty, seen.insert(stored.id).inserted else { continue }
            values.append(stored)
        }
        return values
    }

    func defaultCategories(platform: ComicPlatform) -> [ComicCategoryItem] {
        switch platform {
        case .picacg:
            return []
        case .jmComic:
            return [
                category("最新A漫", platform, query: "最新A漫"),
                category("同人", platform),
                category("單本", platform),
                category("短篇", platform),
                category("韓漫", platform),
                category("美漫", platform),
                category("Cosplay", platform),
                category("3D", platform),
                category("禁漫漢化組", platform),
                category("全彩", platform),
                category("纯爱", platform),
                category("人妻", platform),
                category("NTR", platform),
                category("百合", platform),
                category("教师", platform),
                category("御姐", platform),
                category("巨乳", platform)
            ]
        case .nhentai:
            return nhentaiDefaultCategories(platform: platform)
        case .hitomi:
            return [
                category("中文", platform, query: "language:chinese"),
                category("日本語", platform, query: "language:japanese"),
                category("English", platform, query: "language:english"),
                category("doujinshi", platform),
                category("manga", platform),
                category("artistcg", platform),
                category("gamecg", platform),
                category("imageset", platform),
                category("cosplay", platform)
            ]
        case .htManga:
            return [
                category("Cosplay", platform),
                category("3D", platform),
                category("同人", platform),
                category("單行本", platform),
                category("短篇", platform),
                category("全彩", platform)
            ]
        case .eHentai:
            return EhTagTranslationService.categorySuggestions(limitPerNamespace: 20).map { suggestion in
                ComicCategoryItem(
                    title: suggestion.translatedTitle,
                    query: suggestion.categoryQuery,
                    platform: platform,
                    subtitle: "\(suggestion.namespaceTitle) · \(suggestion.query)",
                    coverURLString: nil,
                    groupTitle: suggestion.namespaceTitle
                )
            }
        }
    }

    func nhentaiDefaultCategories(platform: ComicPlatform) -> [ComicCategoryItem] {
        NhentaiTagSuggestionService.categorySuggestions(limitPerGroup: 50).map { suggestion in
            ComicCategoryItem(
                title: suggestion.translatedTitle,
                query: suggestion.query,
                platform: platform,
                subtitle: "\(suggestion.groupTitle) · \(suggestion.query)",
                coverURLString: nil,
                groupTitle: suggestion.groupTitle
            )
        }
    }

    func category(_ title: String, _ platform: ComicPlatform, query: String? = nil) -> ComicCategoryItem {
        let value = query ?? title
        return ComicCategoryItem(
            title: title,
            query: value,
            platform: platform,
            subtitle: value == title ? "按 \(title) 浏览" : value,
            coverURLString: nil,
            groupTitle: nil
        )
    }

    func webHeaders(referer: String, userAgent: String? = nil) -> [String: String] {
        var headers = [
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
            "Referer": referer,
            "User-Agent": PlatformWebUserAgent.normalized(userAgent)
        ]
        if referer.contains("e-hentai.org") || referer.contains("exhentai.org") {
            var cookies = ["nw=\(UserDefaults.standard.bool(forKey: PlatformFeatureSettingsKey.ehentaiIgnoresContentWarning) ? "1" : "0")"]
            let profile = (UserDefaults.standard.string(forKey: PlatformFeatureSettingsKey.ehentaiProfile) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.isEmpty {
                cookies.append("sp=\(profile)")
            }
            headers["Cookie"] = cookies.joined(separator: "; ")
        }
        return headers
    }

    func absoluteURL(_ value: String, baseURL: String) -> String {
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        if value.hasPrefix("/") { return baseURL + value }
        return value.isEmpty ? "" : "\(baseURL)/\(value)"
    }

    func tagRefs(_ values: [String], platform: ComicPlatform, prefix: String = "") -> [ComicTagReference] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ComicTagReference(title: $0, query: "\(prefix)\($0)", platform: platform, urlString: nil) }
    }

    func picacgScopedTagRefs(_ values: [String], prefix: String) -> [ComicTagReference] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ComicTagReference(title: $0, query: "\(prefix)\($0)", platform: .picacg, urlString: nil) }
    }
}

struct LocalFavoritesStore: Sendable {
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

private struct HitomiBrief {
    let item: ComicListItem
    let type: String
    let language: String
    let tags: [ComicTagReference]
    let updatedText: String?
}

private struct HitomiIndexNode {
    let keys: [[UInt8]]
    let data: [(offset: Int, length: Int)]
    let subnodeAddresses: [Int]
}

private struct HitomiGGData {
    let numbers: Set<String>
    let b: String
    let initialG: Int
}

enum ComicContentError: LocalizedError {
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

private extension Dictionary where Key == String, Value == Any {
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

private extension Dictionary {
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

private extension String {
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

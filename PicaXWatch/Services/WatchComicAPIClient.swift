import CryptoKit
import Foundation

struct WatchComicAPIClient {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func loadExplore(platform: WatchComicPlatform, kind: WatchDiscoveryKind, account: WatchPlatformAccount?, page: Int = 1) async throws -> [WatchComicItem] {
        switch platform {
        case .picacg:
            return try await loadPicacgExplore(kind: kind, account: account, page: page)
        case .nhentai:
            return try await loadNhentaiExplore(kind: kind, page: page)
        case .jmComic:
            return try await loadJmComicExplore(kind: kind, page: page)
        case .eHentai, .hitomi, .htManga:
            throw WatchComicAPIError.unsupported("\(platform.title) 的 Watch 独立请求解析尚未接入。")
        }
    }

    func loadFavorites(account: WatchPlatformAccount, page: Int = 1) async throws -> [WatchComicItem] {
        guard let platform = WatchComicPlatform(rawValue: account.platformID) else {
            throw WatchComicAPIError.unsupported("未知平台：\(account.platformID)")
        }
        switch platform {
        case .picacg:
            return try await loadPicacgFavorites(account: account, page: page)
        case .nhentai:
            return try await loadNhentaiFavorites(account: account, page: page)
        case .jmComic:
            return try await loadJmComicFavorites(account: account, page: page)
        case .eHentai, .hitomi, .htManga:
            throw WatchComicAPIError.unsupported("\(platform.title) 收藏夹的 Watch 独立请求解析尚未接入。")
        }
    }

    func loadCategories(platform: WatchComicPlatform, account: WatchPlatformAccount?) async throws -> [WatchCategoryItem] {
        switch platform {
        case .picacg:
            return try await loadPicacgCategories(account: account)
        case .nhentai:
            return Self.nhentaiCategories
        case .jmComic:
            return Self.jmComicCategories
        case .hitomi:
            return Self.hitomiCategories
        case .htManga:
            return Self.htMangaCategories
        case .eHentai:
            return Self.ehentaiCategories
        }
    }

    func loadCategoryComics(_ category: WatchCategoryItem, account: WatchPlatformAccount?, page: Int = 1) async throws -> [WatchComicItem] {
        switch category.platform {
        case .picacg:
            return try await loadPicacgCategoryComics(category: category.query, account: account, page: page)
        case .nhentai:
            return try await searchNhentai(query: category.query, page: page)
        case .jmComic:
            return try await searchJmComic(query: category.query, page: page)
        case .eHentai, .hitomi, .htManga:
            throw WatchComicAPIError.unsupported("\(category.platform.title) 标签列表的 Watch 独立请求解析尚未接入。")
        }
    }

    func loadDetail(item: WatchComicItem, account: WatchPlatformAccount?) async throws -> WatchComicDetailInfo {
        switch item.platform {
        case .picacg:
            return try await loadPicacgDetail(item: item, account: account)
        case .nhentai:
            return try await loadNhentaiDetail(item: item)
        case .jmComic:
            return try await loadJmComicDetail(item: item)
        case .eHentai:
            return try await loadEhentaiDetail(item: item)
        case .hitomi:
            return try await loadHitomiDetail(item: item)
        case .htManga:
            return try await loadHtMangaDetail(item: item)
        }
    }
}

private extension WatchComicAPIClient {
    func loadPicacgExplore(kind: WatchDiscoveryKind, account: WatchPlatformAccount?, page: Int) async throws -> [WatchComicItem] {
        let token = try await picacgToken(account: account)
        switch kind {
        case .random:
            let json = try await picacgJSON(path: "comics/random", token: token)
            return try picacgItems(from: json, path: ["data", "comics"])
        case .latest:
            let json = try await picacgJSON(path: "comics?page=\(page)&s=dd", token: token)
            return try picacgItems(from: json, path: ["data", "comics", "docs"])
        case .ranking:
            guard page == 1 else { return [] }
            let json = try await picacgJSON(path: "comics/leaderboard?tt=H24&ct=VC", token: token)
            return try picacgItems(from: json, path: ["data", "comics"])
        }
    }

    func loadPicacgFavorites(account: WatchPlatformAccount, page: Int) async throws -> [WatchComicItem] {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "users/favourite?s=da&page=\(max(page, 1))", token: token)
        return try picacgItems(from: json, path: ["data", "comics", "docs"], favoriteDate: Date())
    }

    func loadPicacgCategories(account: WatchPlatformAccount?) async throws -> [WatchCategoryItem] {
        let token = try await picacgToken(account: account)
        let json = try await picacgJSON(path: "categories", token: token)
        guard let categories = json.value(at: ["data", "categories"]) as? [[String: Any]] else {
            throw WatchComicAPIError.invalidResponse("PicACG 分类响应缺少 categories。")
        }
        return categories.compactMap { category in
            guard category["isWeb"] as? Bool != true,
                  let title = category["title"] as? String,
                  !title.isEmpty else {
                return nil
            }
            return WatchCategoryItem(
                title: title,
                query: "category:\(title)",
                platform: .picacg,
                subtitle: "PicACG 分类",
                groupTitle: nil
            )
        }
    }

    func loadPicacgCategoryComics(category: String, account: WatchPlatformAccount?, page: Int) async throws -> [WatchComicItem] {
        let token = try await picacgToken(account: account)
        let value = category.hasPrefix("category:") ? String(category.dropFirst("category:".count)) : category
        let encoded = value.urlEncoded
        let json = try await picacgJSON(path: "comics?page=\(page)&c=\(encoded)&s=dd", token: token)
        return try picacgItems(from: json, path: ["data", "comics", "docs"])
    }

    func picacgToken(account: WatchPlatformAccount?) async throws -> String {
        guard let account else {
            throw WatchComicAPIError.loginRequired("PicACG 需要先在 iPhone 登录平台账号并同步。")
        }
        if let password = account.credential.password?.nonEmptyValue {
            return try await picacgLoginToken(email: account.username, password: password)
        }
        if let token = account.credential.token?.nonEmptyValue {
            return token
        }
        throw WatchComicAPIError.loginRequired("PicACG 登录状态无效，请在 iPhone 重新登录后同步。")
    }

    func picacgLoginToken(email: String, password: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let json = try await picacgJSON(path: "auth/sign-in", method: "POST", token: "", body: body)
        guard let token = json.value(at: ["data", "token"]) as? String, !token.isEmpty else {
            throw WatchComicAPIError.invalidResponse("PicACG 登录返回信息不完整。")
        }
        return token
    }

    func picacgJSON(path: String, method: String = "GET", token: String, body: Data? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "https://picaapi.picacomic.com/\(path)") else {
            throw WatchComicAPIError.invalidURL(path)
        }
        return try await requestJSON(url: url, method: method, headers: picacgHeaders(path: path, method: method, token: token), body: body)
    }

    func picacgHeaders(path: String, method: String, token: String) -> [String: String] {
        let apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let time = "\(Int(Date().timeIntervalSince1970))"
        let signatureInput = (path + time + nonce + method.uppercased() + apiKey).lowercased()
        let secret = #"~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"#
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signatureInput.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        return [
            "api-key": apiKey,
            "accept": "application/vnd.picacomic.com.v1+json",
            "app-channel": "3",
            "authorization": token,
            "time": time,
            "nonce": nonce,
            "app-version": "2.2.1.3.3.4",
            "app-uuid": "defaultUuid",
            "image-quality": "middle",
            "app-platform": "android",
            "app-build-version": "45",
            "Content-Type": "application/json; charset=UTF-8",
            "user-agent": "okhttp/3.8.1",
            "version": "v1.4.1",
            "Host": "picaapi.picacomic.com",
            "signature": signature
        ]
    }

    func picacgItems(from json: [String: Any], path: [String], favoriteDate: Date? = nil) throws -> [WatchComicItem] {
        guard let docs = json.value(at: path) as? [[String: Any]] else {
            throw WatchComicAPIError.invalidResponse("PicACG 响应缺少漫画列表。")
        }
        return docs.compactMap { doc in
            guard let id = doc["_id"] as? String else { return nil }
            let thumb = doc["thumb"] as? [String: Any]
            let fileServer = thumb?["fileServer"] as? String ?? ""
            let path = thumb?["path"] as? String ?? ""
            var tags = [String]()
            tags.append(contentsOf: doc["tags"] as? [String] ?? [])
            tags.append(contentsOf: doc["categories"] as? [String] ?? [])
            return WatchComicItem(
                id: "picacg-\(id)",
                platform: .picacg,
                title: doc["title"] as? String ?? "Unknown",
                subtitle: doc["author"] as? String ?? "Unknown",
                coverURLString: picacgImageURL(fileServer: fileServer, path: path),
                tags: tags,
                pageCount: doc.intValue(for: "pagesCount"),
                favoriteDate: favoriteDate
            )
        }
    }

    func picacgImageURL(fileServer: String, path: String) -> String? {
        var server = fileServer.trimmingCharacters(in: .whitespacesAndNewlines)
        var imagePath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !imagePath.isEmpty else { return nil }
        while server.hasSuffix("/") { server.removeLast() }
        if server.hasSuffix("/static") {
            server.removeLast("/static".count)
        }
        while imagePath.hasPrefix("/") { imagePath.removeFirst() }
        return "\(server)/static/\(imagePath)"
    }
}

private extension WatchComicAPIClient {
    func loadNhentaiExplore(kind: WatchDiscoveryKind, page: Int) async throws -> [WatchComicItem] {
        let sort: String
        switch kind {
        case .latest:
            sort = "date"
        case .ranking:
            sort = "popular-today"
        case .random:
            throw WatchComicAPIError.unsupported("NHentai 没有稳定的随机列表接口。")
        }
        return try await searchNhentai(query: " ", page: page, sort: sort)
    }

    func searchNhentai(query: String, page: Int, sort: String = "date") async throws -> [WatchComicItem] {
        let encoded = query.urlEncoded
        guard let url = URL(string: "https://nhentai.net/api/v2/search?query=\(encoded)&page=\(page)&sort=\(sort)") else {
            throw WatchComicAPIError.invalidURL("nhentai search")
        }
        let json = try await requestJSON(url: url, headers: webHeaders(referer: "https://nhentai.net/"))
        return try nhentaiItems(from: json)
    }

    func loadNhentaiFavorites(account: WatchPlatformAccount, page: Int) async throws -> [WatchComicItem] {
        let headers = try nhentaiAuthHeaders(account: account)
        guard let url = URL(string: "https://nhentai.net/api/v2/favorites?page=\(max(page, 1))") else {
            throw WatchComicAPIError.invalidURL("nhentai favorites")
        }
        let json = try await requestJSON(url: url, headers: headers)
        return try nhentaiItems(from: json, favoriteDate: Date())
    }

    func nhentaiAuthHeaders(account: WatchPlatformAccount) throws -> [String: String] {
        let token = account.credential.token?.nonEmptyValue ??
            account.credential.cookies.first { $0.name == "access_token" }?.value.nonEmptyValue
        guard let token else {
            throw WatchComicAPIError.loginRequired("NHentai 登录状态无效，请在 iPhone 重新登录后同步。")
        }
        return webHeaders(referer: "https://nhentai.net/", userAgent: account.credential.userAgent)
            .merging(["Authorization": "User \(token)"]) { _, new in new }
    }

    func nhentaiItems(from json: [String: Any], favoriteDate: Date? = nil) throws -> [WatchComicItem] {
        guard let result = json["result"] as? [[String: Any]] else {
            throw WatchComicAPIError.invalidResponse("NHentai 响应缺少 result。")
        }
        return result.map { doc in
            let rawID = "\(doc.intValue(for: "id") ?? 0)"
            let thumbnail = doc["thumbnail"] as? String ?? ""
            return WatchComicItem(
                id: "nhentai-\(rawID)",
                platform: .nhentai,
                title: doc["english_title"] as? String ?? doc["japanese_title"] as? String ?? rawID,
                subtitle: rawID,
                coverURLString: absoluteNhentaiThumbnail(thumbnail),
                tags: (doc["tag_ids"] as? [Int] ?? []).prefix(4).map { "tag:\($0)" },
                pageCount: doc.intValue(for: "num_pages"),
                favoriteDate: favoriteDate
            )
        }
    }

    func absoluteNhentaiThumbnail(_ value: String) -> String {
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("/") { return "https://t.nhentai.net\(value)" }
        return "https://t.nhentai.net/\(value)"
    }
}

private extension WatchComicAPIClient {
    func loadJmComicExplore(kind: WatchDiscoveryKind, page: Int) async throws -> [WatchComicItem] {
        switch kind {
        case .latest:
            return try await jmComicItems(from: jmJSON(path: "latest?page=\(max(page, 1))"))
        case .ranking:
            return try await jmComicItems(from: jmJSON(path: "categories/filter?o=mv&c=0&page=\(max(page, 1))"))
        case .random:
            var items = try await jmComicItems(from: jmJSON(path: "latest?page=\(max(page, 1))"))
            items.shuffle()
            return items
        }
    }

    func loadJmComicFavorites(account: WatchPlatformAccount, page: Int) async throws -> [WatchComicItem] {
        let context = try await jmAuthenticatedContext(account: account)
        let sort = jmFavoriteSort()
        let json = try await jmJSON(
            path: "favorite?page=\(max(page, 1))&folder_id=0&o=\(sort)",
            cookies: context.cookies,
            baseURL: context.baseURL
        )
        return try jmComicItems(from: json, favoriteDate: Date())
    }

    func searchJmComic(query: String, page: Int, sort: String = "mr") async throws -> [WatchComicItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await jmComicItems(from: jmJSON(path: "latest?page=\(max(page, 1))"))
        }
        let encoded = trimmed.urlEncoded.replacingOccurrences(of: "%20", with: "+")
        let json = try await jmJSON(path: "search?&search_query=\(encoded)&o=\(sort)&page=\(max(page, 1))")
        return try jmComicItems(from: json)
    }

    func jmAuthenticatedContext(account: WatchPlatformAccount) async throws -> (cookies: HTTPCookieStorage, baseURL: String) {
        if !account.credential.cookies.isEmpty {
            let cookies = HTTPCookieStorage()
            for cookie in account.credential.cookies.compactMap(\.httpCookie) {
                cookies.setCookie(cookie)
            }
            return (cookies, account.credential.baseURL?.nonEmptyValue ?? jmBaseURLs.first ?? "https://18comic.vip")
        }

        guard let password = account.credential.password?.nonEmptyValue else {
            throw WatchComicAPIError.loginRequired("JMComic 登录信息已失效，请在 iPhone 重新登录后同步。")
        }

        let cookies = HTTPCookieStorage()
        let baseURL = try await jmLogin(username: account.username, password: password, cookies: cookies)
        return (cookies, baseURL)
    }

    func jmLogin(username: String, password: String, cookies: HTTPCookieStorage) async throws -> String {
        let body = "username=\(username.urlEncoded)&password=\(password.urlEncoded)"
        var lastError: Error?
        for baseURL in jmBaseURLs {
            do {
                guard let json = try await jmJSON(path: "login", method: "POST", body: body, cookies: cookies, baseURL: baseURL) as? [String: Any],
                      let username = jmString(json["username"]),
                      !username.isEmpty else {
                    throw WatchComicAPIError.invalidResponse("JMComic 登录响应缺少用户信息。")
                }
                return baseURL
            } catch {
                lastError = error
            }
        }
        throw lastError ?? WatchComicAPIError.loginRequired("JMComic 登录失败。")
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
        throw lastError ?? WatchComicAPIError.server("JMComic 请求失败。")
    }

    func jmJSON(path: String, method: String, body: String?, cookies: HTTPCookieStorage?, baseURL: String) async throws -> Any {
        let time = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw WatchComicAPIError.invalidURL("JMComic \(path)")
        }

        var headers = jmHeaders(time: time, post: method.uppercased() == "POST")
        if let cookies {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies.cookies(for: url) ?? [])
            headers.merge(cookieHeader) { _, new in new }
        }

        let data = try await requestData(
            url: url,
            method: method,
            headers: headers,
            body: body.map { Data($0.utf8) }
        )

        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WatchComicAPIError.invalidResponse("JMComic 响应不是 JSON 对象。")
        }
        guard let encrypted = envelope["data"] as? String, !encrypted.isEmpty else {
            if let dataList = envelope["data"] as? [Any], dataList.isEmpty {
                throw WatchComicAPIError.invalidResponse("JMComic 返回空数据。")
            }
            throw WatchComicAPIError.invalidResponse("JMComic 响应缺少 data。")
        }

        let decoded = try jmDecrypt(encrypted, time: time)
        guard let decodedData = decoded.data(using: .utf8) else {
            throw WatchComicAPIError.invalidResponse("JMComic 解密结果无法转为 UTF-8。")
        }
        return try JSONSerialization.jsonObject(with: decodedData)
    }

    func jmDecrypt(_ input: String, time: Int) throws -> String {
        guard let encrypted = Data(base64Encoded: input) else {
            throw WatchComicAPIError.invalidResponse("JMComic data 不是有效 Base64。")
        }
        let key = Insecure.MD5.hash(data: Data("\(time)\(jmSecret)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let service = try WatchAESECBService(key: Data(key.utf8), usesPKCS7Padding: false)
        let decrypted = try service.decrypt(encrypted)
        let text = String(decoding: decrypted, as: UTF8.self)
        guard let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else {
            throw WatchComicAPIError.invalidResponse("JMComic 解密结果缺少 JSON 结束符。")
        }
        return String(text[...end])
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

    func jmComicItems(from value: Any, favoriteDate: Date? = nil) throws -> [WatchComicItem] {
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
            throw WatchComicAPIError.invalidResponse("JMComic 列表响应缺少漫画数组。")
        }
        return rows.compactMap { jmComicItem(from: $0, favoriteDate: favoriteDate) }
    }

    func jmComicItem(from comic: [String: Any], favoriteDate: Date?) -> WatchComicItem? {
        guard let id = jmString(comic["id"]), !id.isEmpty else { return nil }
        let tags = [
            jmCategoryName(comic["category"]),
            jmCategoryName(comic["category_sub"])
        ].compactMap { $0 }
        return WatchComicItem(
            id: id,
            platform: .jmComic,
            title: jmString(comic["name"]) ?? id,
            subtitle: jmString(comic["author"]) ?? "Unknown",
            coverURLString: "\(jmImageBaseURL)/media/albums/\(id)_3x4.jpg",
            tags: tags,
            pageCount: nil,
            favoriteDate: favoriteDate
        )
    }

    var jmBaseURLs: [String] {
        let configured = (UserDefaults.standard.string(forKey: WatchJMSettingsKey.customAPIBaseURLs) ?? "")
            .components(separatedBy: .newlines)
            .map { normalizedBaseURL($0, fallback: "") }
            .filter { !$0.isEmpty && URL(string: $0)?.host != nil }
        return uniqueBaseURLs(configured + ["https://www.cdntwice.org", "https://www.cdnsha.org", "https://www.cdnaspa.cc", "https://www.cdnntr.cc"])
    }

    var jmImageBaseURL: String {
        let defaultValue = "https://cdn-msp.jmapiproxy3.cc"
        let endpoint = UserDefaults.standard.string(forKey: WatchJMSettingsKey.imageEndpoint) ?? "mspProxy3"
        let baseURL: String
        switch endpoint {
        case "mspProxy1":
            baseURL = "https://cdn-msp3.jmapiproxy1.cc"
        case "mspProxy2":
            baseURL = "https://cdn-msp2.jmapiproxy2.cc"
        case "mspProxy3Backup":
            baseURL = "https://cdn-msp3.jmapiproxy3.cc"
        case "custom":
            baseURL = UserDefaults.standard.string(forKey: WatchJMSettingsKey.customImageBaseURL) ?? ""
        default:
            baseURL = defaultValue
        }
        return normalizedBaseURL(baseURL, fallback: defaultValue)
    }

    var jmAppVersion: String {
        let value = UserDefaults.standard.string(forKey: WatchJMSettingsKey.appVersion) ?? ""
        return value.nonEmptyValue ?? "2.0.26"
    }

    var jmSecret: String { "185Hcomic3PAPP7R" }
    var jmAuthKey: String { "18comicAPPContent" }

    func jmFavoriteSort() -> String {
        switch UserDefaults.standard.string(forKey: WatchJMSettingsKey.favoriteSort) {
        case "updated":
            "mp"
        default:
            "mr"
        }
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

    func jmCategoryName(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        return jmString(dict["title"]) ?? jmString(dict["name"])
    }

    func normalizedBaseURL(_ value: String, fallback: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = fallback
        }
        if !trimmed.lowercased().hasPrefix("http://"),
           !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    func uniqueBaseURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for value in values {
            let normalized = normalizedBaseURL(value, fallback: "")
            guard URL(string: normalized)?.host != nil, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }
}

private extension WatchStoredHTTPCookie {
    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}

private enum WatchJMSettingsKey {
    static let customAPIBaseURLs = "settings.platformFeature.jm.customAPIBaseURLs"
    static let imageEndpoint = "settings.platformFeature.jm.imageEndpoint"
    static let customImageBaseURL = "settings.platformFeature.jm.customImageBaseURL"
    static let appVersion = "settings.platformFeature.jm.appVersion"
    static let favoriteSort = "settings.platformFeature.jm.favoriteSort"
}

private extension WatchComicAPIClient {
    func loadPicacgDetail(item: WatchComicItem, account: WatchPlatformAccount?) async throws -> WatchComicDetailInfo {
        let token = try await picacgToken(account: account)
        let id = item.id.removingPrefix("picacg-")
        let json = try await picacgJSON(path: "comics/\(id)", token: token)
        guard let doc = json.value(at: ["data", "comic"]) as? [String: Any] else {
            throw WatchComicAPIError.invalidResponse("PicACG 详情响应缺少 comic。")
        }

        let detailItem = try picacgItems(from: ["data": ["comics": [doc]]], path: ["data", "comics"]).first ?? item
        let chapters = try await loadPicacgChapters(comicID: id, token: token)
        let author = (doc["author"] as? String)?.nonEmptyValue
        let chineseTeam = (doc["chineseTeam"] as? String)?.nonEmptyValue
        let categories = doc["categories"] as? [String] ?? []
        let tags = doc["tags"] as? [String] ?? []
        let metadata = [
            metadata("作者", author),
            metadata("汉化", chineseTeam),
            metadata("喜欢", doc.intValue(for: "likesCount").map(String.init)),
            metadata("浏览", doc.intValue(for: "viewsCount").map(String.init)),
            metadata("页数", doc.intValue(for: "pagesCount").map { "\($0)" })
        ].compactMap { $0 }

        return WatchComicDetailInfo(
            item: detailItem,
            description: doc["description"] as? String ?? "",
            metadata: metadata,
            tagGroups: [
                tagGroup("作者", values: author.map { [$0] } ?? [], platform: .picacg),
                tagGroup("汉化", values: chineseTeam.map { [$0] } ?? [], platform: .picacg),
                tagGroup("分类", values: categories, platform: .picacg, prefix: "category:"),
                tagGroup("标签", values: tags, platform: .picacg)
            ].compactMap { $0 },
            chapters: chapters,
            related: try picacgItems(from: ["data": ["comics": json.value(at: ["data", "recommendation"]) as? [[String: Any]] ?? []]], path: ["data", "comics"]),
            updatedText: doc["updated_at"] as? String
        )
    }

    func loadPicacgChapters(comicID: String, token: String) async throws -> [WatchChapterItem] {
        var page = 1
        var result = [WatchChapterItem]()
        while true {
            let json = try await picacgJSON(path: "comics/\(comicID)/eps?page=\(page)", token: token)
            guard let eps = json.value(at: ["data", "eps"]) as? [String: Any],
                  let docs = eps["docs"] as? [[String: Any]] else {
                throw WatchComicAPIError.invalidResponse("PicACG 章节响应缺少 eps。")
            }
            result.append(contentsOf: docs.compactMap { doc in
                guard let title = doc["title"] as? String else { return nil }
                let order = doc.intValue(for: "order")
                return WatchChapterItem(
                    id: doc["_id"] as? String ?? "\(comicID)-\(order ?? result.count)",
                    title: title,
                    subtitle: order.map { "第 \($0) 话" }
                )
            })
            let pages = eps.intValue(for: "pages") ?? page
            if page >= pages { break }
            page += 1
        }
        return result
    }

    func loadNhentaiDetail(item: WatchComicItem) async throws -> WatchComicDetailInfo {
        let id = item.id.removingPrefix("nhentai-")
        guard let url = URL(string: "https://nhentai.net/api/v2/galleries/\(id)") else {
            throw WatchComicAPIError.invalidURL("nhentai detail \(id)")
        }
        let json = try await requestJSON(url: url, headers: webHeaders(referer: "https://nhentai.net/"))
        let title = json.value(at: ["title", "english"]) as? String ??
            json.value(at: ["title", "japanese"]) as? String ??
            item.title
        let subtitle = json.value(at: ["title", "japanese"]) as? String ?? json["scanlator"] as? String ?? item.subtitle
        let coverPath = json.value(at: ["cover", "path"]) as? String ?? json.value(at: ["thumbnail", "path"]) as? String ?? item.coverURLString ?? ""
        let tags = json["tags"] as? [[String: Any]] ?? []
        let grouped = Dictionary(grouping: tags) { tag in tag["type"] as? String ?? "tag" }
        let tagGroups = grouped.keys.sorted().compactMap { key in
            tagGroup(nhentaiTagGroupTitle(key), values: grouped[key]?.compactMap { $0["name"] as? String } ?? [], platform: .nhentai)
        }
        let detailItem = WatchComicItem(
            id: item.id,
            platform: .nhentai,
            title: title,
            subtitle: subtitle,
            coverURLString: absoluteNhentaiThumbnail(coverPath),
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: json.intValue(for: "num_pages"),
            favoriteDate: item.favoriteDate
        )
        return WatchComicDetailInfo(
            item: detailItem,
            description: subtitle == title ? "" : subtitle,
            metadata: [
                metadata("页数", json.intValue(for: "num_pages").map(String.init)),
                metadata("收藏", json.intValue(for: "num_favorites").map(String.init))
            ].compactMap { $0 },
            tagGroups: tagGroups,
            chapters: [WatchChapterItem(id: item.id, title: "开始阅读", subtitle: detailItem.pageCount.map { "\($0) 页" })],
            related: [],
            updatedText: json.intValue(for: "upload_date").map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .abbreviated, time: .omitted) }
        )
    }

    func loadJmComicDetail(item: WatchComicItem) async throws -> WatchComicDetailInfo {
        let id = item.id.removingPrefix("jm")
        guard let json = try await jmJSON(path: "album?id=\(id)") as? [String: Any] else {
            throw WatchComicAPIError.invalidResponse("JMComic 详情响应不是对象。")
        }

        let authors = jmStringArray(json["author"])
        let tags = jmStringArray(json["tags"])
        let works = jmStringArray(json["works"])
        let actors = jmStringArray(json["actors"])
        let series = json["series"] as? [[String: Any]] ?? []
        let likes = jmInt(json["likes"])
        let views = jmInt(json["total_views"])
        let comments = jmInt(json["comment_total"])
        let tagGroups = [
            tagGroup("作者", values: authors, platform: .jmComic),
            tagGroup("标签", values: tags, platform: .jmComic),
            tagGroup("作品", values: works, platform: .jmComic),
            tagGroup("角色", values: actors, platform: .jmComic)
        ].compactMap { $0 }
        let detailItem = WatchComicItem(
            id: id,
            platform: .jmComic,
            title: jmString(json["name"]) ?? item.title,
            subtitle: authors.first ?? item.subtitle,
            coverURLString: "\(jmImageBaseURL)/media/albums/\(id)_3x4.jpg",
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: item.pageCount,
            favoriteDate: item.favoriteDate
        )

        return WatchComicDetailInfo(
            item: detailItem,
            description: jmString(json["description"]) ?? "",
            metadata: [
                metadata("阅读", views.map(String.init)),
                metadata("喜欢", likes.map(String.init)),
                metadata("评论", comments.map(String.init))
            ].compactMap { $0 },
            tagGroups: tagGroups,
            chapters: jmChapters(series: series, fallbackID: id),
            related: (try? jmComicItems(from: json["related_list"] as? [[String: Any]] ?? [])) ?? [],
            updatedText: nil
        )
    }

    func loadEhentaiDetail(item: WatchComicItem) async throws -> WatchComicDetailInfo {
        guard let url = URL(string: item.id) else {
            throw WatchComicAPIError.invalidURL(item.id)
        }
        let baseURL = "https://e-hentai.org"
        let html = try await requestString(url: url, headers: webHeaders(referer: baseURL))
        if html.contains("Content Warning"), html.contains("Never Warn Me Again") {
            throw WatchComicAPIError.server("E-Hentai 返回 Content Warning，需要网页登录确认。")
        }

        let title = html.firstRegexCapture(#"<h1 id="gn"[^>]*>(.*?)</h1>"#)?.htmlDecoded ?? item.title
        let subtitle = html.firstRegexCapture(#"<h1 id="gj"[^>]*>(.*?)</h1>"#)?.htmlDecoded
        let cover = html.firstRegexCapture(#"<div id="gd1"[^>]*>.*?url\((https?://[^)]+)\)"#) ?? item.coverURLString
        let uploader = html.firstRegexCapture(#"<div id="gdn"[^>]*>.*?<a[^>]*>(.*?)</a>"#)?.htmlDecoded ?? item.subtitle
        let pages = html.firstRegexCapture(#"<td class="gdt2">([0-9,]+)\s+pages</td>"#)
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .flatMap(Int.init)
        let time = html.firstRegexCapture(#"<td class="gdt2">([0-9]{4}-[0-9]{2}-[0-9]{2}[^<]*)</td>"#)?.htmlDecoded
        let tagGroups = parseEhentaiTagGroups(html, platform: .eHentai)
        let detailItem = WatchComicItem(
            id: item.id,
            platform: .eHentai,
            title: title,
            subtitle: uploader,
            coverURLString: cover,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: pages ?? item.pageCount,
            favoriteDate: item.favoriteDate
        )
        return WatchComicDetailInfo(
            item: detailItem,
            description: subtitle ?? "",
            metadata: [metadata("页数", detailItem.pageCount.map(String.init))].compactMap { $0 },
            tagGroups: tagGroups,
            chapters: [WatchChapterItem(id: item.id, title: "开始阅读", subtitle: detailItem.pageCount.map { "\($0) 页" })],
            related: [],
            updatedText: time
        )
    }

    func loadHtMangaDetail(item: WatchComicItem) async throws -> WatchComicDetailInfo {
        let base = "https://www.wnacg.com"
        let id = firstNumber(in: item.id) ?? item.id
        guard let url = URL(string: "\(base)/photos-index-page-1-aid-\(id).html") else {
            throw WatchComicAPIError.invalidURL("htmanga detail \(item.id)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        let title = html.firstRegexCapture(#"<div class="userwrap"[^>]*>.*?<h2[^>]*>(.*?)</h2>"#)?.htmlDecoded ?? item.title
        let cover = html.firstRegexCapture(#"<div class="asTBcell uwthumb"[^>]*>.*?<img[^>]+src="([^"]+)""#).map { absoluteURL($0, baseURL: base) } ?? item.coverURLString
        let labels = html.regexMatches(#"<label[^>]*>.*?</label>"#, options: [.dotMatchesLineSeparators]).map(\.htmlDecoded)
        let category = labels.first { $0.contains("分類") || $0.contains("分类") }?.components(separatedBy: "：").last?.nonEmptyValue
        let pages = labels.first { $0.contains("頁數") || $0.contains("页数") }?.firstRegexCapture(#"([0-9]+)"#).flatMap(Int.init)
        let description = html.firstRegexCapture(#"<div class="asTBcell uwconn"[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? ""
        let uploader = html.firstRegexCapture(#"<div class="asTBcell uwuinfo"[^>]*>.*?<a[^>]*>\s*<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? item.subtitle
        let tags = html.regexMatches(#"<a class="tagshow"[^>]*href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators]).map(\.strippingHTML).filter { !$0.isEmpty }
        let tagGroups = [
            tagGroup("分类", values: category.map { [$0] } ?? [], platform: .htManga),
            tagGroup("标签", values: tags, platform: .htManga)
        ].compactMap { $0 }
        let detailItem = WatchComicItem(
            id: id,
            platform: .htManga,
            title: title,
            subtitle: uploader,
            coverURLString: cover,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: pages ?? item.pageCount,
            favoriteDate: item.favoriteDate
        )
        return WatchComicDetailInfo(
            item: detailItem,
            description: description,
            metadata: [metadata("页数", detailItem.pageCount.map(String.init))].compactMap { $0 },
            tagGroups: tagGroups,
            chapters: [WatchChapterItem(id: id, title: "开始阅读", subtitle: detailItem.pageCount.map { "\($0) 页" })],
            related: [],
            updatedText: nil
        )
    }

    func loadHitomiDetail(item: WatchComicItem) async throws -> WatchComicDetailInfo {
        let id = try hitomiID(from: item.id)
        let jsURL = try hitomiURL(path: "galleries/\(id).js")
        let script = try await requestString(url: jsURL, headers: hitomiHeaders(referer: hitomiPublicBaseURL))
        guard let start = script.firstIndex(of: "{"), let end = script.lastIndex(of: "}") else {
            throw WatchComicAPIError.invalidResponse("Hitomi galleries.js 缺少 JSON 数据。")
        }
        let jsonData = Data(script[start...end].utf8)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw WatchComicAPIError.invalidResponse("Hitomi 详情 JSON 无法解析。")
        }

        let files = json["files"] as? [[String: Any]] ?? []
        let artists = hitomiNamedTags(json["artists"], key: "artist", namespace: "artist")
        let groups = hitomiNamedTags(json["groups"], key: "group", namespace: "group")
        let parodys = hitomiNamedTags(json["parodys"], key: "parody", namespace: "parody")
        let characters = hitomiNamedTags(json["characters"], key: "character", namespace: "character")
        let tags = hitomiGalleryTags(json["tags"])
        let type = (json["type"] as? String)?.nonEmptyValue
        let language = (json["language"] as? String)?.nonEmptyValue
        let tagGroups = ([
            tagGroup("类型", values: type.map { [$0] } ?? [], platform: .hitomi),
            tagGroup("语言", values: language.map { [$0] } ?? [], platform: .hitomi, prefix: "language:")
        ].compactMap { $0 } + [
            WatchTagGroup(title: "作者", tags: artists),
            WatchTagGroup(title: "分组", tags: groups),
            WatchTagGroup(title: "原作", tags: parodys),
            WatchTagGroup(title: "角色", tags: characters),
            WatchTagGroup(title: "标签", tags: tags)
        ]).filter { !$0.tags.isEmpty }
        let detailItem = WatchComicItem(
            id: item.id,
            platform: .hitomi,
            title: json["title"] as? String ?? item.title,
            subtitle: artists.first?.title ?? item.subtitle,
            coverURLString: item.coverURLString,
            tags: tagGroups.flatMap { $0.tags.map(\.title) },
            pageCount: files.count,
            favoriteDate: item.favoriteDate
        )
        return WatchComicDetailInfo(
            item: detailItem,
            description: "",
            metadata: [metadata("页数", files.isEmpty ? nil : "\(files.count)")].compactMap { $0 },
            tagGroups: tagGroups,
            chapters: [WatchChapterItem(id: id, title: "开始阅读", subtitle: files.isEmpty ? nil : "\(files.count) 页")],
            related: [],
            updatedText: json["date"] as? String
        )
    }

    func nhentaiTagGroupTitle(_ key: String) -> String {
        switch key {
        case "tag": "标签"
        case "artist": "作者"
        case "group": "社团"
        case "parody": "原作"
        case "character": "角色"
        case "category": "分类"
        case "language": "语言"
        default: key
        }
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

    func jmInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    func jmChapters(series: [[String: Any]], fallbackID: String) -> [WatchChapterItem] {
        guard !series.isEmpty else {
            return [WatchChapterItem(id: fallbackID, title: "第 1 话", subtitle: fallbackID)]
        }
        return series.enumerated().compactMap { index, value in
            guard let id = jmString(value["id"]) else { return nil }
            let order = jmInt(value["sort"]) ?? index + 1
            let title = jmString(value["name"])?.nonEmptyValue ?? "第 \(order) 话"
            return WatchChapterItem(id: id, title: title, subtitle: id)
        }
    }

    func parseEhentaiTagGroups(_ html: String, platform: WatchComicPlatform) -> [WatchTagGroup] {
        html.regexMatches(#"<tr\b[^>]*>.*?</tr>"#, options: [.dotMatchesLineSeparators]).compactMap { row in
            guard row.contains(#"class="tc""#) || row.contains(#"id="td_"#) || row.contains(#"id="ta_""#) else { return nil }
            let namespace = row.firstRegexCapture(#"<td\b[^>]*class="[^"]*\btc\b[^"]*"[^>]*>([^<:]+):?</td>"#)?.htmlDecoded ?? "标签"
            let tags = row.regexMatches(#"<div\b[^>]*class="[^"]*\bgt[lr]?\b[^"]*"[^>]*>.*?</div>"#, options: [.dotMatchesLineSeparators]).compactMap { tagHTML -> WatchTagItem? in
                let displayTitle = tagHTML.strippingHTML
                let titleValue = tagHTML.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded
                let searchValue = tagHTML.firstRegexCapture(#"[?&]f_search=([^"&]+)"#)
                let title = displayTitle.nonEmptyValue ?? titleValue ?? ""
                guard !title.isEmpty else { return nil }
                return WatchTagItem(title: title, query: searchValue?.removingPercentEncoding ?? title, platform: platform)
            }
            return tags.isEmpty ? nil : WatchTagGroup(title: namespace, tags: tags)
        }
    }

    var hitomiPublicBaseURL: String {
        "https://hitomi.la"
    }

    var hitomiDataDomain: String {
        let value = UserDefaults.standard.string(forKey: WatchHitomiSettingsKey.dataDomain) ?? ""
        return normalizedDomain(value, fallback: "gold-usergeneratedcontent.net")
    }

    func hitomiID(from target: String) throws -> String {
        if Int(target) != nil {
            return target
        }
        if let id = target.firstRegexCapture(#"([0-9]+)(?=\.html)"#) ?? target.firstRegexCapture(#"([0-9]+)"#) {
            return id
        }
        throw WatchComicAPIError.invalidURL("Hitomi ID \(target)")
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
            throw WatchComicAPIError.invalidURL("Hitomi \(path)")
        }
        return url
    }

    func hitomiHeaders(referer: String) -> [String: String] {
        webHeaders(referer: referer).merging(["Origin": hitomiPublicBaseURL]) { _, new in new }
    }

    func hitomiNamedTags(_ value: Any?, key: String, namespace: String) -> [WatchTagItem] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let title = row[key] as? String, !title.isEmpty else { return nil }
            return WatchTagItem(title: title, query: "\(namespace):\(title)", platform: .hitomi)
        }
    }

    func hitomiGalleryTags(_ value: Any?) -> [WatchTagItem] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let tag = row["tag"] as? String, !tag.isEmpty else { return nil }
            let namespace = row["female"] as? String == "1" ? "female" : (row["male"] as? String == "1" ? "male" : "tag")
            return WatchTagItem(title: tag, query: "\(namespace):\(tag)", platform: .hitomi)
        }
    }

    func tagGroup(_ title: String, values: [String], platform: WatchComicPlatform, prefix: String = "") -> WatchTagGroup? {
        let tags = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { WatchTagItem(title: $0, query: "\(prefix)\($0)", platform: platform) }
        return tags.isEmpty ? nil : WatchTagGroup(title: title, tags: tags)
    }

    func metadata(_ title: String, _ value: String?) -> WatchDetailMetadata? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return WatchDetailMetadata(title: title, value: value)
    }

    func firstNumber(in value: String) -> String? {
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

    func absoluteURL(_ value: String, baseURL: String) -> String {
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("//") { return "https:\(value)" }
        if value.hasPrefix("/") { return baseURL + value }
        return value.isEmpty ? "" : "\(baseURL)/\(value)"
    }

    func normalizedDomain(_ value: String, fallback: String) -> String {
        let base = normalizedBaseURL(value, fallback: "https://\(fallback)")
        guard let host = URL(string: base)?.host, !host.isEmpty else {
            return fallback
        }
        return host
    }
}

private enum WatchHitomiSettingsKey {
    static let dataDomain = "settings.platformFeature.hitomi.dataDomain"
}

private extension WatchComicAPIClient {
    func requestJSON(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> [String: Any] {
        let data = try await requestData(url: url, method: method, headers: headers, body: body)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw WatchComicAPIError.invalidResponse("接口返回不是 JSON 对象。")
        }
        if let message = json["message"] as? String, message != "success" {
            throw WatchComicAPIError.server(message)
        }
        return json
    }

    func requestData(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WatchComicAPIError.server("HTTP \(httpResponse.statusCode)")
        }
        return data
    }

    func requestString(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> String {
        let data = try await requestData(url: url, method: method, headers: headers, body: body)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw WatchComicAPIError.invalidResponse("响应文本无法解码。")
        }
        return text
    }

    func webHeaders(referer: String, userAgent: String? = nil) -> [String: String] {
        [
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
            "Referer": referer,
            "User-Agent": userAgent?.nonEmptyValue ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ]
    }
}

private extension WatchComicAPIClient {
    static var nhentaiCategories: [WatchCategoryItem] {
        [
            category("中文", .nhentai, query: "language:chinese", group: "语言"),
            category("日本語", .nhentai, query: "language:japanese", group: "语言"),
            category("English", .nhentai, query: "language:english", group: "语言"),
            category("doujinshi", .nhentai, group: "分类"),
            category("manga", .nhentai, group: "分类"),
            category("artist cg", .nhentai, group: "分类"),
            category("game cg", .nhentai, group: "分类")
        ]
    }

    static var jmComicCategories: [WatchCategoryItem] {
        ["最新A漫", "同人", "單本", "短篇", "韓漫", "美漫", "Cosplay", "3D", "全彩", "纯爱", "人妻", "NTR"].map {
            category($0, .jmComic)
        }
    }

    static var hitomiCategories: [WatchCategoryItem] {
        [
            category("中文", .hitomi, query: "language:chinese", group: "语言"),
            category("日本語", .hitomi, query: "language:japanese", group: "语言"),
            category("English", .hitomi, query: "language:english", group: "语言"),
            category("doujinshi", .hitomi, group: "分类"),
            category("manga", .hitomi, group: "分类"),
            category("artistcg", .hitomi, group: "分类"),
            category("gamecg", .hitomi, group: "分类")
        ]
    }

    static var htMangaCategories: [WatchCategoryItem] {
        ["Cosplay", "3D", "同人", "單行本", "短篇", "全彩"].map {
            category($0, .htManga)
        }
    }

    static var ehentaiCategories: [WatchCategoryItem] {
        [
            category("female:big breasts", .eHentai, group: "Female"),
            category("female:sole female", .eHentai, group: "Female"),
            category("male:sole male", .eHentai, group: "Male"),
            category("language:chinese", .eHentai, group: "Language"),
            category("language:japanese", .eHentai, group: "Language")
        ]
    }

    static func category(_ title: String, _ platform: WatchComicPlatform, query: String? = nil, group: String? = nil) -> WatchCategoryItem {
        let value = query ?? title
        return WatchCategoryItem(
            title: title,
            query: value,
            platform: platform,
            subtitle: value == title ? "按 \(title) 浏览" : value,
            groupTitle: group
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(at path: [String]) -> Any? {
        var current: Any? = self
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    func intValue(for key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? String { return Int(value) }
        if let value = self[key] as? Double { return Int(value) }
        return nil
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .strippingHTML
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .htmlDecodedEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var htmlDecodedEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func regexMatches(_ pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: self) else { return nil }
            return String(self[matchRange])
        }
    }

    func firstRegexCapture(_ pattern: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[captureRange])
    }
}

import CryptoKit
import Foundation

extension ComicContentService {
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
        return trimmed.isEmpty ? "2.1.4" : trimmed
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
        case .popular(let period):
            let rankingQuery: String
            switch period {
            case .today:
                // JM's current ranking route separates the popularity sort and time range.
                // The legacy mv_t / mv_w values now return an empty result.
                rankingQuery = "o=mv&t=t"
            case .week:
                rankingQuery = "o=mv&t=w"
            case .month:
                rankingQuery = "o=mv_m"
            case .allTime:
                rankingQuery = "o=mv"
            case .year:
                throw ComicContentError.unsupported("JMComic 没有\(period.title)接口。")
            }
            return try await jmComicItems(from: jmJSON(path: "categories/filter?\(rankingQuery)&c=0&page=\(page)"))
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
            } catch where error.isTaskCancellation {
                throw error
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
            favoriteDate: item.favoriteDate,
            language: item.language
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
            } catch where error.isTaskCancellation {
                throw error
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
            if httpResponse.statusCode == 405 {
                throw ComicContentError.server("JMComic API 地址已失效（HTTP 405），请前往“平台账号 → JMComic → 漫画源设置”更新 API 地址。")
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
        let decodedData = try await Self.decryptJmPayload(
            encrypted,
            time: time,
            secret: jmSecret
        )
        return try JSONSerialization.jsonObject(with: decodedData)
    }

    private nonisolated static func decryptJmPayload(
        _ input: String,
        time: Int,
        secret: String
    ) async throws -> Data {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let encrypted = Data(base64Encoded: input) else {
                throw ComicContentError.invalidResponse("JMComic data 不是有效 Base64。")
            }
            let key = Insecure.MD5.hash(data: Data("\(time)\(secret)".utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let service = try AESECBService(key: Data(key.utf8), usesPKCS7Padding: false)
            let decrypted = try service.decrypt(encrypted)
            try Task.checkCancellation()
            let text = String(decoding: decrypted, as: UTF8.self)
            guard let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else {
                throw ComicContentError.invalidResponse("JMComic 解密结果缺少 JSON 结束符。")
            }
            return Data(text[...end].utf8)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
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
                return try Self.jmAPIBaseURLs(fromDomainPayload: decoded)
            } catch where error.isTaskCancellation {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ComicContentError.server("JMComic API 域名更新失败。")
    }

    static func jmAPIBaseURLs(fromDomainPayload payload: String) throws -> [String] {
        guard let data = payload.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let domains = json["Server"] as? [String] else {
            throw ComicContentError.invalidResponse("JMComic 域名响应缺少 Server。")
        }

        var seen = Set<String>()
        let baseURLs = domains.compactMap { domain -> String? in
            let baseURL = PlatformFeatureSettings.normalizedBaseURL(domain, fallback: "")
            guard URL(string: baseURL)?.host != nil, seen.insert(baseURL).inserted else {
                return nil
            }
            return baseURL
        }
        guard !baseURLs.isEmpty else {
            throw ComicContentError.invalidResponse("JMComic 域名响应没有有效 Server。")
        }
        return baseURLs
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
            } catch where error.isTaskCancellation {
                throw error
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

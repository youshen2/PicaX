import Foundation

extension ComicContentService {
    func loadNhentaiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let sort: String
        switch entry {
        case .latest:
            sort = "date"
        case .popular(let period):
            switch period {
            case .today:
                sort = "popular-today"
            case .week:
                sort = "popular-week"
            case .month:
                sort = "popular-month"
            case .allTime:
                sort = "popular"
            case .year:
                throw ComicContentError.unsupported("NHentai 没有\(period.title)接口。")
            }
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
        try PicaXSQLiteStore.upsertPlatformAccountOrThrow(updatedAccount)
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
                tags: (grouped[key] ?? []).compactMap { tag in
                    guard let name = tag["name"] as? String else { return nil }
                    return NhentaiTagSuggestionService.detailTagReference(forTagName: name, group: key)
                }
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

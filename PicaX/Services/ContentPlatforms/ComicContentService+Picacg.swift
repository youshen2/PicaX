import CryptoKit
import Foundation

extension ComicContentService {
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
        case .popular(let period):
            guard page == 1 else { return [] }
            let leaderboardType: String
            switch period {
            case .today:
                leaderboardType = "H24"
            case .week:
                leaderboardType = "D7"
            case .month:
                leaderboardType = "D30"
            case .year, .allTime:
                throw ComicContentError.unsupported("PicACG 没有\(period.title)接口。")
            }
            let json = try await picacgJSON(path: "comics/leaderboard?tt=\(leaderboardType)&ct=VC", token: token)
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

    func picacgJSON(
        path: String,
        method: String = "GET",
        token: String,
        body: Data? = nil,
        appChannel: String? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://picaapi.picacomic.com/\(path)") else {
            throw ComicContentError.invalidURL(path)
        }
        let headers = picacgHeaders(path: path, method: method, token: token, appChannel: appChannel)
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

    func picacgHeaders(path: String, method: String, token: String, appChannel: String? = nil) -> [String: String] {
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
            "app-channel": appChannel ?? PlatformFeatureSettings.picacgAppChannel(),
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

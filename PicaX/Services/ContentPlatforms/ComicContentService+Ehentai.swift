import Foundation

extension ComicContentService {
    var ehentaiBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .eHentai)
    }

    func loadEhentaiExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let urlString: String
        let pageIndex = max(0, page - 1)
        switch entry {
        case .latest:
            urlString = pageIndex == 0 ? "\(ehentaiBaseURL)/" : "\(ehentaiBaseURL)/?page=\(pageIndex)"
        case .popular(.today):
            urlString = pageIndex == 0 ? "\(ehentaiBaseURL)/popular" : "\(ehentaiBaseURL)/popular?page=\(pageIndex)"
        case .popular, .random, .search:
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
}

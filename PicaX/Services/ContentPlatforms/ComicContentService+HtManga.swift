import Foundation

extension ComicContentService {
    var htMangaBaseURL: String {
        PlatformFeatureSettings.frontendBaseURL(for: .htManga)
    }

    func loadHtMangaExplore(entry: ComicExploreEntry, page: Int) async throws -> [ComicListItem] {
        let base = htMangaBaseURL
        let path: String
        switch entry {
        case .popular(let period):
            switch period {
            case .today:
                path = "/albums-favorite_ranking-type-day.html"
            case .week:
                path = "/albums-favorite_ranking-type-week.html"
            case .month:
                path = "/albums-favorite_ranking-type-month.html"
            case .year, .allTime:
                throw ComicContentError.unsupported("绅士漫画没有\(period.title)接口。")
            }
        case .latest:
            path = "/albums.html"
        case .random, .search:
            throw ComicContentError.unsupported("绅士漫画当前入口不可用。")
        }
        let urlString = htMangaPagedURL(base + path, page: page)
        guard let url = URL(string: urlString) else { throw ComicContentError.invalidURL(urlString) }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        let items = parseHtMangaList(html, baseURL: base)
        guard page > 1 || !items.isEmpty else {
            throw ComicContentError.invalidResponse("绅士漫画列表没有返回可解析的漫画。")
        }
        return items
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
            throw ComicContentError.loginRequired("绅士漫画收藏需要先登录平台账号。")
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
            return PlatformFavoriteFolder(id: id, title: title.isEmpty ? "云端收藏夹" : title, subtitle: "绅士漫画收藏夹", platform: .htManga)
        }
        return folders.isEmpty ? [PlatformFavoriteFolder(id: "0", title: "云端收藏夹", subtitle: "绅士漫画默认收藏", platform: .htManga)] : folders
    }

    func addHtMangaFavorite(item: ComicListItem, folderID: String, account: PlatformAccount?) async throws {
        guard let account else {
            throw ComicContentError.loginRequired("绅士漫画收藏需要先登录平台账号。")
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
            throw ComicContentError.loginRequired("绅士漫画登录失败。")
        }
    }

    func htMangaCookieStorage(account: PlatformAccount) throws -> HTTPCookieStorage {
        guard !account.credential.cookies.isEmpty else {
            throw ComicContentError.loginRequired("绅士漫画登录状态无效，请重新登录。")
        }
        return account.credential.cookieStorage()
    }

    func parseHtMangaList(_ html: String, baseURL: String, favoriteDate: Date? = nil) -> [ComicListItem] {
        let rows = html.regexMatches(#"<li\b[^>]*>.*?</li>"#, options: [.dotMatchesLineSeparators]) +
            html.regexMatches(#"<div\b[^>]*class="[^"]*\basTB\b[^"]*"[^>]*>.*?(?=<div\b[^>]*class="[^"]*\basTB\b[^"]*"|\z)"#, options: [.dotMatchesLineSeparators])
        return rows.compactMap { row in
            guard let link = row.firstRegexCapture(#"href="([^"]*aid-[0-9]+[^"]*)""#),
                  let id = link.firstRegexCapture(#"aid-([0-9]+)"#) else {
                return nil
            }
            let title = row.firstRegexCapture(#"title="([^"]+)""#)?.htmlDecoded ??
                row.firstRegexCapture(#"<p\b[^>]*class="[^"]*\bl_title\b[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ??
                row.firstRegexCapture(#"<div\b[^>]*class="[^"]*\btitle\b[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>"#)?.htmlDecoded ??
                id
            let image = row.firstRegexCapture(#"<img[^>]+src="([^"]+)""#) ?? ""
            let pages = row.firstRegexCapture(#"(?:頁數|页数|页)\s*[：:]?\s*([0-9]+)"#).flatMap(Int.init) ??
                row.firstRegexCapture(#"([0-9]+)\s*(?:張|张)(?:圖片|图片|照片)?"#).flatMap(Int.init)
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


    func loadHtMangaDetail(item: ComicListItem) async throws -> ComicDetailInfo {
        let base = htMangaBaseURL
        guard let url = URL(string: "\(base)/photos-index-page-1-aid-\(item.id).html") else {
            throw ComicContentError.invalidURL("htmanga detail \(item.id)")
        }
        let html = try await requestString(url: url, headers: webHeaders(referer: base))
        let title = html.firstRegexCapture(#"<div\b[^>]*class="[^"]*\buserwrap\b[^"]*"[^>]*>.*?<h2[^>]*>(.*?)</h2>"#)?.htmlDecoded ?? item.title
        let cover = html.firstRegexCapture(#"<div\b[^>]*class="[^"]*\buwthumb\b[^"]*"[^>]*>.*?<img[^>]+src="([^"]+)""#).map { absoluteURL($0, baseURL: base) } ?? item.coverURLString
        let labels = html.regexMatches(#"<label[^>]*>.*?</label>"#, options: [.dotMatchesLineSeparators]).map(\.htmlDecoded)
        let category = labels.first { $0.contains("分類") || $0.contains("分类") }?.components(separatedBy: "：").last ?? ""
        let pages = labels.first { $0.contains("頁數") || $0.contains("页数") }?.firstRegexCapture(#"([0-9]+)"#).flatMap(Int.init)
        let description = html.firstRegexCapture(#"<div\b[^>]*class="[^"]*\buwconn\b[^"]*"[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? ""
        let uploader = html.firstRegexCapture(#"<div\b[^>]*class="[^"]*\buwuinfo\b[^"]*"[^>]*>.*?<a[^>]*>.*?<p[^>]*>(.*?)</p>"#)?.htmlDecoded ?? item.subtitle
        let tags = html.regexMatches(#"<a\b[^>]*class="[^"]*\btagshow\b[^"]*"[^>]*href="([^"]+)"[^>]*>.*?</a>"#, options: [.dotMatchesLineSeparators]).compactMap { row -> ComicTagReference? in
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
            favoriteDate: item.favoriteDate,
            language: item.language
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
        let images = htMangaImageURLs(from: html)
        guard !images.isEmpty else {
            throw ComicContentError.invalidResponse("绅士漫画阅读页没有返回图片。")
        }
        return images
    }

    func htMangaImageURLs(from html: String) -> [String] {
        var seen = Set<String>()
        return html.regexMatches(
            #"//[^"\\\s,}]+?\.(?:jpe?g|png|webp|gif|avif)"#,
            options: [.caseInsensitive]
        )
        .compactMap { match in
            let url = "https://\(match.drop(while: { $0 == "/" }))"
            return seen.insert(url).inserted ? url : nil
        }
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

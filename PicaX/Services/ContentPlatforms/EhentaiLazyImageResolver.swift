import CryptoKit
import Foundation

actor EhentaiLazyImageResolver {
    static let shared = EhentaiLazyImageResolver()
    nonisolated static let scheme = "picax-ehentai-image"

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
                let (data, response) = try await AppProxyNetwork.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                if let statusCode = httpResponse?.statusCode,
                   shouldRetry(statusCode: statusCode),
                   attempt < attempts - 1 {
                    lastError = ComicContentError.server("HTTP \(statusCode)")
                    continue
                }
                return (data, httpResponse)
            } catch where error.isTaskCancellation {
                throw error
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

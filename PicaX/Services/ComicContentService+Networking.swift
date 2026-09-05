import CFNetwork
import Foundation

extension ComicContentService {
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
                let (data, response) = try await networkData(for: request)
                saveCookies(from: response, requestURL: request.url, cookies: cookies)

                if let httpResponse = response as? HTTPURLResponse,
                   shouldRetry(statusCode: httpResponse.statusCode),
                   attempt < attempts - 1 {
                    lastError = ComicContentError.server("HTTP \(httpResponse.statusCode)")
                    continue
                }

                return (data, response)
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
        case .picacg, .local:
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
        if value.hasPrefix("//") {
            let path = value.drop(while: { $0 == "/" })
            return path.isEmpty ? "" : "https://\(path)"
        }
        if value.hasPrefix("/") { return baseURL + value }
        return value.isEmpty ? "" : "\(baseURL)/\(value)"
    }

    func tagRefs(_ values: [String], platform: ComicPlatform, prefix: String = "") -> [ComicTagReference] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { value in
                let displayValue = MarkdownImageTagContent(value).plainText
                return ComicTagReference(
                    title: value,
                    query: "\(prefix)\(displayValue.isEmpty ? value : displayValue)",
                    platform: platform,
                    urlString: nil
                )
            }
    }

    func picacgScopedTagRefs(_ values: [String], prefix: String) -> [ComicTagReference] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { value in
                let displayValue = MarkdownImageTagContent(value).plainText
                return ComicTagReference(
                    title: value,
                    query: "\(prefix)\(displayValue.isEmpty ? value : displayValue)",
                    platform: .picacg,
                    urlString: nil
                )
            }
    }
}

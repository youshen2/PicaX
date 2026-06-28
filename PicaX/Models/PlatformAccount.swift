import Foundation
import SwiftUI

enum ComicPlatform: String, CaseIterable, Codable, Identifiable {
    case picacg
    case jmComic
    case nhentai
    case eHentai
    case hitomi
    case htManga

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .picacg:
            "PicACG"
        case .jmComic:
            "JMComic"
        case .nhentai:
            "NHentai"
        case .eHentai:
            "E-Hentai"
        case .hitomi:
            "Hitomi"
        case .htManga:
            "HT Manga"
        }
    }

    var subtitle: String {
        switch self {
        case .picacg:
            "哔咔漫画账号"
        case .jmComic:
            "禁漫天堂账号"
        case .nhentai:
            "NHentai 网站账号"
        case .eHentai:
            "E-Hentai 网页登录"
        case .hitomi:
            "Hitomi 浏览状态"
        case .htManga:
            "HT Manga 账号"
        }
    }

    var loginHint: String {
        switch self {
        case .eHentai:
            "用户名 / 网页登录信息"
        case .hitomi:
            "用户名 / 浏览状态"
        default:
            "用户名"
        }
    }

    var loginWebsite: String? {
        switch self {
        case .picacg:
            "\(PlatformFeatureSettings.frontendBaseURL(for: .picacg))/web/login"
        case .jmComic:
            nil
        case .nhentai:
            "\(PlatformFeatureSettings.frontendBaseURL(for: .nhentai))/login/?next=/"
        case .eHentai:
            "https://forums.e-hentai.org/index.php?act=Login&CODE=00"
        case .hitomi:
            PlatformFeatureSettings.frontendBaseURL(for: .hitomi)
        case .htManga:
            "\(PlatformFeatureSettings.frontendBaseURL(for: .htManga))/users-login.html"
        }
    }

    var systemImage: String {
        switch self {
        case .picacg:
            "p.circle"
        case .jmComic:
            "j.circle"
        case .nhentai:
            "n.circle"
        case .eHentai:
            "e.circle"
        case .hitomi:
            "h.circle"
        case .htManga:
            "book.circle"
        }
    }

    var accentColor: Color {
        switch self {
        case .picacg:
            .pink
        case .jmComic:
            .orange
        case .nhentai:
            .red
        case .eHentai:
            .purple
        case .hitomi:
            .blue
        case .htManga:
            .teal
        }
    }
}

enum PlatformWebUserAgent {
    static let defaultBrowser = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"

    static func normalized(_ userAgent: String?) -> String {
        let trimmed = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultBrowser : trimmed
    }
}

struct PlatformAccount: Codable, Equatable, Identifiable {
    var platform: ComicPlatform
    var username: String
    var credential: PlatformCredential
    var loggedInAt: Date

    var id: ComicPlatform { platform }

    var displayName: String {
        credential.profile?.displayName ?? (username.isEmpty ? platform.title : username)
    }

    var hasReusableCredential: Bool {
        !credential.isEmpty
    }

    init(platform: ComicPlatform, username: String, credential: PlatformCredential, loggedInAt: Date = Date()) {
        self.platform = platform
        self.username = username
        self.credential = credential
        self.loggedInAt = loggedInAt
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case username
        case credential
        case loggedInAt
        case password
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(ComicPlatform.self, forKey: .platform)
        username = try container.decode(String.self, forKey: .username)
        loggedInAt = try container.decode(Date.self, forKey: .loggedInAt)
        var decodedCredential = try container.decodeIfPresent(PlatformCredential.self, forKey: .credential) ?? .empty
        if platform == .jmComic,
           decodedCredential.password?.isEmpty ?? true,
           let legacyPassword = try container.decodeIfPresent(String.self, forKey: .password),
           !legacyPassword.isEmpty {
            decodedCredential.password = legacyPassword
        }
        credential = decodedCredential
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(username, forKey: .username)
        try container.encode(credential, forKey: .credential)
        try container.encode(loggedInAt, forKey: .loggedInAt)
    }
}

struct PlatformCredential: Codable, Equatable {
    var token: String?
    var refreshToken: String?
    var tokenType: String?
    var password: String?
    var cookies: [StoredHTTPCookie]
    var userAgent: String?
    var baseURL: String?
    var source: PlatformCredentialSource
    var profile: PlatformAccountProfile?

    static let empty = PlatformCredential(
        token: nil,
        refreshToken: nil,
        tokenType: nil,
        password: nil,
        cookies: [],
        userAgent: nil,
        baseURL: nil,
        source: .manual,
        profile: nil
    )

    var isEmpty: Bool {
        (token?.isEmpty ?? true) && (refreshToken?.isEmpty ?? true) && (password?.isEmpty ?? true) && cookies.isEmpty
    }

    var summaryText: String {
        isEmpty ? "未保存" : "已保存"
    }

    func cookieStorage() -> HTTPCookieStorage {
        let storage = HTTPCookieStorage()
        for cookie in cookies.compactMap(\.httpCookie) {
            storage.setCookie(cookie)
        }
        return storage
    }
}

enum PlatformCredentialSource: String, Codable, Equatable {
    case api
    case web
    case manual
}

struct PlatformAccountProfile: Codable, Equatable {
    var email: String?
    var username: String?
    var nickname: String?

    var displayName: String? {
        nickname.nonEmptyValue ?? username.nonEmptyValue ?? email.nonEmptyValue
    }
}

struct StoredHTTPCookie: Codable, Equatable, Identifiable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresDate: Date?
    var isSecure: Bool

    var id: String {
        "\(domain)|\(path)|\(name)"
    }

    nonisolated init(name: String, value: String, domain: String, path: String = "/", expiresDate: Date? = nil, isSecure: Bool = false) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path.isEmpty ? "/" : path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
    }

    nonisolated init(cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure
        )
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: "0"
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

private extension Optional where Wrapped == String {
    var nonEmptyValue: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

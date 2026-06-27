import Foundation
import SwiftUI

enum ComicPlatform: String, CaseIterable, Codable, Identifiable {
    case picacg
    case jmComic
    case nhentai
    case eHentai
    case hitomi
    case htManga

    var id: String { rawValue }

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
            PlatformFeatureSettings.frontendBaseURL(for: .picacg)
        case .jmComic:
            PlatformFeatureSettings.frontendBaseURL(for: .jmComic)
        case .nhentai:
            "\(PlatformFeatureSettings.frontendBaseURL(for: .nhentai))/login/"
        case .eHentai:
            "\(PlatformFeatureSettings.frontendBaseURL(for: .eHentai))/bounce_login.php"
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

struct PlatformAccount: Codable, Equatable, Identifiable {
    var platform: ComicPlatform
    var username: String
    var password: String
    var loggedInAt: Date

    var id: ComicPlatform { platform }

    var displayName: String {
        username.isEmpty ? platform.title : username
    }
}

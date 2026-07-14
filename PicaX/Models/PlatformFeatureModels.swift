import Foundation

struct PicacgUserProfile: Equatable, Codable {
    let id: String
    let email: String
    let name: String
    let title: String
    let level: Int
    let exp: Int
    let slogan: String?
    let avatarURLString: String?
    let frameURLString: String?
    let isPunched: Bool?

    var displayName: String {
        name.isEmpty ? email : name
    }

    var levelText: String {
        "Lv\(level) \(title) Exp\(exp)"
    }

    var avatarURL: URL? {
        URL.picaxResolved(from: avatarURLString)
    }

    var frameURL: URL? {
        URL.picaxResolved(from: frameURLString)
    }
}

struct PicacgUserComment: Identifiable, Equatable {
    let id: String
    let content: String
    let comicID: String
    let comicTitle: String
    let timeText: String?
    let likesCount: Int
    let replyCount: Int
    let isLiked: Bool

    var comicItem: ComicListItem {
        ComicListItem(
            id: comicID,
            platform: .picacg,
            title: comicTitle,
            subtitle: "PicACG",
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }
}

struct PicacgUserCommentsPageData: Equatable {
    let comments: [PicacgUserComment]
    let page: Int
    let pages: Int
}

struct EhentaiProfile: Identifiable, Equatable {
    let id: String
    let title: String

    var displayTitle: String {
        id.isEmpty ? "不修改" : title
    }
}

struct JmAPIUpdateResult: Equatable {
    let baseURLs: [String]
    let appVersion: String?

    var domainsText: String {
        baseURLs
            .compactMap { value in
                if let host = URL(string: value)?.host, !host.isEmpty {
                    return host
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .enumerated()
            .map { "线路 \($0.offset + 1)：\($0.element)" }
            .joined(separator: "\n")
    }
}

struct SourceRouteSpeedTestResult: Identifiable, Equatable, Sendable {
    let id: String
    let endpoint: String
    let milliseconds: Int?
    let errorMessage: String?

    var statusText: String {
        if let milliseconds {
            return "\(milliseconds) ms"
        }
        return errorMessage ?? "失败"
    }
}

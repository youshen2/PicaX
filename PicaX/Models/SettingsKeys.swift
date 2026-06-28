import Foundation
import SwiftUI

enum HomeSettingsKey {
    static let showsHistorySection = "settings.home.showsHistorySection"
    static let showsDownloadSection = "settings.home.showsDownloadSection"
    static let showsAccountManagementEntry = "settings.home.showsAccountManagementEntry"
}

enum AppAppearanceSettingsKey {
    static let colorScheme = "settings.appAppearance.colorScheme"
}

enum AppBehaviorSettingsKey {
    static let checksClipboardForComicLinks = "settings.appBehavior.checksClipboardForComicLinks"
    static let checksClipboardOnlyOnLaunch = "settings.appBehavior.checksClipboardOnlyOnLaunch"
    static let checksUpdatesOnLaunch = "settings.appBehavior.checksUpdatesOnLaunch"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum DownloadSettingsKey {
    static let records = "picax.download.records"
    static let tasks = "picax.download.tasks"
    static let homeLimit = "settings.download.homeLimit"
    static let imageRetryCount = "settings.download.imageRetryCount"
    static let concurrentDownloadCount = "settings.download.concurrentDownloadCount"
    static let speedLimitEnabled = "settings.download.speedLimitEnabled"
    static let speedLimitKBPerSecond = "settings.download.speedLimitKBPerSecond"
    static let downloadsCommentsByDefault = "settings.download.downloadsCommentsByDefault"
}

enum SearchSettingsKey {
    static let focusesSearchFieldOnOpen = "settings.search.focusesSearchFieldOnOpen"
    static let defaultTargetMode = "settings.search.defaultTargetMode"
    static let defaultPlatform = "settings.search.defaultPlatform"
    static let defaultAggregatePlatforms = "settings.search.defaultAggregatePlatforms"
}

enum SearchDefaultTargetMode: String, CaseIterable, Identifiable {
    case platform
    case aggregate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .platform:
            "单平台"
        case .aggregate:
            "多平台聚合"
        }
    }
}

enum ComicListSettingsKey {
    static let showsReadingProgress = "settings.comicList.showsReadingProgress"
    static let showsFavoriteState = "settings.comicList.showsFavoriteState"
    static let showsTags = "settings.comicList.showsTags"
    static let maxVisibleTags = "settings.comicList.maxVisibleTags"
    static let showsPopularity = "settings.comicList.showsPopularity"
}

enum DetailSettingsKey {
    static let usesCoverAccent = "settings.detail.usesCoverAccent"
}

enum ReadFilterSettingsKey {
    nonisolated static let hidesReadComicsInLists = "settings.readFilter.hidesReadComicsInLists"
    nonisolated static let hiddenProgressThreshold = "settings.readFilter.hiddenProgressThreshold"
}

enum SearchHistorySettingsKey {
    nonisolated static let records = "picax.searchHistory.records"
    nonisolated static let isEnabled = "settings.searchHistory.isEnabled"
    nonisolated static let maxRecords = "settings.searchHistory.maxRecords"
}

enum BlockingKeywordSettingsKey {
    nonisolated static let common = "picax.blockingKeywords.common"
    nonisolated static let jmComic = "picax.blockingKeywords.jmComic"
}

enum ImageCacheSettingsKey {
    static let maxDiskSizeMB = "settings.imageCache.maxDiskSizeMB"
}

enum PlatformFeatureSettingsKey {
    static let picacgAppChannel = "settings.platformFeature.picacg.appChannel"
    static let picacgShowsAvatarFrame = "settings.platformFeature.picacg.showsAvatarFrame"
    static let picacgAutoPunchIn = "settings.platformFeature.picacg.autoPunchIn"
    static let picacgFavoriteSort = "settings.platformFeature.picacg.favoriteSort"
    static let picacgDefaultSort = "settings.platformFeature.picacg.defaultSort"
    static let jmAPIEndpoint = "settings.platformFeature.jm.apiEndpoint"
    static let jmCustomAPIBaseURLs = "settings.platformFeature.jm.customAPIBaseURLs"
    static let jmImageEndpoint = "settings.platformFeature.jm.imageEndpoint"
    static let jmCustomImageBaseURL = "settings.platformFeature.jm.customImageBaseURL"
    static let jmAppVersion = "settings.platformFeature.jm.appVersion"
    static let jmAutoSelectAPIEndpoint = "settings.platformFeature.jm.autoSelectAPIEndpoint"
    static let jmAutoCheckIn = "settings.platformFeature.jm.autoCheckIn"
    static let jmFavoriteSort = "settings.platformFeature.jm.favoriteSort"
    static let hitomiDataDomain = "settings.platformFeature.hitomi.dataDomain"
    static let ehentaiPrefersOriginalImage = "settings.platformFeature.ehentai.prefersOriginalImage"
    static let ehentaiIgnoresContentWarning = "settings.platformFeature.ehentai.ignoresContentWarning"
    static let ehentaiPrefersJapaneseTitle = "settings.platformFeature.ehentai.prefersJapaneseTitle"
    static let ehentaiProfile = "settings.platformFeature.ehentai.profile"

    static func frontendBaseURL(_ platform: ComicPlatform) -> String {
        "settings.platformFeature.\(platform.rawValue).frontendBaseURL"
    }
}

enum PlatformFeatureSettings {
    static func picacgAppChannel(defaults: UserDefaults = .standard) -> String {
        let rawValue = defaults.string(forKey: PlatformFeatureSettingsKey.picacgAppChannel) ?? "3"
        return ["1", "2", "3"].contains(rawValue) ? rawValue : "3"
    }

    static func picacgDefaultSort(defaults: UserDefaults = .standard) -> String {
        validPicacgSort(defaults.string(forKey: PlatformFeatureSettingsKey.picacgDefaultSort), fallback: "dd")
    }

    static func picacgFavoriteSort(defaults: UserDefaults = .standard) -> String {
        validPicacgSort(defaults.string(forKey: PlatformFeatureSettingsKey.picacgFavoriteSort), fallback: "da")
    }

    static func validPicacgSort(_ value: String?, fallback: String) -> String {
        guard let value, PicacgSortMode(rawValue: value) != nil else {
            return fallback
        }
        return value
    }

    static func jmFavoriteSort(defaults: UserDefaults = .standard) -> String {
        let rawValue = defaults.string(forKey: PlatformFeatureSettingsKey.jmFavoriteSort) ?? JmFavoriteSort.latest.rawValue
        return JmFavoriteSort(rawValue: rawValue)?.apiValue ?? JmFavoriteSort.latest.apiValue
    }

    static func jmAPIBaseURLs(defaults: UserDefaults = .standard) -> [String] {
        let rawValue = defaults.string(forKey: PlatformFeatureSettingsKey.jmCustomAPIBaseURLs) ?? ""
        let values = rawValue
            .components(separatedBy: .newlines)
            .map { normalizedBaseURL($0, fallback: "") }
            .filter { !$0.isEmpty && URL(string: $0)?.host != nil }
        return values.isEmpty ? JmAPIEndpoint.fallbackBaseURLs : values
    }

    static func frontendBaseURL(for platform: ComicPlatform, defaults: UserDefaults = .standard) -> String {
        let storedValue = defaults.string(forKey: PlatformFeatureSettingsKey.frontendBaseURL(platform)) ?? ""
        return normalizedBaseURL(storedValue, fallback: defaultFrontendBaseURL(for: platform))
    }

    static func defaultFrontendBaseURL(for platform: ComicPlatform) -> String {
        switch platform {
        case .picacg:
            "https://picaapi.picacomic.com"
        case .jmComic:
            "https://18comic.vip"
        case .nhentai:
            "https://nhentai.net"
        case .eHentai:
            "https://e-hentai.org"
        case .hitomi:
            "https://hitomi.la"
        case .htManga:
            "https://www.wnacg.com"
        }
    }

    static func normalizedBaseURL(_ value: String, fallback: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = fallback
        }
        if !trimmed.lowercased().hasPrefix("http://"),
           !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func normalizedDomain(_ value: String, fallback: String) -> String {
        let base = normalizedBaseURL(value, fallback: "https://\(fallback)")
        guard let host = URL(string: base)?.host, !host.isEmpty else {
            return fallback
        }
        return host
    }
}

enum JmAPIEndpoint: String, CaseIterable, Identifiable {
    case auto
    case cdnTwice
    case cdnSha
    case cdnAspa
    case cdnNtr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "自动"
        case .cdnTwice:
            "分流 1"
        case .cdnSha:
            "分流 2"
        case .cdnAspa:
            "分流 3"
        case .cdnNtr:
            "分流 4"
        }
    }

    var baseURLString: String? {
        switch self {
        case .auto:
            nil
        case .cdnTwice:
            "https://www.cdntwice.org"
        case .cdnSha:
            "https://www.cdnsha.org"
        case .cdnAspa:
            "https://www.cdnaspa.cc"
        case .cdnNtr:
            "https://www.cdnntr.cc"
        }
    }

    var dynamicIndex: Int? {
        switch self {
        case .auto:
            nil
        case .cdnTwice:
            0
        case .cdnSha:
            1
        case .cdnAspa:
            2
        case .cdnNtr:
            3
        }
    }

    static var fallbackBaseURLs: [String] {
        allCases.compactMap(\.baseURLString)
    }
}

enum PicacgSortMode: String, CaseIterable, Identifiable {
    case newest = "dd"
    case oldest = "da"
    case mostLiked = "ld"
    case mostViewed = "vd"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            "新到旧"
        case .oldest:
            "旧到新"
        case .mostLiked:
            "最多喜欢"
        case .mostViewed:
            "最多指名"
        }
    }
}

enum PicacgFavoriteSort: String, CaseIterable, Identifiable {
    case oldest = "da"
    case newest = "dd"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oldest:
            "旧到新"
        case .newest:
            "新到旧"
        }
    }
}

enum JmFavoriteSort: String, CaseIterable, Identifiable {
    case latest
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest:
            "最新收藏"
        case .updated:
            "最新更新"
        }
    }

    var apiValue: String {
        switch self {
        case .latest:
            "mr"
        case .updated:
            "mp"
        }
    }
}

enum EhentaiSite: String, CaseIterable, Identifiable {
    case eHentai = "https://e-hentai.org"
    case exhentai = "https://exhentai.org"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eHentai:
            "e-hentai.org"
        case .exhentai:
            "exhentai.org"
        }
    }
}

enum JmImageEndpoint: String, CaseIterable, Identifiable {
    case mspProxy1
    case mspProxy3
    case mspProxy2
    case mspProxy3Backup
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mspProxy1:
            "分流 1"
        case .mspProxy3:
            "分流 2"
        case .mspProxy2:
            "分流 3"
        case .mspProxy3Backup:
            "分流 4"
        case .custom:
            "自定义"
        }
    }

    var baseURLString: String? {
        switch self {
        case .mspProxy1:
            "https://cdn-msp3.jmapiproxy1.cc"
        case .mspProxy3:
            "https://cdn-msp.jmapiproxy3.cc"
        case .mspProxy2:
            "https://cdn-msp2.jmapiproxy2.cc"
        case .mspProxy3Backup:
            "https://cdn-msp3.jmapiproxy3.cc"
        case .custom:
            nil
        }
    }

    static var defaultBaseURL: String {
        JmImageEndpoint.mspProxy3.baseURLString ?? "https://cdn-msp.jmapiproxy3.cc"
    }
}

import SwiftUI

enum WatchSettingsKey {
    nonisolated static let defaultExplorePlatform = "watch.explore.defaultPlatform"
    nonisolated static let showsAllExplorePlatforms = "watch.explore.showsAllPlatforms"
    nonisolated static let defaultSearchTargetMode = "watch.search.defaultTargetMode"
    nonisolated static let defaultSearchPlatform = "watch.search.defaultPlatform"
    nonisolated static let defaultAggregatePlatforms = "watch.search.defaultAggregatePlatforms"
    nonisolated static let savesSearchHistory = "watch.search.history.enabled"
    nonisolated static let maxSearchHistoryRecords = "watch.search.history.maxRecords"
    nonisolated static let searchHistoryRecords = "watch.search.history.records"
    nonisolated static let defaultTagsPlatform = "watch.tags.defaultPlatform"
    nonisolated static let maxVisibleComics = "watch.lists.maxVisibleComics"
    nonisolated static let readerReadingMode = "watch.reader.readingMode"
    nonisolated static let readerImageSpacing = "watch.reader.imageSpacing"
    nonisolated static let readerFirstImageTopPadding = "watch.reader.firstImageTopPadding"
    nonisolated static let readerLastImageBottomPadding = "watch.reader.lastImageBottomPadding"
    nonisolated static let readerPrefetchCount = "watch.reader.prefetchCount"
    nonisolated static let readerRetryCount = "watch.reader.retryCount"
    nonisolated static let readerRetryIntervalSeconds = "watch.reader.retryIntervalSeconds"
    nonisolated static let readerShowsProgress = "watch.reader.showsProgress"
    nonisolated static let readerProgressPosition = "watch.reader.progressPosition"
    nonisolated static let readerProgressEdgeInset = "watch.reader.progressEdgeInset"
    nonisolated static let readerProgressBottomInset = "watch.reader.progressBottomInset"
    nonisolated static let readerUsesProgressGlassBackground = "watch.reader.usesProgressGlassBackground"
    nonisolated static let readerShowsSystemStatus = "watch.reader.showsSystemStatus"
    nonisolated static let readerSystemStatusPosition = "watch.reader.systemStatusPosition"
    nonisolated static let readerSystemStatusEdgeInset = "watch.reader.systemStatusEdgeInset"
    nonisolated static let readerSystemStatusBottomInset = "watch.reader.systemStatusBottomInset"
    nonisolated static let readerUsesSystemStatusGlassBackground = "watch.reader.usesSystemStatusGlassBackground"
    nonisolated static let readerKeepsScreenAwake = "watch.reader.keepsScreenAwake"
    nonisolated static let detailCacheEnabled = "watch.cache.detail.enabled"
    nonisolated static let detailCacheMaxDiskSizeMB = "watch.cache.detail.maxDiskSizeMB"
    nonisolated static let imageCacheEnabled = "watch.cache.image.enabled"
    nonisolated static let imageCacheMaxDiskSizeMB = "watch.cache.image.maxDiskSizeMB"
    nonisolated static let downloadRetryCount = "watch.download.retryCount"
    nonisolated static let downloadReadsImagesFromCache = "watch.download.readsImagesFromCache"
}

enum WatchSearchDefaultTargetMode: String, CaseIterable, Identifiable, Codable {
    case platform
    case aggregate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .platform:
            "单平台"
        case .aggregate:
            "聚合搜索"
        }
    }
}

enum WatchReaderOverlayPosition: String, CaseIterable, Identifiable, Codable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading:
            "左上角"
        case .topTrailing:
            "右上角"
        case .bottomLeading:
            "左下角"
        case .bottomTrailing:
            "右下角"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading:
            .topLeading
        case .topTrailing:
            .topTrailing
        case .bottomLeading:
            .bottomLeading
        case .bottomTrailing:
            .bottomTrailing
        }
    }

    var edgeInsets: EdgeInsets {
        switch self {
        case .topLeading:
            EdgeInsets(top: 10, leading: 8, bottom: 0, trailing: 0)
        case .topTrailing:
            EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 8)
        case .bottomLeading:
            EdgeInsets(top: 0, leading: 8, bottom: 3, trailing: 0)
        case .bottomTrailing:
            EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 8)
        }
    }
}

enum WatchReaderReadingMode: String, CaseIterable, Identifiable, Codable {
    case continuousVertical
    case pagedVertical
    case pagedHorizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuousVertical:
            "纵向连续"
        case .pagedVertical:
            "纵向分页"
        case .pagedHorizontal:
            "横向分页"
        }
    }

    var subtitle: String {
        switch self {
        case .continuousVertical:
            "适合长图和快速滚动"
        case .pagedVertical:
            "每页独立上下滑动"
        case .pagedHorizontal:
            "每页独立左右滑动"
        }
    }
}

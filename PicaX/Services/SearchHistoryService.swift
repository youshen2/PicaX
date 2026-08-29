import Combine
import Foundation

nonisolated struct ComicSearchBreakpoint: Equatable, Codable, Sendable {
    nonisolated struct Request: Equatable, Codable, Sendable {
        let keyword: String
        let platform: ComicPlatform
        let nextPage: Int
    }

    let requests: [Request]

    var isAvailable: Bool {
        !requests.isEmpty
    }
}

struct SearchHistoryRecord: Identifiable, Equatable, Codable {
    let keyword: String
    let target: SearchHistoryTarget
    let advancedOptions: ComicSearchAdvancedOptions
    let searchesKeywordsSeparately: Bool
    var breakpoint: ComicSearchBreakpoint?
    var searchedAt: Date

    private enum CodingKeys: String, CodingKey {
        case keyword
        case target
        case advancedOptions
        case searchesKeywordsSeparately
        case breakpoint
        case searchedAt
    }

    nonisolated init(
        keyword: String,
        target: SearchHistoryTarget,
        advancedOptions: ComicSearchAdvancedOptions = ComicSearchAdvancedOptions(),
        searchesKeywordsSeparately: Bool = false,
        breakpoint: ComicSearchBreakpoint? = nil,
        searchedAt: Date
    ) {
        self.keyword = keyword
        self.target = target
        self.advancedOptions = advancedOptions
        self.searchesKeywordsSeparately = searchesKeywordsSeparately
        self.breakpoint = breakpoint
        self.searchedAt = searchedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyword = try container.decode(String.self, forKey: .keyword)
        target = try container.decode(SearchHistoryTarget.self, forKey: .target)
        advancedOptions = try container.decodeIfPresent(
            ComicSearchAdvancedOptions.self,
            forKey: .advancedOptions
        ) ?? ComicSearchAdvancedOptions()
        searchesKeywordsSeparately = try container.decodeIfPresent(
            Bool.self,
            forKey: .searchesKeywordsSeparately
        ) ?? false
        breakpoint = try container.decodeIfPresent(
            ComicSearchBreakpoint.self,
            forKey: .breakpoint
        )
        searchedAt = try container.decode(Date.self, forKey: .searchedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyword, forKey: .keyword)
        try container.encode(target, forKey: .target)
        try container.encode(advancedOptions, forKey: .advancedOptions)
        try container.encode(searchesKeywordsSeparately, forKey: .searchesKeywordsSeparately)
        try container.encodeIfPresent(breakpoint, forKey: .breakpoint)
        try container.encode(searchedAt, forKey: .searchedAt)
    }

    var id: String {
        "\(target.id)-\(normalizedKeyword)"
    }

    var subtitle: String {
        if breakpoint?.isAvailable == true {
            return "\(target.title) · 可继续"
        }
        return target.title
    }

    var searchedAtText: String {
        Self.relativeFormatter.localizedString(for: searchedAt, relativeTo: Date())
    }

    private var normalizedKeyword: String {
        keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

enum SearchHistoryTarget: Equatable, Hashable, Codable {
    case aggregate([ComicPlatform])
    case platform(ComicPlatform)

    init(_ target: ComicSearchTarget) {
        switch target {
        case .aggregate(let platforms):
            self = .aggregate(Self.normalizedPlatforms(platforms))
        case .platform(let platform):
            self = .platform(platform)
        }
    }

    var id: String {
        switch self {
        case .aggregate(let platforms):
            "aggregate-\(Self.normalizedPlatforms(platforms).map(\.id).joined(separator: "-"))"
        case .platform(let platform):
            "platform-\(platform.id)"
        }
    }

    var title: String {
        switch self {
        case .aggregate(let platforms):
            let normalized = Self.normalizedPlatforms(platforms)
            if normalized.count == ComicPlatform.allCases.count {
                return "多平台聚合"
            }
            return "\(normalized.count) 个平台聚合"
        case .platform(let platform):
            return platform.title
        }
    }

    var systemImage: String {
        switch self {
        case .aggregate:
            "square.grid.2x2"
        case .platform(let platform):
            platform.systemImage
        }
    }

    var searchTarget: ComicSearchTarget {
        switch self {
        case .aggregate(let platforms):
            .aggregate(Self.normalizedPlatforms(platforms))
        case .platform(let platform):
            .platform(platform)
        }
    }

    var aggregatePlatformSet: Set<ComicPlatform>? {
        guard case .aggregate(let platforms) = self else { return nil }
        return Set(Self.normalizedPlatforms(platforms))
    }

    private static func normalizedPlatforms(_ platforms: [ComicPlatform]) -> [ComicPlatform] {
        let selected = Set(platforms)
        let normalized = ComicPlatform.allCases.filter { selected.contains($0) }
        return normalized.isEmpty ? ComicPlatform.allCases : normalized
    }
}

@MainActor
final class SearchHistoryService: ObservableObject {
    @Published private(set) var records: [SearchHistoryRecord] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: SearchHistorySettingsKey.isEnabled) == nil {
            defaults.set(true, forKey: SearchHistorySettingsKey.isEnabled)
        }
        if defaults.object(forKey: SearchHistorySettingsKey.maxRecords) == nil {
            defaults.set(50, forKey: SearchHistorySettingsKey.maxRecords)
        }
        records = PicaXSQLiteStore.loadSearchHistory()
    }

    var isEnabled: Bool {
        defaults.bool(forKey: SearchHistorySettingsKey.isEnabled)
    }

    func record(
        keyword rawKeyword: String,
        target: ComicSearchTarget,
        advancedOptions: ComicSearchAdvancedOptions,
        searchesKeywordsSeparately: Bool,
        breakpoint: ComicSearchBreakpoint? = nil
    ) {
        guard isEnabled else { return }
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        let historyTarget = SearchHistoryTarget(target)
        let normalizedKeyword = normalized(keyword)
        records.removeAll { record in
            record.target == historyTarget && normalized(record.keyword) == normalizedKeyword
        }
        let previousIDs = Set(records.map(\.id))
        let record = SearchHistoryRecord(
            keyword: keyword,
            target: historyTarget,
            advancedOptions: advancedOptions,
            searchesKeywordsSeparately: searchesKeywordsSeparately,
            breakpoint: breakpoint,
            searchedAt: Date()
        )
        records.insert(record, at: 0)
        trimToLimit()
        PicaXSQLiteStore.upsertSearchHistory(record)
        let currentIDs = Set(records.map(\.id))
        for removedID in previousIDs.subtracting(currentIDs) {
            PicaXSQLiteStore.deleteSearchHistory(id: removedID)
        }
    }

    func updateBreakpoint(
        keyword rawKeyword: String,
        target: ComicSearchTarget,
        breakpoint: ComicSearchBreakpoint?
    ) {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyTarget = SearchHistoryTarget(target)
        guard let index = records.firstIndex(where: { record in
            record.target == historyTarget && normalized(record.keyword) == normalized(keyword)
        }) else {
            return
        }

        records[index].breakpoint = breakpoint
        PicaXSQLiteStore.upsertSearchHistory(records[index])
    }

    func remove(_ record: SearchHistoryRecord) {
        records.removeAll { $0.id == record.id }
        PicaXSQLiteStore.deleteSearchHistory(id: record.id)
    }

    func clear() {
        records.removeAll()
        PicaXSQLiteStore.clearSearchHistory()
    }

    func trimToCurrentLimit() {
        trimToLimit()
        PicaXSQLiteStore.replaceSearchHistory(records)
    }

    func reloadFromDefaults() {
        records = PicaXSQLiteStore.loadSearchHistory()
    }

    private func trimToLimit() {
        let maxRecords = max(defaults.integer(forKey: SearchHistorySettingsKey.maxRecords), 1)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

}

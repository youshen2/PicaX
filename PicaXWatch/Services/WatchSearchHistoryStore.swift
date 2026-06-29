import Combine
import Foundation

struct WatchSearchHistoryRecord: Identifiable, Equatable, Codable {
    let id: String
    let keyword: String
    let target: WatchSearchTarget
    let searchedAt: Date

    init(keyword: String, target: WatchSearchTarget, searchedAt: Date = Date()) {
        self.keyword = keyword
        self.target = target
        self.searchedAt = searchedAt
        self.id = "\(Self.normalized(keyword))|\(target.id)"
    }

    static func normalized(_ keyword: String) -> String {
        keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

@MainActor
final class WatchSearchHistoryStore: ObservableObject {
    @Published private(set) var records: [WatchSearchHistoryRecord] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: WatchSettingsKey.savesSearchHistory) == nil {
            defaults.set(true, forKey: WatchSettingsKey.savesSearchHistory)
        }
        if defaults.object(forKey: WatchSettingsKey.maxSearchHistoryRecords) == nil {
            defaults.set(30, forKey: WatchSettingsKey.maxSearchHistoryRecords)
        }
        reload()
    }

    var isEnabled: Bool {
        defaults.bool(forKey: WatchSettingsKey.savesSearchHistory)
    }

    func record(keyword rawKeyword: String, target: WatchSearchTarget) {
        guard isEnabled else { return }
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        let normalized = WatchSearchHistoryRecord.normalized(keyword)
        records.removeAll {
            $0.target == target && WatchSearchHistoryRecord.normalized($0.keyword) == normalized
        }
        records.insert(WatchSearchHistoryRecord(keyword: keyword, target: target), at: 0)
        trim()
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where records.indices.contains(index) {
            records.remove(at: index)
        }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    func trimToSettingsLimit() {
        trim()
        save()
    }

    func reload() {
        guard let data = defaults.data(forKey: WatchSettingsKey.searchHistoryRecords),
              let decoded = try? JSONDecoder().decode([WatchSearchHistoryRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.searchedAt > $1.searchedAt }
        trim()
    }

    private func trim() {
        let maxRecords = max(defaults.integer(forKey: WatchSettingsKey.maxSearchHistoryRecords), 1)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: WatchSettingsKey.searchHistoryRecords)
    }
}

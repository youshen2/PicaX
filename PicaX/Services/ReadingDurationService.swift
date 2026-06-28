import Combine
import Foundation

struct ReadingDurationRecord: Identifiable, Equatable, Codable {
    var item: ComicListItem
    var totalSeconds: TimeInterval
    var dailySeconds: [String: TimeInterval]
    var lastReadAt: Date

    var id: String {
        item.readingHistoryID
    }

    var totalDurationText: String {
        ReadingDurationService.formattedDuration(totalSeconds)
    }

    var lastReadAtText: String {
        Self.relativeFormatter.localizedString(for: lastReadAt, relativeTo: Date())
    }

    func durationText(for dayKey: String) -> String {
        ReadingDurationService.formattedDuration(dailySeconds[dayKey] ?? 0)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

@MainActor
final class ReadingDurationService: ObservableObject {
    enum Key {
        static let records = "picax.readingDuration.records"
        static let isEnabled = "settings.readingDuration.isEnabled"
        static let homeLimit = "settings.readingDuration.homeLimit"
        static let maxRecords = "settings.readingDuration.maxRecords"
    }

    @Published private(set) var records: [ReadingDurationRecord] = [] {
        didSet {
            rebuildSummary()
        }
    }

    private let defaults: UserDefaults
    private var durationSummary = ReadingDurationSummary(todayKey: ReadingDurationService.dayKey(for: Date()), totalSeconds: 0, todaySeconds: 0)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.isEnabled) == nil {
            defaults.set(true, forKey: Key.isEnabled)
        }
        if defaults.object(forKey: Key.homeLimit) == nil {
            defaults.set(6, forKey: Key.homeLimit)
        }
        if defaults.object(forKey: Key.maxRecords) == nil {
            defaults.set(300, forKey: Key.maxRecords)
        }
        records = PicaXSQLiteStore.loadReadingDuration()
        fillMissingCoversFromReadingHistory()
        rebuildSummary()
    }

    var todayKey: String {
        currentSummary.todayKey
    }

    var totalDurationText: String {
        Self.formattedDuration(totalSeconds)
    }

    var todayDurationText: String {
        Self.formattedDuration(todaySeconds)
    }

    var totalSeconds: TimeInterval {
        currentSummary.totalSeconds
    }

    var todaySeconds: TimeInterval {
        currentSummary.todaySeconds
    }

    func latest(limit: Int) -> [ReadingDurationRecord] {
        Array(records.prefix(max(limit, 0)))
    }

    func record(item: ComicListItem, seconds rawSeconds: TimeInterval, at date: Date = Date()) {
        guard defaults.bool(forKey: Key.isEnabled) else { return }
        let seconds = rawSeconds.rounded(.down)
        guard seconds >= 1 else { return }

        let id = item.readingHistoryID
        let previousIDs = Set(records.map(\.id))
        let key = Self.dayKey(for: date)
        if let index = records.firstIndex(where: { $0.id == id }) {
            var record = records[index]
            record.item = Self.itemByRefreshingCover(existing: record.item, incoming: item)
            record.totalSeconds += seconds
            record.dailySeconds[key, default: 0] += seconds
            record.lastReadAt = date
            records.remove(at: index)
            records.insert(record, at: 0)
        } else {
            let record = ReadingDurationRecord(
                item: item,
                totalSeconds: seconds,
                dailySeconds: [key: seconds],
                lastReadAt: date
            )
            records.insert(record, at: 0)
        }
        trimToLimit()
        if let record = records.first(where: { $0.id == id }) {
            PicaXSQLiteStore.upsertReadingDuration(record)
        }
        let currentIDs = Set(records.map(\.id))
        for removedID in previousIDs.subtracting(currentIDs) {
            PicaXSQLiteStore.deleteReadingDuration(id: removedID)
        }
    }

    func remove(_ record: ReadingDurationRecord) {
        records.removeAll { $0.id == record.id }
        PicaXSQLiteStore.deleteReadingDuration(id: record.id)
    }

    func clear() {
        records.removeAll()
        PicaXSQLiteStore.clearReadingDuration()
    }

    func trimToCurrentLimit() {
        trimToLimit()
        PicaXSQLiteStore.replaceReadingDuration(records)
    }

    func reloadFromDefaults() {
        records = PicaXSQLiteStore.loadReadingDuration()
    }

    private func trimToLimit() {
        let maxRecords = max(defaults.integer(forKey: Key.maxRecords), 1)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
    }

    private func fillMissingCoversFromReadingHistory() {
        let historyItemsByID = Dictionary(
            uniqueKeysWithValues: PicaXSQLiteStore.loadReadingHistory().map { ($0.id, $0.item) }
        )
        var didUpdate = false
        records = records.map { record in
            guard Self.needsCoverRefresh(record.item),
                  let historyItem = historyItemsByID[record.id],
                  !Self.needsCoverRefresh(historyItem) else {
                return record
            }
            var updated = record
            updated.item = historyItem
            didUpdate = true
            return updated
        }
        if didUpdate {
            PicaXSQLiteStore.replaceReadingDuration(records)
        }
    }

    private static func itemByRefreshingCover(existing: ComicListItem, incoming: ComicListItem) -> ComicListItem {
        guard existing.readingHistoryID == incoming.readingHistoryID,
              !needsCoverRefresh(incoming) else {
            return existing
        }
        return incoming
    }

    private static func needsCoverRefresh(_ item: ComicListItem) -> Bool {
        item.coverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSummary: ReadingDurationSummary {
        let key = ReadingDurationService.dayKey(for: Date())
        if durationSummary.todayKey != key {
            rebuildSummary(todayKey: key)
        }
        return durationSummary
    }

    private func rebuildSummary(todayKey: String? = nil) {
        let todayKey = todayKey ?? ReadingDurationService.dayKey(for: Date())
        var totalSeconds: TimeInterval = 0
        var todaySeconds: TimeInterval = 0
        for record in records {
            totalSeconds += max(record.totalSeconds, 0)
            todaySeconds += max(record.dailySeconds[todayKey] ?? 0, 0)
        }
        durationSummary = ReadingDurationSummary(todayKey: todayKey, totalSeconds: totalSeconds, todaySeconds: todaySeconds)
    }

    nonisolated static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        if totalSeconds < 60 {
            return "\(totalSeconds) 秒"
        }

        let totalMinutes = totalSeconds / 60
        if totalMinutes < 60 {
            return "\(totalMinutes) 分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct ReadingDurationSummary {
    let todayKey: String
    let totalSeconds: TimeInterval
    let todaySeconds: TimeInterval
}

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

    @Published private(set) var records: [ReadingDurationRecord] = []

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        records = Self.loadRecords(defaults: defaults, decoder: decoder)
    }

    var todayKey: String {
        Self.dayKey(for: Date())
    }

    var totalDurationText: String {
        Self.formattedDuration(totalSeconds)
    }

    var todayDurationText: String {
        Self.formattedDuration(todaySeconds)
    }

    var totalSeconds: TimeInterval {
        records.reduce(0) { $0 + max($1.totalSeconds, 0) }
    }

    var todaySeconds: TimeInterval {
        let key = todayKey
        return records.reduce(0) { $0 + max($1.dailySeconds[key] ?? 0, 0) }
    }

    func latest(limit: Int) -> [ReadingDurationRecord] {
        Array(records.prefix(max(limit, 0)))
    }

    func record(item: ComicListItem, seconds rawSeconds: TimeInterval, at date: Date = Date()) {
        guard defaults.bool(forKey: Key.isEnabled) else { return }
        let seconds = rawSeconds.rounded(.down)
        guard seconds >= 1 else { return }

        let id = item.readingHistoryID
        let key = Self.dayKey(for: date)
        if let index = records.firstIndex(where: { $0.id == id }) {
            var record = records[index]
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
        save()
    }

    func remove(_ record: ReadingDurationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        records.removeAll()
        defaults.removeObject(forKey: Key.records)
    }

    func trimToCurrentLimit() {
        trimToLimit()
        save()
    }

    func reloadFromDefaults() {
        records = Self.loadRecords(defaults: defaults, decoder: decoder)
    }

    private func trimToLimit() {
        let maxRecords = max(defaults.integer(forKey: Key.maxRecords), 1)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
    }

    private func save() {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Key.records)
    }

    private static func loadRecords(defaults: UserDefaults, decoder: JSONDecoder) -> [ReadingDurationRecord] {
        guard let data = defaults.data(forKey: Key.records),
              let records = try? decoder.decode([ReadingDurationRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.lastReadAt > $1.lastReadAt }
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

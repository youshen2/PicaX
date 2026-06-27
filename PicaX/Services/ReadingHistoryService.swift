import Combine
import Foundation

struct ReadingHistoryRecord: Identifiable, Equatable, Codable {
    let item: ComicListItem
    var viewedAt: Date
    var progress: ReadingProgress?

    var id: String {
        item.readingHistoryID
    }

    var viewedAtText: String {
        Self.relativeFormatter.localizedString(for: viewedAt, relativeTo: Date())
    }

    var detailTimeText: String {
        Self.detailFormatter.string(from: viewedAt)
    }

    var progressText: String {
        guard let progress else { return "查看过详情" }
        switch progress.status {
        case .viewed:
            return "查看过详情"
        case .reading:
            return "读到 E\(progress.chapterIndex + 1) · P\(progress.pageIndex + 1)"
        case .finished:
            return "已读完 · \(progress.totalPages) 页"
        }
    }

    var isReadingRecord: Bool {
        guard let progress else { return false }
        return progress.status != .viewed
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ReadingProgress: Equatable, Codable {
    var status: ReadingProgressStatus
    var chapterIndex: Int
    var pageIndex: Int
    var totalPages: Int
    var totalChapters: Int
    var readChapterIndexes: Set<Int>
    var updatedAt: Date
}

enum ReadingProgressStatus: String, Codable {
    case viewed
    case reading
    case finished
}

@MainActor
final class ReadingHistoryService: ObservableObject {
    enum Key {
        static let records = "picax.readingHistory.records"
        static let isEnabled = "settings.history.isEnabled"
        static let homeLimit = "settings.history.homeLimit"
        static let maxRecords = "settings.history.maxRecords"
    }

    @Published private(set) var records: [ReadingHistoryRecord] = []

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.isEnabled) == nil {
            defaults.set(true, forKey: Key.isEnabled)
        }
        if defaults.object(forKey: Key.homeLimit) == nil {
            defaults.set(10, forKey: Key.homeLimit)
        }
        if defaults.object(forKey: Key.maxRecords) == nil {
            defaults.set(200, forKey: Key.maxRecords)
        }
        records = Self.loadRecords(defaults: defaults, decoder: decoder)
    }

    func latest(limit: Int) -> [ReadingHistoryRecord] {
        Array(records.prefix(max(limit, 0)))
    }

    func recordViewed(_ item: ComicListItem) {
        guard defaults.bool(forKey: Key.isEnabled) else { return }

        upsert(item: item) { record in
            record.viewedAt = Date()
            if record.progress == nil {
                record.progress = ReadingProgress(
                    status: .viewed,
                    chapterIndex: 0,
                    pageIndex: 0,
                    totalPages: item.pageCount ?? 0,
                    totalChapters: 0,
                    readChapterIndexes: [],
                    updatedAt: Date()
                )
            }
        }
    }

    func recordReading(item: ComicListItem, chapterIndex: Int, pageIndex: Int, totalPages: Int, totalChapters: Int) {
        guard defaults.bool(forKey: Key.isEnabled) else { return }

        upsert(item: item) { record in
            var readChapters = record.progress?.readChapterIndexes ?? []
            if pageIndex >= max(totalPages - 1, 0) {
                readChapters.insert(chapterIndex)
            }
            let finished = totalChapters > 0 && readChapters.count >= totalChapters && pageIndex >= max(totalPages - 1, 0)
            record.viewedAt = Date()
            record.progress = ReadingProgress(
                status: finished ? .finished : .reading,
                chapterIndex: chapterIndex,
                pageIndex: pageIndex,
                totalPages: totalPages,
                totalChapters: totalChapters,
                readChapterIndexes: readChapters,
                updatedAt: Date()
            )
        }
    }

    func remove(_ record: ReadingHistoryRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clearReadingProgress() {
        records = records.map { record in
            var updated = record
            updated.progress = nil
            return updated
        }
        save()
    }

    private func upsert(item: ComicListItem, update: (inout ReadingHistoryRecord) -> Void) {
        let id = item.readingHistoryID
        if let index = records.firstIndex(where: { $0.id == id }) {
            var record = records[index]
            update(&record)
            if index == 0 {
                records[0] = record
            } else {
                records.remove(at: index)
                records.insert(record, at: 0)
            }
        } else {
            var record = ReadingHistoryRecord(item: item, viewedAt: Date(), progress: nil)
            update(&record)
            records.insert(record, at: 0)
        }
        trimToLimit()
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

    private static func loadRecords(defaults: UserDefaults, decoder: JSONDecoder) -> [ReadingHistoryRecord] {
        guard let data = defaults.data(forKey: Key.records),
              let records = try? decoder.decode([ReadingHistoryRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.viewedAt > $1.viewedAt }
    }
}

import Foundation

struct WatchReadingProgress: Hashable, Codable {
    var chapterIndex: Int
    var pageIndex: Int
    var totalPages: Int
    var totalChapters: Int

    var progressText: String {
        guard totalPages > 0 else { return "第 \(chapterIndex + 1) 章" }
        return "第 \(chapterIndex + 1)/\(max(totalChapters, 1)) 章 · \(pageIndex + 1)/\(totalPages) 页"
    }
}

struct WatchReadingHistoryRecord: Identifiable, Hashable, Codable {
    var item: WatchComicItem
    var viewedAt: Date
    var progress: WatchReadingProgress

    var id: String {
        "\(item.platform.id)-\(item.id)"
    }
}

struct WatchReadingHistoryStore {
    private static let defaultsKey = "picax.watch.readingHistory.records"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [WatchReadingHistoryRecord] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let records = try? JSONDecoder().decode([WatchReadingHistoryRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.viewedAt > $1.viewedAt }
    }

    func latest(limit: Int) -> [WatchReadingHistoryRecord] {
        Array(load().prefix(max(limit, 0)))
    }

    func record(for item: WatchComicItem) -> WatchReadingHistoryRecord? {
        load().first { $0.id == "\(item.platform.id)-\(item.id)" }
    }

    func record(
        item: WatchComicItem,
        chapterIndex: Int,
        pageIndex: Int,
        totalPages: Int,
        totalChapters: Int
    ) {
        var records = load()
        let id = "\(item.platform.id)-\(item.id)"
        records.removeAll { $0.id == id }
        records.insert(
            WatchReadingHistoryRecord(
                item: item,
                viewedAt: Date(),
                progress: WatchReadingProgress(
                    chapterIndex: max(chapterIndex, 0),
                    pageIndex: max(pageIndex, 0),
                    totalPages: max(totalPages, 0),
                    totalChapters: max(totalChapters, 1)
                )
            ),
            at: 0
        )
        records = Array(records.prefix(120))
        save(records)
    }

    func remove(_ record: WatchReadingHistoryRecord) {
        save(load().filter { $0.id != record.id })
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func save(_ records: [WatchReadingHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

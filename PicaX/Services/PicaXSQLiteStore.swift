import Foundation
import SQLite3

nonisolated(unsafe) private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class PicaXSQLiteDatabase: @unchecked Sendable {
    nonisolated static let shared = PicaXSQLiteDatabase()

    private let lock = NSRecursiveLock()
    nonisolated(unsafe) private var db: OpaquePointer?

    private nonisolated init() {
        open()
        createTables()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    nonisolated func execute(_ sql: String, bindings: [SQLiteBinding] = []) {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        sqlite3_step(statement)
    }

    nonisolated func dataRows(_ sql: String, bindings: [SQLiteBinding] = []) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)

        var rows: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let byteCount = Int(sqlite3_column_bytes(statement, 0))
            guard byteCount > 0, let bytes = sqlite3_column_blob(statement, 0) else {
                rows.append(Data())
                continue
            }
            rows.append(Data(bytes: bytes, count: byteCount))
        }
        return rows
    }

    nonisolated func tableBytes(_ table: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(length(value)), 0) FROM \(table)", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    nonisolated func transaction(_ operation: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        execute("BEGIN IMMEDIATE TRANSACTION")
        operation()
        execute("COMMIT")
    }

    private nonisolated func open() {
        let url = Self.databaseURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
    }

    private nonisolated func createTables() {
        execute("""
        CREATE TABLE IF NOT EXISTS reading_history (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_reading_history_sort ON reading_history(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS read_later (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_read_later_sort ON read_later(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS reading_duration (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_reading_duration_sort ON reading_duration(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS search_history (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_search_history_sort ON search_history(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS platform_accounts (
            platform TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)

        execute("""
        CREATE TABLE IF NOT EXISTS local_favorites (
            folder_id TEXT NOT NULL,
            id TEXT NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL,
            PRIMARY KEY(folder_id, id)
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_local_favorites_folder_sort ON local_favorites(folder_id, sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS follow_updates (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_follow_updates_sort ON follow_updates(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS download_records (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_download_records_sort ON download_records(sort_date DESC)")

        execute("""
        CREATE TABLE IF NOT EXISTS nhentai_tag_names (
            id TEXT PRIMARY KEY NOT NULL,
            sort_date REAL NOT NULL,
            value BLOB NOT NULL
        )
        """)
    }

    private nonisolated func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case .double(let value):
                sqlite3_bind_double(statement, position, value)
            case .data(let value):
                _ = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, position, buffer.baseAddress, Int32(value.count), sqliteTransient)
                }
            }
        }
    }

    private nonisolated static func databaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("PicaX.sqlite3")
    }
}

enum SQLiteBinding: Sendable {
    case text(String)
    case double(Double)
    case data(Data)
}

enum PicaXSQLiteStore {
    nonisolated private static let db = PicaXSQLiteDatabase.shared

    static func loadReadingHistory() -> [ReadingHistoryRecord] {
        loadValues("SELECT value FROM reading_history ORDER BY sort_date DESC")
    }

    static func upsertReadingHistory(_ record: ReadingHistoryRecord) {
        upsert(table: "reading_history", id: record.id, sortDate: record.viewedAt, value: record)
    }

    static func replaceReadingHistory(_ records: [ReadingHistoryRecord]) {
        replace(table: "reading_history", values: records) { record in
            (record.id, record.viewedAt)
        }
    }

    static func deleteReadingHistory(id: String) {
        delete(table: "reading_history", id: id)
    }

    static func clearReadingHistory() {
        clear(table: "reading_history")
    }

    static func loadReadLater() -> [ReadLaterRecord] {
        loadValues("SELECT value FROM read_later ORDER BY sort_date DESC")
    }

    static func upsertReadLater(_ record: ReadLaterRecord) {
        upsert(table: "read_later", id: record.id, sortDate: record.addedAt, value: record)
        NotificationCenter.default.post(name: .picaxReadLaterDidChange, object: nil)
    }

    static func replaceReadLater(_ records: [ReadLaterRecord]) {
        replace(table: "read_later", values: records) { record in
            (record.id, record.addedAt)
        }
        NotificationCenter.default.post(name: .picaxReadLaterDidChange, object: nil)
    }

    static func deleteReadLater(id: String) {
        delete(table: "read_later", id: id)
        NotificationCenter.default.post(name: .picaxReadLaterDidChange, object: nil)
    }

    static func clearReadLater() {
        clear(table: "read_later")
        NotificationCenter.default.post(name: .picaxReadLaterDidChange, object: nil)
    }

    static func loadReadingDuration() -> [ReadingDurationRecord] {
        loadValues("SELECT value FROM reading_duration ORDER BY sort_date DESC")
    }

    static func upsertReadingDuration(_ record: ReadingDurationRecord) {
        upsert(table: "reading_duration", id: record.id, sortDate: record.lastReadAt, value: record)
    }

    static func replaceReadingDuration(_ records: [ReadingDurationRecord]) {
        replace(table: "reading_duration", values: records) { record in
            (record.id, record.lastReadAt)
        }
    }

    static func deleteReadingDuration(id: String) {
        delete(table: "reading_duration", id: id)
    }

    static func clearReadingDuration() {
        clear(table: "reading_duration")
    }

    static func loadSearchHistory() -> [SearchHistoryRecord] {
        loadValues("SELECT value FROM search_history ORDER BY sort_date DESC")
    }

    static func upsertSearchHistory(_ record: SearchHistoryRecord) {
        upsert(table: "search_history", id: record.id, sortDate: record.searchedAt, value: record)
    }

    static func replaceSearchHistory(_ records: [SearchHistoryRecord]) {
        replace(table: "search_history", values: records) { record in
            (record.id, record.searchedAt)
        }
    }

    static func deleteSearchHistory(id: String) {
        delete(table: "search_history", id: id)
    }

    static func clearSearchHistory() {
        clear(table: "search_history")
    }

    static func loadPlatformAccounts() -> [ComicPlatform: PlatformAccount] {
        let accounts: [PlatformAccount] = loadValues("SELECT value FROM platform_accounts ORDER BY sort_date DESC")
        return Dictionary(uniqueKeysWithValues: accounts.map { ($0.platform, $0) })
    }

    static func replacePlatformAccounts(_ accounts: [PlatformAccount]) {
        db.transaction {
            clear(table: "platform_accounts")
            for account in accounts {
                guard let data = encoded(account) else { continue }
                db.execute(
                    """
                    INSERT OR REPLACE INTO platform_accounts(platform, sort_date, value)
                    VALUES(?, ?, ?)
                    """,
                    bindings: [.text(account.platform.id), .double(account.loggedInAt.timeIntervalSince1970), .data(data)]
                )
            }
        }
    }

    static func upsertPlatformAccount(_ account: PlatformAccount) {
        guard let data = encoded(account) else { return }
        db.execute(
            """
            INSERT OR REPLACE INTO platform_accounts(platform, sort_date, value)
            VALUES(?, ?, ?)
            """,
            bindings: [.text(account.platform.id), .double(account.loggedInAt.timeIntervalSince1970), .data(data)]
        )
    }

    static func deletePlatformAccount(platform: ComicPlatform) {
        db.execute("DELETE FROM platform_accounts WHERE platform = ?", bindings: [.text(platform.id)])
    }

    nonisolated static func loadLocalFavorites(folderID: String) -> [StoredLocalFavorite] {
        loadValues(
            "SELECT value FROM local_favorites WHERE folder_id = ? ORDER BY sort_date DESC",
            bindings: [.text(folderID)]
        )
    }

    static func replaceLocalFavorites(_ favorites: [StoredLocalFavorite], folderID: String) {
        db.transaction {
            db.execute("DELETE FROM local_favorites WHERE folder_id = ?", bindings: [.text(folderID)])
            for favorite in favorites {
                upsertLocalFavorite(favorite, folderID: folderID)
            }
        }
    }

    static func upsertLocalFavorite(_ favorite: StoredLocalFavorite, folderID: String, notify: Bool = true) {
        guard let data = encoded(favorite) else { return }
        db.execute(
            """
            INSERT OR REPLACE INTO local_favorites(folder_id, id, sort_date, value)
            VALUES(?, ?, ?, ?)
            """,
            bindings: [
                .text(folderID),
                .text("\(favorite.platform.id)-\(favorite.id)"),
                .double((favorite.favoriteDate ?? .distantPast).timeIntervalSince1970),
                .data(data)
            ]
        )
        if notify {
            NotificationCenter.default.post(name: .picaxLocalFavoritesDidChange, object: nil)
        }
    }

    static func loadFollowUpdateRecords() -> [FollowUpdateRecord] {
        loadValues("SELECT value FROM follow_updates ORDER BY sort_date DESC")
    }

    static func replaceFollowUpdateRecords(_ records: [FollowUpdateRecord]) {
        replace(table: "follow_updates", values: records) { record in
            (record.id, record.lastCheckDate ?? .distantPast)
        }
        NotificationCenter.default.post(name: .picaxFollowUpdatesDidChange, object: nil)
    }

    static func loadDownloadRecords() -> [DownloadRecord] {
        loadValues("SELECT value FROM download_records ORDER BY sort_date DESC")
    }

    static func upsertDownloadRecord(_ record: DownloadRecord) {
        upsert(table: "download_records", id: record.id, sortDate: record.updatedAt, value: record)
    }

    static func replaceDownloadRecords(_ records: [DownloadRecord]) {
        replace(table: "download_records", values: records) { record in
            (record.id, record.updatedAt)
        }
    }

    static func deleteDownloadRecord(id: String) {
        delete(table: "download_records", id: id)
    }

    static func clearDownloadRecords() {
        clear(table: "download_records")
    }

    nonisolated static func loadNhentaiTagNames(ids: [Int]) -> [Int: StoredNhentaiTagName] {
        let uniqueIDs = Array(Set(ids.filter { $0 > 0 })).sorted()
        guard !uniqueIDs.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ", ")
        let records: [StoredNhentaiTagName] = loadValues(
            "SELECT value FROM nhentai_tag_names WHERE id IN (\(placeholders))",
            bindings: uniqueIDs.map { .text(String($0)) }
        )
        return records.reduce(into: [:]) { result, record in
            guard record.id > 0, !record.name.isEmpty else { return }
            result[record.id] = record
        }
    }

    nonisolated static func upsertNhentaiTagNames(_ records: [StoredNhentaiTagName]) {
        var latestByID: [Int: StoredNhentaiTagName] = [:]
        for record in records where record.id > 0 && !record.name.isEmpty {
            latestByID[record.id] = record
        }
        guard !latestByID.isEmpty else { return }

        db.transaction {
            for record in latestByID.values.sorted(by: { $0.id < $1.id }) {
                upsert(
                    table: "nhentai_tag_names",
                    id: String(record.id),
                    sortDate: record.updatedAt,
                    value: record
                )
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .picaxNhentaiTagNamesDidChange, object: nil)
        }
    }

    static func bytes(for table: SQLiteBackedTable) -> Int {
        db.tableBytes(table.rawValue)
    }

    private nonisolated static func upsert<Value: Encodable>(table: String, id: String, sortDate: Date, value: Value) {
        guard let data = encoded(value) else { return }
        db.execute(
            """
            INSERT OR REPLACE INTO \(table)(id, sort_date, value)
            VALUES(?, ?, ?)
            """,
            bindings: [.text(id), .double(sortDate.timeIntervalSince1970), .data(data)]
        )
    }

    private static func replace<Value: Encodable>(
        table: String,
        values: [Value],
        identity: (Value) -> (id: String, sortDate: Date)
    ) {
        db.transaction {
            clear(table: table)
            for value in values {
                let row = identity(value)
                upsert(table: table, id: row.id, sortDate: row.sortDate, value: value)
            }
        }
    }

    private static func delete(table: String, id: String) {
        db.execute("DELETE FROM \(table) WHERE id = ?", bindings: [.text(id)])
    }

    private static func clear(table: String) {
        db.execute("DELETE FROM \(table)")
    }

    private nonisolated static func encoded<Value: Encodable>(_ value: Value) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private nonisolated static func loadValues<Value: Decodable>(_ sql: String, bindings: [SQLiteBinding] = []) -> [Value] {
        let decoder = JSONDecoder()
        return db.dataRows(sql, bindings: bindings).compactMap { data in
            try? decoder.decode(Value.self, from: data)
        }
    }
}

enum SQLiteBackedTable: String {
    case readingHistory = "reading_history"
    case readLater = "read_later"
    case readingDuration = "reading_duration"
    case searchHistory = "search_history"
    case platformAccounts = "platform_accounts"
    case localFavorites = "local_favorites"
    case downloadRecords = "download_records"
    case nhentaiTagNames = "nhentai_tag_names"
}

struct StoredNhentaiTagName: Codable, Hashable, Sendable {
    let id: Int
    let group: String
    let name: String
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case group
        case name
        case updatedAt
    }

    nonisolated init(id: Int, group: String, name: String, updatedAt: Date = Date()) {
        self.id = id
        self.group = group
        self.name = name
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
        name = try container.decode(String.self, forKey: .name)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(group, forKey: .group)
        try container.encode(name, forKey: .name)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

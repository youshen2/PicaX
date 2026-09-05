import Foundation
import GRDB
import OSLog

final class PicaXSQLiteDatabase: Sendable {
    nonisolated static let shared = PicaXSQLiteDatabase()

    private let queueResult: Result<DatabaseQueue, Error>

    private nonisolated init() {
        queueResult = Self.openDatabase(at: Self.databaseURL())
    }

    nonisolated init(databaseURL: URL) {
        queueResult = Self.openDatabase(at: databaseURL)
    }

    private nonisolated static func openDatabase(
        at url: URL
    ) -> Result<DatabaseQueue, Error> {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            configuration.prepareDatabase { database in
                try database.execute(sql: "PRAGMA foreign_keys = ON")
            }
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            try Self.migrator.migrate(queue)
            return .success(queue)
        } catch {
            return .failure(error)
        }
    }

    nonisolated func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let queue = try queueResult.get()
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: sql, arguments: bindings.statementArguments)
        }
    }

    nonisolated func dataRows(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [Data] {
        let queue = try queueResult.get()
        return try queue.read { database in
            try Data.fetchAll(database, sql: sql, arguments: bindings.statementArguments)
        }
    }

    nonisolated func tableBytes(_ table: String) throws -> Int {
        let queue = try queueResult.get()
        return try queue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COALESCE(SUM(length(value)), 0) FROM \(table)"
            ) ?? 0
        }
    }

    nonisolated func write<T>(_ updates: (Database) throws -> T) throws -> T {
        let queue = try queueResult.get()
        return try queue.write(updates)
    }

    private nonisolated static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPicaXStore") { database in
            try database.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS reading_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_reading_history_sort
                    ON reading_history(sort_date DESC);

                CREATE TABLE IF NOT EXISTS read_later (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_read_later_sort
                    ON read_later(sort_date DESC);

                CREATE TABLE IF NOT EXISTS reading_duration (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_reading_duration_sort
                    ON reading_duration(sort_date DESC);

                CREATE TABLE IF NOT EXISTS search_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_search_history_sort
                    ON search_history(sort_date DESC);

                CREATE TABLE IF NOT EXISTS platform_accounts (
                    platform TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );

                CREATE TABLE IF NOT EXISTS local_favorites (
                    folder_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL,
                    PRIMARY KEY(folder_id, id)
                );
                CREATE INDEX IF NOT EXISTS idx_local_favorites_folder_sort
                    ON local_favorites(folder_id, sort_date DESC);

                CREATE TABLE IF NOT EXISTS follow_updates (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_follow_updates_sort
                    ON follow_updates(sort_date DESC);

                CREATE TABLE IF NOT EXISTS download_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_download_records_sort
                    ON download_records(sort_date DESC);

                CREATE TABLE IF NOT EXISTS nhentai_tag_names (
                    id TEXT PRIMARY KEY NOT NULL,
                    sort_date REAL NOT NULL,
                    value BLOB NOT NULL
                );
                """
            )
        }
        migrator.registerMigration("createLegacyUserDataMigrationState") { database in
            try database.execute(
                sql: """
                CREATE TABLE legacy_user_data_migrations (
                    source_key TEXT PRIMARY KEY NOT NULL,
                    payload_digest BLOB NOT NULL,
                    discarded_count INTEGER NOT NULL,
                    migrated_at REAL NOT NULL
                );
                """
            )
        }
        return migrator
    }()

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

struct PicaXSQLiteRestorePayload {
    var platformAccounts: [PlatformAccount]? = nil
    var localFavorites: [StoredLocalFavorite]? = nil
    var readingHistory: [ReadingHistoryRecord]? = nil
    var readLater: [ReadLaterRecord]? = nil
    var readingDuration: [ReadingDurationRecord]? = nil
    var searchHistory: [SearchHistoryRecord]? = nil
    var downloadRecords: [DownloadRecord]? = nil
}

private extension Array where Element == SQLiteBinding {
    nonisolated var statementArguments: StatementArguments {
        StatementArguments(map(\.databaseValue))
    }
}

private extension SQLiteBinding {
    nonisolated var databaseValue: DatabaseValue {
        switch self {
        case .text(let value):
            value.databaseValue
        case .double(let value):
            value.databaseValue
        case .data(let value):
            value.databaseValue
        }
    }
}

enum PicaXSQLiteStore {
    nonisolated private static let db = PicaXSQLiteDatabase.shared
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PicaX",
        category: "SQLiteStore"
    )

    static func migrateLegacyUserDataAtAppLaunch() {
        do {
            try LegacyUserDataMigration.migrate(
                defaults: .standard,
                database: db
            )
        } catch {
            report(error, operation: "migrate legacy user data")
        }
    }

    static func loadReadingHistory() -> [ReadingHistoryRecord] {
        loadValues("SELECT value FROM reading_history ORDER BY sort_date DESC")
    }

    nonisolated static func loadReadingHistoryOrThrow() throws -> [ReadingHistoryRecord] {
        try loadValuesOrThrow("SELECT value FROM reading_history ORDER BY sort_date DESC")
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

    nonisolated static func loadReadLaterOrThrow() throws -> [ReadLaterRecord] {
        try loadValuesOrThrow("SELECT value FROM read_later ORDER BY sort_date DESC")
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

    static func deleteReadLater(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        delete(table: "read_later", ids: ids)
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

    static func loadPlatformAccounts(
        defaults: UserDefaults = .standard
    ) -> [ComicPlatform: PlatformAccount] {
        do {
            try LegacyLocalAccountCredentialMigration.migrate(
                defaults: defaults,
                dependencies: LegacyLocalAccountCredentialMigration.Dependencies(
                    loadSecureData: LegacyLocalAccountCredentialVault.data,
                    restoreSecureData: LegacyLocalAccountCredentialVault.restore
                )
            )
        } catch {
            report(error, operation: "migrate legacy local account credentials")
        }

        do {
            let accounts = try PlatformCredentialMigration.migrate(
                defaults: defaults,
                dependencies: PlatformCredentialMigration.Dependencies(
                    loadPersistedAccounts: loadPersistedPlatformAccountsOrThrow,
                    persistRedactedAccounts: persistRedactedPlatformAccountsOrThrow,
                    loadSecrets: PlatformCredentialVault.secrets,
                    restoreSecrets: PlatformCredentialVault.restore
                )
            )
            return Dictionary(uniqueKeysWithValues: accounts.map { ($0.platform, $0) })
        } catch {
            report(error, operation: "migrate platform credentials")
            let persistedAccounts = (try? loadPersistedPlatformAccountsOrThrow()) ?? []
            let fallbackAccounts = PlatformCredentialMigration.fallbackAccounts(
                persistedAccounts: persistedAccounts,
                defaults: defaults,
                loadSecrets: PlatformCredentialVault.secrets
            )
            return Dictionary(
                uniqueKeysWithValues: fallbackAccounts.map { ($0.platform, $0) }
            )
        }
    }

    static func upsertPlatformAccount(_ account: PlatformAccount) {
        perform("upsert platform account") {
            try upsertPlatformAccountOrThrow(account)
        }
    }

    static func deletePlatformAccount(platform: ComicPlatform) {
        perform("delete platform account") {
            try deletePlatformAccountOrThrow(platform: platform)
        }
    }

    nonisolated static func loadLocalFavorites(folderID: String) -> [StoredLocalFavorite] {
        loadValues(
            "SELECT value FROM local_favorites WHERE folder_id = ? ORDER BY sort_date DESC",
            bindings: [.text(folderID)]
        )
    }

    nonisolated static func loadLocalFavoritesOrThrow(
        folderID: String
    ) throws -> [StoredLocalFavorite] {
        try loadValuesOrThrow(
            "SELECT value FROM local_favorites WHERE folder_id = ? ORDER BY sort_date DESC",
            bindings: [.text(folderID)]
        )
    }

    static func replaceLocalFavorites(_ favorites: [StoredLocalFavorite], folderID: String) {
        perform("replace local favorites") {
            try replaceLocalFavoritesOrThrow(favorites, folderID: folderID)
        }
        NotificationCenter.default.post(name: .picaxLocalFavoritesDidChange, object: nil)
    }

    static func upsertLocalFavorite(_ favorite: StoredLocalFavorite, folderID: String, notify: Bool = true) {
        guard let data = encoded(favorite) else { return }
        perform("upsert local favorite") {
            try db.execute(
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
        }
        if notify {
            NotificationCenter.default.post(name: .picaxLocalFavoritesDidChange, object: nil)
        }
    }

    static func loadFollowUpdateRecords() -> [FollowUpdateRecord] {
        loadValues("SELECT value FROM follow_updates ORDER BY sort_date DESC")
    }

    static func upsertFollowUpdateRecord(_ record: FollowUpdateRecord) {
        upsert(
            table: "follow_updates",
            id: record.id,
            sortDate: record.lastCheckDate ?? .distantPast,
            value: record
        )
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

    static func deleteDownloadRecords(ids: Set<String>) {
        delete(table: "download_records", ids: ids)
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

        perform("upsert nhentai tag names") {
            try db.write { database in
                for record in latestByID.values.sorted(by: { $0.id < $1.id }) {
                    let data = try encodedOrThrow(record)
                    try execute(
                        in: database,
                        sql: """
                        INSERT OR REPLACE INTO nhentai_tag_names(id, sort_date, value)
                        VALUES(?, ?, ?)
                        """,
                        bindings: [
                            .text(String(record.id)),
                            .double(record.updatedAt.timeIntervalSince1970),
                            .data(data)
                        ]
                    )
                }
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .picaxNhentaiTagNamesDidChange, object: nil)
        }
    }

    nonisolated static func bytes(for table: SQLiteBackedTable) -> Int {
        do {
            return try db.tableBytes(table.rawValue)
        } catch {
            report(error, operation: "read \(table.rawValue) size")
            return 0
        }
    }

    private nonisolated static func upsert<Value: Encodable>(table: String, id: String, sortDate: Date, value: Value) {
        guard let data = encoded(value) else { return }
        perform("upsert \(table)") {
            try db.execute(
                """
                INSERT OR REPLACE INTO \(table)(id, sort_date, value)
                VALUES(?, ?, ?)
                """,
                bindings: [.text(id), .double(sortDate.timeIntervalSince1970), .data(data)]
            )
        }
    }

    private static func replace<Value: Encodable>(
        table: String,
        values: [Value],
        identity: (Value) -> (id: String, sortDate: Date)
    ) {
        perform("replace \(table)") {
            try replaceOrThrow(table: table, values: values, identity: identity)
        }
    }

    private static func delete(table: String, id: String) {
        perform("delete from \(table)") {
            try db.execute("DELETE FROM \(table) WHERE id = ?", bindings: [.text(id)])
        }
    }

    private static func delete(table: String, ids: Set<String>) {
        let sortedIDs = ids.sorted()
        guard !sortedIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: sortedIDs.count).joined(separator: ", ")
        perform("delete from \(table)") {
            try db.execute(
                "DELETE FROM \(table) WHERE id IN (\(placeholders))",
                bindings: sortedIDs.map(SQLiteBinding.text)
            )
        }
    }

    private static func clear(table: String) {
        perform("clear \(table)") {
            try db.execute("DELETE FROM \(table)")
        }
    }

    private nonisolated static func encoded<Value: Encodable>(_ value: Value) -> Data? {
        do {
            return try encodedOrThrow(value)
        } catch {
            report(error, operation: "encode database value")
            return nil
        }
    }

    static func upsertPlatformAccountOrThrow(_ account: PlatformAccount) throws {
        let previousSecrets = try PlatformCredentialVault.secrets(for: account.platform)
        do {
            let persistedAccount = try PlatformCredentialVault.persist(account)
            let data = try encodedOrThrow(persistedAccount)
            try db.execute(
                """
                INSERT OR REPLACE INTO platform_accounts(platform, sort_date, value)
                VALUES(?, ?, ?)
                """,
                bindings: [
                    .text(account.platform.id),
                    .double(account.loggedInAt.timeIntervalSince1970),
                    .data(data)
                ]
            )
        } catch {
            let operationError = error
            try PlatformCredentialVault.restore(previousSecrets, for: account.platform)
            throw operationError
        }
    }

    static func deletePlatformAccountOrThrow(platform: ComicPlatform) throws {
        let previousSecrets = try PlatformCredentialVault.secrets(for: platform)
        do {
            try PlatformCredentialVault.delete(platform: platform)
            try db.execute(
                "DELETE FROM platform_accounts WHERE platform = ?",
                bindings: [.text(platform.id)]
            )
        } catch {
            let operationError = error
            try PlatformCredentialVault.restore(previousSecrets, for: platform)
            throw operationError
        }
    }

    private static func loadPersistedPlatformAccountsOrThrow() throws -> [PlatformAccount] {
        let rows = try db.dataRows(
            "SELECT value FROM platform_accounts ORDER BY sort_date DESC"
        )
        return decodeStoredRows(rows, as: PlatformAccount.self)
    }

    private static func persistRedactedPlatformAccountsOrThrow(
        _ accounts: [PlatformAccount]
    ) throws {
        try db.write { database in
            for account in accounts {
                var redactedAccount = account
                redactedAccount.credential = account.credential.removingSecrets()
                try execute(
                    in: database,
                    sql: """
                    INSERT OR REPLACE INTO platform_accounts(platform, sort_date, value)
                    VALUES(?, ?, ?)
                    """,
                    bindings: [
                        .text(redactedAccount.platform.id),
                        .double(redactedAccount.loggedInAt.timeIntervalSince1970),
                        .data(try encodedOrThrow(redactedAccount))
                    ]
                )
            }
        }
    }

    static func replaceLocalFavoritesOrThrow(
        _ favorites: [StoredLocalFavorite],
        folderID: String
    ) throws {
        try db.write { database in
            try database.execute(
                sql: "DELETE FROM local_favorites WHERE folder_id = ?",
                arguments: [folderID]
            )
            for favorite in favorites {
                try execute(
                    in: database,
                    sql: """
                    INSERT OR REPLACE INTO local_favorites(folder_id, id, sort_date, value)
                    VALUES(?, ?, ?, ?)
                    """,
                    bindings: [
                        .text(folderID),
                        .text("\(favorite.platform.id)-\(favorite.id)"),
                        .double((favorite.favoriteDate ?? .distantPast).timeIntervalSince1970),
                        .data(try encodedOrThrow(favorite))
                    ]
                )
            }
        }
    }

    static func replaceReadingHistoryOrThrow(_ records: [ReadingHistoryRecord]) throws {
        try replaceOrThrow(table: "reading_history", values: records) {
            ($0.id, $0.viewedAt)
        }
    }

    static func replaceReadLaterOrThrow(_ records: [ReadLaterRecord]) throws {
        try replaceOrThrow(table: "read_later", values: records) {
            ($0.id, $0.addedAt)
        }
    }

    static func replaceReadingDurationOrThrow(_ records: [ReadingDurationRecord]) throws {
        try replaceOrThrow(table: "reading_duration", values: records) {
            ($0.id, $0.lastReadAt)
        }
    }

    static func replaceSearchHistoryOrThrow(_ records: [SearchHistoryRecord]) throws {
        try replaceOrThrow(table: "search_history", values: records) {
            ($0.id, $0.searchedAt)
        }
    }

    static func replaceDownloadRecordsOrThrow(_ records: [DownloadRecord]) throws {
        try replaceOrThrow(table: "download_records", values: records) {
            ($0.id, $0.updatedAt)
        }
    }

    static func applyRestoreOrThrow(_ payload: PicaXSQLiteRestorePayload) throws {
        let previousSecrets: [ComicPlatform: PlatformCredentialSecrets?]?
        if payload.platformAccounts != nil {
            previousSecrets = try Dictionary(
                uniqueKeysWithValues: ComicPlatform.onlinePlatforms.map {
                    ($0, try PlatformCredentialVault.secrets(for: $0))
                }
            )
        } else {
            previousSecrets = nil
        }

        do {
            let persistedAccounts = try payload.platformAccounts?.map(
                PlatformCredentialVault.persistPreservingExistingSecrets
            )
            if let persistedAccounts {
                let restoredPlatforms = Set(persistedAccounts.map(\.platform))
                for platform in ComicPlatform.onlinePlatforms where !restoredPlatforms.contains(platform) {
                    try PlatformCredentialVault.delete(platform: platform)
                }
            }
            try db.write { database in
            if let persistedAccounts {
                try database.execute(sql: "DELETE FROM platform_accounts")
                for account in persistedAccounts {
                    try execute(
                        in: database,
                        sql: """
                        INSERT OR REPLACE INTO platform_accounts(platform, sort_date, value)
                        VALUES(?, ?, ?)
                        """,
                        bindings: [
                            .text(account.platform.id),
                            .double(account.loggedInAt.timeIntervalSince1970),
                            .data(try encodedOrThrow(account))
                        ]
                    )
                }
            }
            if let localFavorites = payload.localFavorites {
                try database.execute(
                    sql: "DELETE FROM local_favorites WHERE folder_id = ?",
                    arguments: ["default"]
                )
                for favorite in localFavorites {
                    try execute(
                        in: database,
                        sql: """
                        INSERT OR REPLACE INTO local_favorites(folder_id, id, sort_date, value)
                        VALUES(?, ?, ?, ?)
                        """,
                        bindings: [
                            .text("default"),
                            .text("\(favorite.platform.id)-\(favorite.id)"),
                            .double((favorite.favoriteDate ?? .distantPast).timeIntervalSince1970),
                            .data(try encodedOrThrow(favorite))
                        ]
                    )
                }
            }
            if let values = payload.readingHistory {
                try replace(
                    in: database,
                    table: "reading_history",
                    values: values,
                    identity: { ($0.id, $0.viewedAt) }
                )
            }
            if let values = payload.readLater {
                try replace(
                    in: database,
                    table: "read_later",
                    values: values,
                    identity: { ($0.id, $0.addedAt) }
                )
            }
            if let values = payload.readingDuration {
                try replace(
                    in: database,
                    table: "reading_duration",
                    values: values,
                    identity: { ($0.id, $0.lastReadAt) }
                )
            }
            if let values = payload.searchHistory {
                try replace(
                    in: database,
                    table: "search_history",
                    values: values,
                    identity: { ($0.id, $0.searchedAt) }
                )
            }
            if let values = payload.downloadRecords {
                try replace(
                    in: database,
                    table: "download_records",
                    values: values,
                    identity: { ($0.id, $0.updatedAt) }
                )
            }
            }
        } catch {
            let operationError = error
            if let previousSecrets {
                for platform in ComicPlatform.onlinePlatforms {
                    try PlatformCredentialVault.restore(
                        previousSecrets[platform] ?? nil,
                        for: platform
                    )
                }
            }
            throw operationError
        }
    }

    private nonisolated static func replaceOrThrow<Value: Encodable>(
        table: String,
        values: [Value],
        identity: (Value) -> (id: String, sortDate: Date)
    ) throws {
        try db.write { database in
            try replace(
                in: database,
                table: table,
                values: values,
                identity: identity
            )
        }
    }

    private nonisolated static func replace<Value: Encodable>(
        in database: Database,
        table: String,
        values: [Value],
        identity: (Value) -> (id: String, sortDate: Date)
    ) throws {
        try database.execute(sql: "DELETE FROM \(table)")
        for value in values {
            let row = identity(value)
            try execute(
                in: database,
                sql: """
                INSERT OR REPLACE INTO \(table)(id, sort_date, value)
                VALUES(?, ?, ?)
                """,
                bindings: [
                    .text(row.id),
                    .double(row.sortDate.timeIntervalSince1970),
                    .data(try encodedOrThrow(value))
                ]
            )
        }
    }

    private nonisolated static func execute(
        in database: Database,
        sql: String,
        bindings: [SQLiteBinding] = []
    ) throws {
        try database.execute(sql: sql, arguments: bindings.statementArguments)
    }

    private nonisolated static func encodedOrThrow<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private nonisolated static func loadValuesOrThrow<Value: Decodable>(
        _ sql: String,
        bindings: [SQLiteBinding] = []
    ) throws -> [Value] {
        let rows = try db.dataRows(sql, bindings: bindings)
        let decoder = JSONDecoder()
        return try rows.map { try decoder.decode(Value.self, from: $0) }
    }

    private nonisolated static func perform(
        _ operation: String,
        _ body: () throws -> Void
    ) {
        do {
            try body()
        } catch {
            report(error, operation: operation)
        }
    }

    private nonisolated static func report(_ error: Error, operation: String) {
        logger.error("\(operation, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }

    private nonisolated static func loadValues<Value: Decodable>(_ sql: String, bindings: [SQLiteBinding] = []) -> [Value] {
        do {
            let rows = try db.dataRows(sql, bindings: bindings)
            return decodeStoredRows(rows, as: Value.self)
        } catch {
            report(error, operation: "load values")
            return []
        }
    }

    nonisolated static func decodeStoredRows<Value: Decodable>(
        _ rows: [Data],
        as type: Value.Type
    ) -> [Value] {
        let decoder = JSONDecoder()
        return rows.compactMap { data in
            do {
                return try decoder.decode(type, from: data)
            } catch {
                report(error, operation: "decode stored \(String(describing: type))")
                return nil
            }
        }
    }
}

enum SQLiteBackedTable: String, Sendable {
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

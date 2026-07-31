import GRDB
import XCTest
@testable import PicaX

@MainActor
final class LegacyUserDataMigrationTests: XCTestCase {
    func testMigratesEveryLegacyUserDefaultsCollectionAndKeepsSourcePayloads() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let item = makeItem(title: "旧版漫画")
        let date = Date(timeIntervalSince1970: 1_000)
        let readingHistory = ReadingHistoryRecord(
            item: item,
            viewedAt: date,
            progress: nil
        )
        let readLater = ReadLaterRecord(item: item, addedAt: date)
        let readingDuration = ReadingDurationRecord(
            item: item,
            totalSeconds: 120,
            dailySeconds: ["2026-07-31": 120],
            lastReadAt: date
        )
        let searchHistory = SearchHistoryRecord(
            keyword: "legacy",
            target: .platform(.picacg),
            searchedAt: date
        )
        let downloadRecord = DownloadRecord(
            item: item,
            chapters: [],
            totalChapterCount: 1,
            totalBytes: 0,
            directoryName: "legacy-download",
            coverFileName: nil,
            detail: nil,
            comments: [],
            updatedAt: date
        )
        let favorite = StoredLocalFavorite(item: item, favoriteDate: date)
        let sourcePayloads = [
            LegacyUserDataMigration.readingHistoryKey: try encode([readingHistory]),
            LegacyUserDataMigration.readLaterKey: try encode([readLater]),
            LegacyUserDataMigration.readingDurationKey: try encode([readingDuration]),
            LegacyUserDataMigration.searchHistoryKey: try encode([searchHistory]),
            LegacyUserDataMigration.downloadRecordsKey: try encode([downloadRecord]),
            LegacyUserDataMigration.localFavoritesPrefix + "default": try encode([favorite])
        ]
        for (key, data) in sourcePayloads {
            fixture.defaults.set(data, forKey: key)
        }

        try LegacyUserDataMigration.migrate(
            defaults: fixture.defaults,
            database: fixture.database
        )

        let migratedHistory: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        let migratedReadLater: [ReadLaterRecord] = try load(
            table: "read_later",
            database: fixture.database
        )
        let migratedDuration: [ReadingDurationRecord] = try load(
            table: "reading_duration",
            database: fixture.database
        )
        let migratedSearch: [SearchHistoryRecord] = try load(
            table: "search_history",
            database: fixture.database
        )
        let migratedDownloads: [DownloadRecord] = try load(
            table: "download_records",
            database: fixture.database
        )
        let migratedFavorites: [StoredLocalFavorite] = try load(
            table: "local_favorites",
            database: fixture.database
        )

        XCTAssertEqual(migratedHistory.map(\.id), [readingHistory.id])
        XCTAssertEqual(migratedReadLater.map(\.id), [readLater.id])
        XCTAssertEqual(migratedDuration.map(\.id), [readingDuration.id])
        XCTAssertEqual(migratedSearch.map(\.id), [searchHistory.id])
        XCTAssertEqual(migratedDownloads.map(\.id), [downloadRecord.id])
        XCTAssertEqual(migratedFavorites.map(\.id), [favorite.id])

        for (key, data) in sourcePayloads {
            XCTAssertEqual(fixture.defaults.data(forKey: key), data)
        }
        let processedSourceKeys = Set(
            try fixture.database.dataRows(
                """
                SELECT CAST(source_key AS BLOB)
                FROM legacy_user_data_migrations
                """
            ).compactMap { String(data: $0, encoding: .utf8) }
        )
        XCTAssertTrue(processedSourceKeys.isSuperset(of: sourcePayloads.keys))
    }

    func testDoesNotOverwriteNewerSQLiteRecordWithOlderLegacyValue() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let oldRecord = ReadingHistoryRecord(
            item: makeItem(title: "旧标题"),
            viewedAt: Date(timeIntervalSince1970: 1_000),
            progress: nil
        )
        let newRecord = ReadingHistoryRecord(
            item: makeItem(title: "新标题"),
            viewedAt: Date(timeIntervalSince1970: 2_000),
            progress: nil
        )
        try fixture.database.execute(
            """
            INSERT INTO reading_history(id, sort_date, value)
            VALUES(?, ?, ?)
            """,
            bindings: [
                .text(newRecord.id),
                .double(newRecord.viewedAt.timeIntervalSince1970),
                .data(try encode(newRecord))
            ]
        )
        fixture.defaults.set(
            try encode([oldRecord]),
            forKey: LegacyUserDataMigration.readingHistoryKey
        )

        try LegacyUserDataMigration.migrate(
            defaults: fixture.defaults,
            database: fixture.database
        )

        let migrated: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.item.title, "新标题")
        XCTAssertEqual(migrated.first?.viewedAt, newRecord.viewedAt)
    }

    func testPartiallyInvalidPayloadIsProcessedOnlyOnceWithoutResurrectingData() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let validRecord = ReadingHistoryRecord(
            item: makeItem(title: "可恢复"),
            viewedAt: Date(timeIntervalSince1970: 1_000),
            progress: nil
        )
        let validObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encode(validRecord)) as? [String: Any]
        )
        let payload = try JSONSerialization.data(
            withJSONObject: [validObject, ["invalid": true]]
        )
        fixture.defaults.set(
            payload,
            forKey: LegacyUserDataMigration.readingHistoryKey
        )

        XCTAssertThrowsError(
            try LegacyUserDataMigration.migrate(
                defaults: fixture.defaults,
                database: fixture.database
            )
        )

        let migrated: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        XCTAssertEqual(migrated.map(\.id), [validRecord.id])
        let discardedCount = try fixture.database.write { database in
            try Int.fetchOne(
                database,
                sql: """
                SELECT discarded_count
                FROM legacy_user_data_migrations
                WHERE source_key = ?
                """,
                arguments: [LegacyUserDataMigration.readingHistoryKey]
            )
        }
        XCTAssertEqual(discardedCount, 1)
        XCTAssertEqual(
            fixture.defaults.data(
                forKey: LegacyUserDataMigration.readingHistoryKey
            ),
            payload
        )

        try fixture.database.execute(
            "DELETE FROM reading_history WHERE id = ?",
            bindings: [.text(validRecord.id)]
        )
        XCTAssertNoThrow(
            try LegacyUserDataMigration.migrate(
                defaults: fixture.defaults,
                database: fixture.database
            )
        )
        let afterRetry: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        XCTAssertTrue(afterRetry.isEmpty)
    }

    func testMergesSequentialHistoryDurationAndDownloadData() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let legacyItem = makeItem(title: "旧标题")
        let currentItem = makeItem(title: "新标题")
        let legacyDate = Date(timeIntervalSince1970: 1_000)
        let currentDate = Date(timeIntervalSince1970: 2_000)
        let legacyHistory = ReadingHistoryRecord(
            item: legacyItem,
            viewedAt: legacyDate,
            progress: ReadingProgress(
                status: .reading,
                chapterIndex: 0,
                pageIndex: 9,
                totalPages: 10,
                totalChapters: 3,
                readChapterIndexes: [0],
                updatedAt: legacyDate
            )
        )
        let currentHistory = ReadingHistoryRecord(
            item: currentItem,
            viewedAt: currentDate,
            progress: ReadingProgress(
                status: .reading,
                chapterIndex: 1,
                pageIndex: 9,
                totalPages: 10,
                totalChapters: 3,
                readChapterIndexes: [1],
                updatedAt: currentDate
            )
        )
        let legacyDuration = ReadingDurationRecord(
            item: legacyItem,
            totalSeconds: 120,
            dailySeconds: ["2026-07-30": 120],
            lastReadAt: legacyDate
        )
        let currentDuration = ReadingDurationRecord(
            item: currentItem,
            totalSeconds: 30,
            dailySeconds: ["2026-07-31": 30],
            lastReadAt: currentDate
        )
        let legacyDownload = DownloadRecord(
            item: legacyItem,
            chapters: [
                makeChapter(index: 0, bytes: 10, date: legacyDate)
            ],
            totalChapterCount: 2,
            totalBytes: 10,
            directoryName: "legacy-download",
            coverFileName: "cover.jpg",
            detail: nil,
            comments: [],
            updatedAt: legacyDate
        )
        let currentDownload = DownloadRecord(
            item: currentItem,
            chapters: [
                makeChapter(index: 1, bytes: 20, date: currentDate)
            ],
            totalChapterCount: 2,
            totalBytes: 20,
            directoryName: "legacy-download",
            coverFileName: nil,
            detail: nil,
            comments: [],
            updatedAt: currentDate
        )
        try insert(
            currentHistory,
            table: "reading_history",
            id: currentHistory.id,
            sortDate: currentHistory.viewedAt,
            database: fixture.database
        )
        try insert(
            currentDuration,
            table: "reading_duration",
            id: currentDuration.id,
            sortDate: currentDuration.lastReadAt,
            database: fixture.database
        )
        try insert(
            currentDownload,
            table: "download_records",
            id: currentDownload.id,
            sortDate: currentDownload.updatedAt,
            database: fixture.database
        )
        fixture.defaults.set(
            try encode([legacyHistory]),
            forKey: LegacyUserDataMigration.readingHistoryKey
        )
        fixture.defaults.set(
            try encode([legacyDuration]),
            forKey: LegacyUserDataMigration.readingDurationKey
        )
        fixture.defaults.set(
            try encode([legacyDownload]),
            forKey: LegacyUserDataMigration.downloadRecordsKey
        )

        try LegacyUserDataMigration.migrate(
            defaults: fixture.defaults,
            database: fixture.database
        )

        let histories: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        let durations: [ReadingDurationRecord] = try load(
            table: "reading_duration",
            database: fixture.database
        )
        let downloads: [DownloadRecord] = try load(
            table: "download_records",
            database: fixture.database
        )
        XCTAssertEqual(histories.first?.item.title, "新标题")
        XCTAssertEqual(histories.first?.progress?.readChapterIndexes, [0, 1])
        XCTAssertEqual(durations.first?.totalSeconds, 150)
        XCTAssertEqual(
            durations.first?.dailySeconds,
            ["2026-07-30": 120, "2026-07-31": 30]
        )
        XCTAssertEqual(downloads.first?.chapters.map(\.index), [0, 1])
        XCTAssertEqual(downloads.first?.totalBytes, 30)
        XCTAssertEqual(downloads.first?.coverFileName, "cover.jpg")
    }

    func testValidLegacyValueRepairsNewerCorruptSQLiteRow() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let legacyRecord = ReadingHistoryRecord(
            item: makeItem(title: "可恢复"),
            viewedAt: Date(timeIntervalSince1970: 1_000),
            progress: nil
        )
        try fixture.database.execute(
            """
            INSERT INTO reading_history(id, sort_date, value)
            VALUES(?, ?, ?)
            """,
            bindings: [
                .text(legacyRecord.id),
                .double(2_000),
                .data(Data("corrupt".utf8))
            ]
        )
        fixture.defaults.set(
            try encode([legacyRecord]),
            forKey: LegacyUserDataMigration.readingHistoryKey
        )

        try LegacyUserDataMigration.migrate(
            defaults: fixture.defaults,
            database: fixture.database
        )

        let migrated: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: fixture.database
        )
        XCTAssertEqual(migrated.map(\.id), [legacyRecord.id])
        XCTAssertEqual(
            migrated.first?.item.title,
            legacyRecord.item.title
        )
    }

    func testOpeningLegacySQLiteSchemaPreservesRowsAndAddsMigrationMetadata() throws {
        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacySQLiteSchemaTests", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("PicaX.sqlite3")
        let record = ReadingHistoryRecord(
            item: makeItem(title: "旧数据库"),
            viewedAt: Date(timeIntervalSince1970: 1_000),
            progress: nil
        )

        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { database in
            try database.execute(sql: Self.legacySQLiteSchema)
            let arguments: StatementArguments = [
                record.id,
                record.viewedAt.timeIntervalSince1970,
                try encode(record)
            ]
            try database.execute(
                sql: """
                INSERT INTO reading_history(id, sort_date, value)
                VALUES(?, ?, ?)
                """,
                arguments: arguments
            )
        }
        try legacyQueue.close()

        let migratedDatabase = PicaXSQLiteDatabase(databaseURL: databaseURL)
        let migrated: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: migratedDatabase
        )
        let migrationIdentifiers = try migratedDatabase.dataRows(
            "SELECT CAST(identifier AS BLOB) FROM grdb_migrations"
        )
        let tableNames = try migratedDatabase.dataRows(
            """
            SELECT CAST(name AS BLOB)
            FROM sqlite_master
            WHERE type = 'table'
            """
        ).compactMap { String(data: $0, encoding: .utf8) }
        let reopenedDatabase = PicaXSQLiteDatabase(databaseURL: databaseURL)
        let reopenedRecords: [ReadingHistoryRecord] = try load(
            table: "reading_history",
            database: reopenedDatabase
        )

        XCTAssertEqual(migrated.map(\.id), [record.id])
        XCTAssertEqual(reopenedRecords.map(\.id), [record.id])
        XCTAssertTrue(tableNames.contains("legacy_user_data_migrations"))
        XCTAssertTrue(
            migrationIdentifiers
                .compactMap { String(data: $0, encoding: .utf8) }
                .contains("createPicaXStore")
        )
        XCTAssertTrue(
            migrationIdentifiers
                .compactMap { String(data: $0, encoding: .utf8) }
                .contains("createLegacyUserDataMigrationState")
        )
    }

    func testTolerantSQLiteDecodeKeepsValidRowsWhenAnotherRowIsCorrupt() throws {
        let validRecord = ReadingHistoryRecord(
            item: makeItem(title: "仍可显示"),
            viewedAt: Date(timeIntervalSince1970: 1_000),
            progress: nil
        )

        let decoded = PicaXSQLiteStore.decodeStoredRows(
            [try encode(validRecord), Data("invalid".utf8)],
            as: ReadingHistoryRecord.self
        )

        XCTAssertEqual(decoded.map(\.id), [validRecord.id])
    }

    private func makeFixture() throws -> MigrationFixture {
        let identifier = UUID().uuidString
        let suiteName = "LegacyUserDataMigrationTests.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyUserDataMigrationTests", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return MigrationFixture(
            suiteName: suiteName,
            defaults: defaults,
            directory: directory,
            database: PicaXSQLiteDatabase(
                databaseURL: directory.appendingPathComponent("PicaX.sqlite3")
            )
        )
    }

    private func makeItem(title: String) -> ComicListItem {
        ComicListItem(
            id: "legacy-comic",
            platform: .picacg,
            title: title,
            subtitle: "旧版数据",
            coverURLString: "https://example.com/cover.jpg",
            tags: ["legacy"],
            pageCount: 10,
            likesCount: 5,
            favoriteDate: nil
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func insert<Value: Encodable>(
        _ value: Value,
        table: String,
        id: String,
        sortDate: Date,
        database: PicaXSQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO \(table)(id, sort_date, value)
            VALUES(?, ?, ?)
            """,
            bindings: [
                .text(id),
                .double(sortDate.timeIntervalSince1970),
                .data(try encode(value))
            ]
        )
    }

    private func makeChapter(
        index: Int,
        bytes: Int64,
        date: Date
    ) -> DownloadedChapterRecord {
        DownloadedChapterRecord(
            index: index,
            chapter: ComicChapter(
                id: "chapter-\(index)",
                title: "第 \(index + 1) 章",
                subtitle: nil
            ),
            pageCount: 1,
            bytes: bytes,
            downloadedAt: date
        )
    }

    private func load<Value: Decodable>(
        table: String,
        database: PicaXSQLiteDatabase
    ) throws -> [Value] {
        try database.dataRows("SELECT value FROM \(table) ORDER BY sort_date DESC")
            .map { try JSONDecoder().decode(Value.self, from: $0) }
    }

    private static let legacySQLiteSchema = """
    CREATE TABLE reading_history (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_reading_history_sort
        ON reading_history(sort_date DESC);
    CREATE TABLE read_later (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_read_later_sort
        ON read_later(sort_date DESC);
    CREATE TABLE reading_duration (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_reading_duration_sort
        ON reading_duration(sort_date DESC);
    CREATE TABLE search_history (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_search_history_sort
        ON search_history(sort_date DESC);
    CREATE TABLE platform_accounts (
        platform TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE TABLE local_favorites (
        folder_id TEXT NOT NULL,
        id TEXT NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL,
        PRIMARY KEY(folder_id, id)
    );
    CREATE INDEX idx_local_favorites_folder_sort
        ON local_favorites(folder_id, sort_date DESC);
    CREATE TABLE follow_updates (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_follow_updates_sort
        ON follow_updates(sort_date DESC);
    CREATE TABLE download_records (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    CREATE INDEX idx_download_records_sort
        ON download_records(sort_date DESC);
    CREATE TABLE nhentai_tag_names (
        id TEXT PRIMARY KEY NOT NULL,
        sort_date REAL NOT NULL,
        value BLOB NOT NULL
    );
    """
}

private struct MigrationFixture {
    let suiteName: String
    let defaults: UserDefaults
    let directory: URL
    let database: PicaXSQLiteDatabase

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

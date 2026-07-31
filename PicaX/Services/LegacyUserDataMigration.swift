import CryptoKit
import Foundation
import GRDB

nonisolated struct LegacyUserDataMigrationError: LocalizedError {
    let failedSourceKeys: [String]

    var errorDescription: String? {
        "旧版数据未能完整迁移：\(failedSourceKeys.joined(separator: "、"))"
    }
}

enum LegacyUserDataMigration {
    static let readingHistoryKey = ReadingHistoryService.Key.records
    static let readLaterKey = ReadLaterService.Key.records
    static let readingDurationKey = ReadingDurationService.Key.records
    static let searchHistoryKey = SearchHistorySettingsKey.records
    static let downloadRecordsKey = DownloadSettingsKey.records
    static let localFavoritesPrefix = LocalFavoritesStore.legacyDefaultsKeyPrefix

    private static let lock = NSLock()

    static func migrate(
        defaults: UserDefaults = .standard,
        database: PicaXSQLiteDatabase
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var failedSourceKeys: [String] = []

        attempt(readingHistoryKey, failures: &failedSourceKeys) {
            try migrateRecords(
                sourceKey: readingHistoryKey,
                table: "reading_history",
                defaults: defaults,
                database: database,
                identity: { (record: ReadingHistoryRecord) in
                    (record.id, record.viewedAt)
                },
                merge: mergeReadingHistory
            )
        }
        attempt(readLaterKey, failures: &failedSourceKeys) {
            try migrateRecords(
                sourceKey: readLaterKey,
                table: "read_later",
                defaults: defaults,
                database: database
            ) { (record: ReadLaterRecord) in
                (record.id, record.addedAt)
            }
        }
        attempt(readingDurationKey, failures: &failedSourceKeys) {
            try migrateRecords(
                sourceKey: readingDurationKey,
                table: "reading_duration",
                defaults: defaults,
                database: database,
                identity: { (record: ReadingDurationRecord) in
                    (record.id, record.lastReadAt)
                },
                merge: mergeReadingDuration
            )
        }
        attempt(searchHistoryKey, failures: &failedSourceKeys) {
            try migrateRecords(
                sourceKey: searchHistoryKey,
                table: "search_history",
                defaults: defaults,
                database: database
            ) { (record: SearchHistoryRecord) in
                (record.id, record.searchedAt)
            }
        }
        attempt(downloadRecordsKey, failures: &failedSourceKeys) {
            try migrateRecords(
                sourceKey: downloadRecordsKey,
                table: "download_records",
                defaults: defaults,
                database: database,
                identity: { (record: DownloadRecord) in
                    (record.id, record.updatedAt)
                },
                merge: mergeDownloadRecord
            )
        }

        let favoriteSourceKeys = Set(
            [localFavoritesPrefix + "default"]
                + defaults.dictionaryRepresentation().keys.filter {
                    $0.hasPrefix(localFavoritesPrefix)
                }
        )
        for sourceKey in favoriteSourceKeys.sorted() {
            attempt(sourceKey, failures: &failedSourceKeys) {
                try migrateLocalFavorites(
                    sourceKey: sourceKey,
                    defaults: defaults,
                    database: database
                )
            }
        }

        if !failedSourceKeys.isEmpty {
            throw LegacyUserDataMigrationError(
                failedSourceKeys: failedSourceKeys.sorted()
            )
        }
    }

    private static func attempt(
        _ sourceKey: String,
        failures: inout [String],
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            failures.append(sourceKey)
        }
    }

    private static func migrateRecords<Value: Codable>(
        sourceKey: String,
        table: String,
        defaults: UserDefaults,
        database: PicaXSQLiteDatabase,
        identity: (Value) -> (id: String, sortDate: Date),
        merge: ((Value, Value) -> Value)? = nil
    ) throws {
        guard let payload = try legacyPayload(sourceKey, defaults: defaults) else { return }
        let digest = payloadDigest(payload)
        guard try !isProcessed(
            sourceKey,
            digest: digest,
            database: database
        ) else { return }

        let decoded = try JSONDecoder().decode(
            LossyDecodableArray<Value>.self,
            from: payload
        )
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        try database.write { db in
            var existingValues: [String: Data] = [:]
            for row in try Row.fetchAll(
                db,
                sql: "SELECT id, value FROM \(table)"
            ) {
                let id: String = row["id"]
                let data: Data = row["value"]
                existingValues[id] = data
            }

            for value in decoded.values {
                let legacyRow = identity(value)
                let migratedValue: Value
                if let existingData = existingValues[legacyRow.id],
                   let existingValue = try? decoder.decode(
                       Value.self,
                       from: existingData
                   ) {
                    if let merge {
                        migratedValue = merge(value, existingValue)
                    } else {
                        migratedValue = legacyRow.sortDate
                            > identity(existingValue).sortDate
                            ? value
                            : existingValue
                    }
                } else {
                    migratedValue = value
                }
                let migratedRow = identity(migratedValue)
                let migratedData = try encoder.encode(migratedValue)
                try upsert(
                    table: table,
                    id: legacyRow.id,
                    sortDate: migratedRow.sortDate,
                    data: migratedData,
                    database: db
                )
                existingValues[legacyRow.id] = migratedData
            }
            try markProcessed(
                sourceKey,
                digest: digest,
                discardedCount: decoded.discardedCount,
                database: db
            )
        }

        guard decoded.discardedCount == 0 else {
            throw LegacyPayloadError.invalidRecordCount(decoded.discardedCount)
        }
    }

    private static func migrateLocalFavorites(
        sourceKey: String,
        defaults: UserDefaults,
        database: PicaXSQLiteDatabase
    ) throws {
        guard let payload = try legacyPayload(sourceKey, defaults: defaults) else { return }
        let digest = payloadDigest(payload)
        guard try !isProcessed(
            sourceKey,
            digest: digest,
            database: database
        ) else { return }

        let folderID = String(sourceKey.dropFirst(localFavoritesPrefix.count))
        guard !folderID.isEmpty else {
            throw LegacyPayloadError.invalidFavoriteFolder
        }
        let decoded = try JSONDecoder().decode(
            LossyDecodableArray<StoredLocalFavorite>.self,
            from: payload
        )
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        try database.write { db in
            var existingValues: [String: Data] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                SELECT id, value FROM local_favorites
                WHERE folder_id = ?
                """,
                arguments: [folderID]
            ) {
                let id: String = row["id"]
                let data: Data = row["value"]
                existingValues[id] = data
            }

            for favorite in decoded.values {
                let id = "\(favorite.platform.id)-\(favorite.id)"
                let migratedFavorite: StoredLocalFavorite
                if let existingData = existingValues[id],
                   let existingFavorite = try? decoder.decode(
                       StoredLocalFavorite.self,
                       from: existingData
                   ),
                   (existingFavorite.favoriteDate ?? .distantPast)
                    >= (favorite.favoriteDate ?? .distantPast) {
                    migratedFavorite = existingFavorite
                } else {
                    migratedFavorite = favorite
                }
                let migratedData = try encoder.encode(migratedFavorite)
                try upsertLocalFavorite(
                    migratedFavorite,
                    folderID: folderID,
                    data: migratedData,
                    database: db
                )
                existingValues[id] = migratedData
            }
            try markProcessed(
                sourceKey,
                digest: digest,
                discardedCount: decoded.discardedCount,
                database: db
            )
        }

        guard decoded.discardedCount == 0 else {
            throw LegacyPayloadError.invalidRecordCount(decoded.discardedCount)
        }
    }

    private static func legacyPayload(
        _ sourceKey: String,
        defaults: UserDefaults
    ) throws -> Data? {
        guard let value = defaults.object(forKey: sourceKey) else { return nil }
        guard let data = value as? Data else {
            throw LegacyPayloadError.unsupportedValue
        }
        return data
    }

    private static func upsert(
        table: String,
        id: String,
        sortDate: Date,
        data: Data,
        database: Database
    ) throws {
        let arguments: StatementArguments = [
            id,
            sortDate.timeIntervalSince1970,
            data
        ]
        try database.execute(
            sql: """
            INSERT INTO \(table)(id, sort_date, value)
            VALUES(?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                sort_date = excluded.sort_date,
                value = excluded.value
            """,
            arguments: arguments
        )
    }

    private static func upsertLocalFavorite(
        _ favorite: StoredLocalFavorite,
        folderID: String,
        data: Data,
        database: Database
    ) throws {
        let id = "\(favorite.platform.id)-\(favorite.id)"
        let timestamp = (favorite.favoriteDate ?? .distantPast).timeIntervalSince1970
        let arguments: StatementArguments = [
            folderID,
            id,
            timestamp,
            data
        ]
        try database.execute(
            sql: """
            INSERT INTO local_favorites(folder_id, id, sort_date, value)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(folder_id, id) DO UPDATE SET
                sort_date = excluded.sort_date,
                value = excluded.value
            """,
            arguments: arguments
        )
    }

    private static func isProcessed(
        _ sourceKey: String,
        digest: Data,
        database: PicaXSQLiteDatabase
    ) throws -> Bool {
        try database.dataRows(
            """
            SELECT payload_digest
            FROM legacy_user_data_migrations
            WHERE source_key = ?
            """,
            bindings: [.text(sourceKey)]
        ).first == digest
    }

    private static func markProcessed(
        _ sourceKey: String,
        digest: Data,
        discardedCount: Int,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO legacy_user_data_migrations(
                source_key,
                payload_digest,
                discarded_count,
                migrated_at
            )
            VALUES(?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                payload_digest = excluded.payload_digest,
                discarded_count = excluded.discarded_count,
                migrated_at = excluded.migrated_at
            """,
            arguments: [
                sourceKey,
                digest,
                discardedCount,
                Date().timeIntervalSince1970
            ]
        )
    }

    private static func payloadDigest(_ payload: Data) -> Data {
        Data(SHA256.hash(data: payload))
    }

    private static func mergeReadingHistory(
        legacy: ReadingHistoryRecord,
        current: ReadingHistoryRecord
    ) -> ReadingHistoryRecord {
        var merged = legacy.viewedAt > current.viewedAt ? legacy : current
        merged.viewedAt = max(legacy.viewedAt, current.viewedAt)
        merged.progress = mergeReadingProgress(
            legacy: legacy.progress,
            current: current.progress
        )
        return merged
    }

    private static func mergeReadingProgress(
        legacy: ReadingProgress?,
        current: ReadingProgress?
    ) -> ReadingProgress? {
        switch (legacy, current) {
        case (.none, .none):
            return nil
        case (.some(let value), .none), (.none, .some(let value)):
            return value
        case (.some(let legacy), .some(let current)):
            let older = legacy.updatedAt > current.updatedAt ? current : legacy
            var merged = legacy.updatedAt > current.updatedAt ? legacy : current
            merged.readChapterIndexes.formUnion(older.readChapterIndexes)
            merged.totalChapters = max(merged.totalChapters, older.totalChapters)
            if merged.totalPages <= 0 {
                merged.totalPages = older.totalPages
            }
            if merged.totalChapters > 0,
               merged.readChapterIndexes.count >= merged.totalChapters {
                merged.status = .finished
            }
            return merged
        }
    }

    private static func mergeReadingDuration(
        legacy: ReadingDurationRecord,
        current: ReadingDurationRecord
    ) -> ReadingDurationRecord {
        guard legacy != current else { return current }

        var merged = legacy.lastReadAt > current.lastReadAt ? legacy : current
        merged.lastReadAt = max(legacy.lastReadAt, current.lastReadAt)
        merged.totalSeconds = legacy.totalSeconds + current.totalSeconds
        var dailySeconds = legacy.dailySeconds
        for (day, seconds) in current.dailySeconds {
            dailySeconds[day, default: 0] += seconds
        }
        merged.dailySeconds = dailySeconds
        return merged
    }

    private static func mergeDownloadRecord(
        legacy: DownloadRecord,
        current: DownloadRecord
    ) -> DownloadRecord {
        let usesLegacyMetadata = legacy.updatedAt > current.updatedAt
        var merged = usesLegacyMetadata ? legacy : current
        let fallback = usesLegacyMetadata ? current : legacy

        var chaptersByIndex: [Int: DownloadedChapterRecord] = [:]
        for chapter in legacy.chapters + current.chapters {
            guard let existing = chaptersByIndex[chapter.index] else {
                chaptersByIndex[chapter.index] = chapter
                continue
            }
            var preferred = chapter.downloadedAt >= existing.downloadedAt
                ? chapter
                : existing
            let other = chapter.downloadedAt >= existing.downloadedAt
                ? existing
                : chapter
            if preferred.comments.isEmpty {
                preferred.comments = other.comments
            }
            chaptersByIndex[chapter.index] = preferred
        }

        merged.chapters = chaptersByIndex.values.sorted { $0.index < $1.index }
        merged.totalChapterCount = max(
            legacy.totalChapterCount,
            current.totalChapterCount
        )
        merged.totalBytes = merged.chapters.reduce(0) { $0 + $1.bytes }
        if merged.coverFileName == nil {
            merged.coverFileName = fallback.coverFileName
        }
        if merged.detail == nil {
            merged.detail = fallback.detail
        }
        if merged.comments.isEmpty {
            merged.comments = fallback.comments
        }
        if merged.directoryName.isEmpty {
            merged.directoryName = fallback.directoryName
        }
        merged.updatedAt = max(legacy.updatedAt, current.updatedAt)
        return merged
    }
}

@MainActor
struct AppDataMigrationCoordinator {
    init() {
        PicaXSQLiteStore.migrateLegacyUserDataAtAppLaunch()
    }
}

private enum LegacyPayloadError: Error {
    case unsupportedValue
    case invalidRecordCount(Int)
    case invalidFavoriteFolder
}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
    let values: [Element]
    let discardedCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        var discardedCount = 0

        while !container.isAtEnd {
            let elementDecoder = try container.superDecoder()
            do {
                values.append(try Element(from: elementDecoder))
            } catch {
                discardedCount += 1
            }
        }

        self.values = values
        self.discardedCount = discardedCount
    }
}

import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

extension UTType {
    nonisolated static let picaxBackup = UTType(exportedAs: "moye.picax.backup", conformingTo: .data)
    nonisolated static let picaComicBackup = UTType(importedAs: "moye.picacomic.backup", conformingTo: .data)
}

nonisolated enum BackupImportMode: Equatable, Sendable {
    case overwrite
    case merge
}

struct PicaXBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.picaxBackup] }
    static var writableContentTypes: [UTType] { [.picaxBackup] }

    private var data: Data
    var temporaryFileURL: URL?

    init(data: Data = Data()) {
        self.data = data
        temporaryFileURL = nil
    }

    init(temporaryFileURL: URL) {
        data = Data()
        self.temporaryFileURL = temporaryFileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        temporaryFileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let temporaryFileURL {
            return try FileWrapper(url: temporaryFileURL, options: [])
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct BackupImportPreview: Identifiable {
    let id = UUID()
    let backup: PicaXBackup
    let data: Data
    let sourceTitle: String

    init(backup: PicaXBackup, data: Data, sourceTitle: String = "PicaX 备份") {
        self.backup = backup
        self.data = data
        self.sourceTitle = sourceTitle
    }

    var title: String {
        sourceTitle
    }

    var subtitle: String {
        "\(backup.defaults.count) 项本地数据 · \(backup.downloadFiles.count) 个下载文件"
    }
}

struct BackupOperationResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

nonisolated struct PicaXBackup: Codable, Sendable {
    var formatVersion: Int
    var createdAt: Date
    var includedContent: [BackupContentKind]
    var defaults: [String: BackupDefaultValue]
    var downloadFiles: [BackupFile]

    var contentSelection: Set<BackupContentKind> {
        Set(includedContent)
    }

    init(
        formatVersion: Int,
        createdAt: Date,
        includedContent: [BackupContentKind],
        defaults: [String: BackupDefaultValue],
        downloadFiles: [BackupFile]
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.includedContent = includedContent
        self.defaults = defaults
        self.downloadFiles = downloadFiles
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case createdAt
        case includedContent
        case defaults
        case downloadFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        includedContent = try container.decode([BackupContentKind].self, forKey: .includedContent)
        defaults = try container.decodeIfPresent([String: BackupDefaultValue].self, forKey: .defaults) ?? [:]
        downloadFiles = try container.decodeIfPresent([BackupFile].self, forKey: .downloadFiles) ?? []
    }
}

nonisolated enum BackupContentKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case accounts
    case settings
    case favorites
    case readingHistory
    case readLater
    case readingDuration
    case searchHistory
    case blockingKeywords
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:
            "账号资料"
        case .settings:
            "应用设置"
        case .favorites:
            "本地收藏"
        case .readingHistory:
            "阅读历史"
        case .readLater:
            "稍后再读"
        case .readingDuration:
            "阅读时长"
        case .searchHistory:
            "搜索历史"
        case .blockingKeywords:
            "屏蔽词"
        case .downloads:
            "已下载漫画"
        }
    }

    static var defaultSelection: Set<BackupContentKind> {
        Set(allCases.filter { $0 != .accounts && $0 != .downloads })
    }
}

nonisolated struct BackupFile: Codable, Sendable {
    var relativePath: String
    var data: String? = nil
    var rawData: Data? = nil

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case data
    }
}

nonisolated struct BackupDefaultValue: Codable, Sendable {
    nonisolated enum ValueType: String, Codable, Sendable {
        case string
        case bool
        case int
        case double
        case stringArray
        case data
    }

    var type: ValueType
    var stringValue: String?
    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringArrayValue: [String]?
    var dataValue: String?

    static func from(_ value: Any) -> BackupDefaultValue? {
        switch value {
        case let value as String:
            BackupDefaultValue(type: .string, stringValue: value)
        case let value as Bool:
            BackupDefaultValue(type: .bool, boolValue: value)
        case let value as Int:
            BackupDefaultValue(type: .int, intValue: value)
        case let value as Double:
            BackupDefaultValue(type: .double, doubleValue: value)
        case let value as Float:
            BackupDefaultValue(type: .double, doubleValue: Double(value))
        case let value as [String]:
            BackupDefaultValue(type: .stringArray, stringArrayValue: value)
        case let value as Data:
            BackupDefaultValue(type: .data, dataValue: value.base64EncodedString())
        default:
            nil
        }
    }

    func userDefaultsValue() -> Any? {
        switch type {
        case .string:
            stringValue
        case .bool:
            boolValue
        case .int:
            intValue
        case .double:
            doubleValue
        case .stringArray:
            stringArrayValue
        case .data:
            dataValue.flatMap { Data(base64Encoded: $0) }
        }
    }

    func decodedData() -> Data? {
        guard case .data = type, let dataValue else { return nil }
        return Data(base64Encoded: dataValue)
    }

    private init(
        type: ValueType,
        stringValue: String? = nil,
        boolValue: Bool? = nil,
        intValue: Int? = nil,
        doubleValue: Double? = nil,
        stringArrayValue: [String]? = nil,
        dataValue: String? = nil
    ) {
        self.type = type
        self.stringValue = stringValue
        self.boolValue = boolValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.stringArrayValue = stringArrayValue
        self.dataValue = dataValue
    }
}

enum BackupService {
    private static let formatVersion = 2
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private static let valueEncoder = JSONEncoder()
    private static let valueDecoder = JSONDecoder()

    static func makeDocument(includedContent: Set<BackupContentKind>, defaults: UserDefaults = .standard) async throws -> PicaXBackupDocument {
        PicaXBackupDocument(
            temporaryFileURL: try await makeArchiveFile(
                includedContent: includedContent,
                defaults: defaults
            )
        )
    }

    static func makeArchiveFile(
        includedContent: Set<BackupContentKind>,
        defaults: UserDefaults = .standard
    ) async throws -> URL {
        let orderedContent = BackupContentKind.allCases.filter { includedContent.contains($0) }
        let includesDownloads = includedContent.contains(.downloads)
        let exportedDefaults = exportDefaults(includedContent: includedContent, defaults: defaults)
        let exportedDownloadFiles = includesDownloads ? try await exportDownloadFiles() : []
        let downloadFileRecords = exportedDownloadFiles.map { BackupFile(relativePath: $0.relativePath) }
        let backup = PicaXBackup(
            formatVersion: formatVersion,
            createdAt: Date(),
            includedContent: orderedContent,
            defaults: [:],
            downloadFiles: []
        )
        let backupMetadata = try encoder.encode(backup)
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaXBackup-\(UUID().uuidString)")
            .appendingPathExtension("picax")

        return try await Task.detached(priority: .utility) {
            do {
                let backupDatabase = try BackupSQLiteArchive.makeDatabase(
                    defaults: exportedDefaults,
                    downloadFiles: downloadFileRecords
                )
                let entries = [
                    StoredZipEntry(path: "backup.json", data: backupMetadata),
                    StoredZipEntry(path: BackupSQLiteArchive.fileName, data: backupDatabase)
                ]
                let fileEntries = exportedDownloadFiles.map { file in
                    StoredZipFileEntry(
                        path: BackupSQLiteArchive.downloadEntryPath(for: file.relativePath),
                        fileURL: file.fileURL,
                        size: file.size
                    )
                }
                try StoredZipArchive.makeArchive(
                    entries: entries,
                    fileEntries: fileEntries,
                    at: archiveURL
                )
                return archiveURL
            } catch {
                try? FileManager.default.removeItem(at: archiveURL)
                throw error
            }
        }.value
    }

    static func preview(from data: Data) throws -> BackupImportPreview {
        let backup = try decodeBackup(from: data)
        return BackupImportPreview(backup: backup, data: data)
    }

    static func importBackup(
        _ backup: PicaXBackup,
        mode: BackupImportMode,
        archiveData: Data? = nil,
        defaults: UserDefaults = .standard,
        postsNotification: Bool = true
    ) async throws {
        let plan = try makeImportPlan(for: backup, mode: mode, defaults: defaults)
        let downloadTransaction: DownloadFilesTransaction?
        if let downloadImport = plan.downloadImport {
            downloadTransaction = try await DownloadFilesTransaction.prepare(
                files: downloadImport.files,
                archiveData: archiveData,
                mode: downloadImport.mode
            )
        } else {
            downloadTransaction = nil
        }

        do {
            try await downloadTransaction?.commit()
            try PicaXSQLiteStore.applyRestoreOrThrow(plan.sqlite)
            for key in plan.defaultKeysToRemove {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in plan.defaults {
                defaults.set(value, forKey: key)
            }
            await downloadTransaction?.finalize()
        } catch {
            let importError = error
            do {
                try await downloadTransaction?.rollback()
            } catch {
                throw BackupArchiveError.rollbackFailed
            }
            throw importError
        }
        defaults.synchronize()
        if postsNotification {
            NotificationCenter.default.post(name: .picaxBackupDidImport, object: nil)
        }
    }

    static func importBackup(from data: Data, mode: BackupImportMode, defaults: UserDefaults = .standard) async throws {
        let decoded = try decodeBackup(from: data)
        try await importBackup(
            decoded,
            mode: mode,
            archiveData: data,
            defaults: defaults
        )
    }

    static func filteredBackup(_ backup: PicaXBackup, includedContent: Set<BackupContentKind>) -> PicaXBackup {
        let selectedContent = backup.contentSelection.intersection(includedContent)
        let orderedContent = BackupContentKind.allCases.filter { selectedContent.contains($0) }
        let defaults = backup.defaults.filter { key, _ in
            guard let contentKind = contentKind(for: key) else { return false }
            return selectedContent.contains(contentKind)
        }
        return PicaXBackup(
            formatVersion: backup.formatVersion,
            createdAt: backup.createdAt,
            includedContent: orderedContent,
            defaults: defaults,
            downloadFiles: selectedContent.contains(.downloads) ? backup.downloadFiles : []
        )
    }

    private static func decodeBackup(from data: Data) throws -> PicaXBackup {
        let entries = try StoredZipArchive.extractEntries(
            from: data,
            matching: ["backup.json", BackupSQLiteArchive.fileName]
        )
        let entryMap = entries.reduce(into: [String: Data]()) { result, entry in
            result[entry.path] = result[entry.path] ?? entry.data
        }
        guard let manifest = entryMap["backup.json"] else {
            throw BackupArchiveError.missingManifest
        }
        var backup = try decoder.decode(PicaXBackup.self, from: manifest)
        guard backup.formatVersion == formatVersion else {
            throw BackupArchiveError.unsupportedVersion(backup.formatVersion)
        }
        guard let database = entryMap[BackupSQLiteArchive.fileName] else {
            throw BackupArchiveError.missingManifest
        }
        let content = try BackupSQLiteArchive.readDatabase(database)
        backup.defaults = content.defaults
        backup.downloadFiles = content.downloadFiles
        return backup
    }

    @MainActor
    private static func exportDefaults(includedContent: Set<BackupContentKind>, defaults: UserDefaults) -> [String: BackupDefaultValue] {
        var values = defaults.dictionaryRepresentation().reduce(into: [String: BackupDefaultValue]()) { result, element in
            let key = element.key
            guard !isSQLiteBackedDataKey(key),
                  shouldExportKey(key, includedContent: includedContent),
                  let value = BackupDefaultValue.from(element.value) else {
                return
            }
            result[key] = value
        }
        appendSQLiteDefaults(to: &values, includedContent: includedContent)
        return values
    }

    @MainActor
    private static func makeImportPlan(
        for backup: PicaXBackup,
        mode: BackupImportMode,
        defaults: UserDefaults
    ) throws -> BackupImportPlan {
        let includedContent = backup.contentSelection
        var importedDefaults: [String: Any] = [:]
        for (key, value) in backup.defaults where !isSQLiteBackedDataKey(key) {
            guard key != "picax.accounts",
                  key != "picax.session",
                  let kind = contentKind(for: key),
                  includedContent.contains(kind) else {
                continue
            }
            switch mode {
            case .overwrite:
                guard let value = value.userDefaultsValue() else {
                    throw BackupArchiveError.invalidPayload(key)
                }
                importedDefaults[key] = value
            case .merge:
                guard let value = mergedDefaultValue(
                    key: key,
                    importedValue: value,
                    defaults: defaults
                ) else {
                    throw BackupArchiveError.invalidPayload(key)
                }
                importedDefaults[key] = value
            }
        }

        let keysToRemove: [String]
        switch mode {
        case .overwrite:
            keysToRemove = defaults.dictionaryRepresentation().keys.filter { key in
                guard isManagedKey(key),
                      !isSQLiteBackedDataKey(key),
                      key != "picax.accounts",
                      key != "picax.session",
                      backup.defaults[key] == nil else {
                    return false
                }
                return shouldRemoveMissingKey(key, includedContent: includedContent)
            }
        case .merge:
            keysToRemove = []
        }

        var sqlite = PicaXSQLiteRestorePayload()
        if includedContent.contains(.accounts) {
            let imported: [PlatformAccount] = try requiredArray(
                in: backup,
                key: "picax.platformAccounts",
                id: { $0.platform.id }
            )
            var local = PicaXSQLiteStore.loadPlatformAccounts()
            var didChangeAccounts = false
            for importedAccount in imported {
                if importedAccount.credential.hasSensitiveData {
                    if mode == .overwrite || local[importedAccount.platform] == nil {
                        local[importedAccount.platform] = importedAccount
                        didChangeAccounts = true
                    }
                } else if mode == .overwrite,
                          let localAccount = local[importedAccount.platform] {
                    var restoredAccount = importedAccount
                    restoredAccount.credential = importedAccount.credential
                        .removingSecrets()
                        .applying(localAccount.credential.secrets)
                    local[importedAccount.platform] = restoredAccount
                    didChangeAccounts = true
                }
            }
            if didChangeAccounts {
                sqlite.platformAccounts = ComicPlatform.onlinePlatforms.compactMap { local[$0] }
            }
        }
        if includedContent.contains(.favorites) {
            let imported: [StoredLocalFavorite] = try requiredArray(
                in: backup,
                key: "picax.localFavorites.default",
                id: { "\($0.platform.id)-\($0.id)" }
            )
            sqlite.localFavorites = mode == .overwrite
                ? imported.sorted(by: favoriteSort)
                : mergeNewest(
                    local: PicaXSQLiteStore.loadLocalFavorites(folderID: "default"),
                    imported: imported,
                    id: { "\($0.platform.id)-\($0.id)" },
                    date: { $0.favoriteDate ?? .distantPast }
                )
        }
        if includedContent.contains(.readingHistory) {
            let imported: [ReadingHistoryRecord] = try requiredArray(
                in: backup,
                key: ReadingHistoryService.Key.records,
                id: \.id
            )
            sqlite.readingHistory = mode == .overwrite
                ? imported.sorted { $0.viewedAt > $1.viewedAt }
                : mergeNewest(
                    local: PicaXSQLiteStore.loadReadingHistory(),
                    imported: imported,
                    id: \.id,
                    date: \.viewedAt
                )
        }
        if includedContent.contains(.readLater) {
            let imported: [ReadLaterRecord] = try requiredArray(
                in: backup,
                key: ReadLaterService.Key.records,
                id: \.id
            )
            sqlite.readLater = mode == .overwrite
                ? imported.sorted { $0.addedAt > $1.addedAt }
                : mergeNewest(
                    local: PicaXSQLiteStore.loadReadLater(),
                    imported: imported,
                    id: \.id,
                    date: \.addedAt
                )
        }
        if includedContent.contains(.readingDuration) {
            let imported: [ReadingDurationRecord] = try requiredArray(
                in: backup,
                key: ReadingDurationService.Key.records,
                id: \.id
            )
            sqlite.readingDuration = mode == .overwrite
                ? imported.sorted { $0.lastReadAt > $1.lastReadAt }
                : mergeReadingDurations(
                    local: PicaXSQLiteStore.loadReadingDuration(),
                    imported: imported
                )
        }
        if includedContent.contains(.searchHistory) {
            let imported: [SearchHistoryRecord] = try requiredArray(
                in: backup,
                key: SearchHistorySettingsKey.records,
                id: \.id
            )
            sqlite.searchHistory = mode == .overwrite
                ? imported.sorted { $0.searchedAt > $1.searchedAt }
                : mergeNewest(
                    local: PicaXSQLiteStore.loadSearchHistory(),
                    imported: imported,
                    id: \.id,
                    date: \.searchedAt
                )
        }
        if includedContent.contains(.downloads) {
            let imported: [DownloadRecord] = try requiredArray(
                in: backup,
                key: DownloadSettingsKey.records,
                id: \.id
            )
            sqlite.downloadRecords = mode == .overwrite
                ? imported.sorted { $0.updatedAt > $1.updatedAt }
                : mergeNewest(
                    local: PicaXSQLiteStore.loadDownloadRecords(),
                    imported: imported,
                    id: \.id,
                    date: \.updatedAt
                )
        }

        return BackupImportPlan(
            defaults: importedDefaults,
            defaultKeysToRemove: keysToRemove,
            sqlite: sqlite,
            downloadImport: includedContent.contains(.downloads)
                ? BackupDownloadImport(files: backup.downloadFiles, mode: mode)
                : nil
        )
    }

    private static func requiredArray<Value: Decodable>(
        in backup: PicaXBackup,
        key: String,
        id: (Value) -> String
    ) throws -> [Value] {
        guard let encodedValue = backup.defaults[key],
              let data = encodedValue.decodedData() else {
            throw BackupArchiveError.invalidPayload(key)
        }
        let values: [Value]
        do {
            values = try valueDecoder.decode([Value].self, from: data)
        } catch {
            throw BackupArchiveError.invalidPayload(key)
        }
        var seen = Set<String>()
        guard values.allSatisfy({ seen.insert(id($0)).inserted }) else {
            throw BackupArchiveError.invalidPayload(key)
        }
        return values
    }

    private static func mergeNewest<Value>(
        local: [Value],
        imported: [Value],
        id: (Value) -> String,
        date: (Value) -> Date
    ) -> [Value] {
        var result: [String: Value] = [:]
        for value in imported + local {
            let key = id(value)
            guard let existing = result[key] else {
                result[key] = value
                continue
            }
            if date(value) >= date(existing) {
                result[key] = value
            }
        }
        return result.values.sorted { date($0) > date($1) }
    }

    private static func mergeReadingDurations(
        local: [ReadingDurationRecord],
        imported: [ReadingDurationRecord]
    ) -> [ReadingDurationRecord] {
        var result: [String: ReadingDurationRecord] = [:]
        for record in imported + local {
            guard var existing = result[record.id] else {
                result[record.id] = record
                continue
            }
            if record.lastReadAt > existing.lastReadAt {
                existing.item = record.item
                existing.lastReadAt = record.lastReadAt
            }
            existing.totalSeconds = max(existing.totalSeconds, record.totalSeconds)
            for (day, seconds) in record.dailySeconds {
                existing.dailySeconds[day] = max(existing.dailySeconds[day] ?? 0, seconds)
            }
            result[record.id] = existing
        }
        return result.values.sorted { $0.lastReadAt > $1.lastReadAt }
    }

    private static func favoriteSort(
        _ lhs: StoredLocalFavorite,
        _ rhs: StoredLocalFavorite
    ) -> Bool {
        (lhs.favoriteDate ?? .distantPast) > (rhs.favoriteDate ?? .distantPast)
    }

    @MainActor
    private static func appendSQLiteDefaults(to values: inout [String: BackupDefaultValue], includedContent: Set<BackupContentKind>) {
        if includedContent.contains(.accounts) {
            let accounts = PicaXSQLiteStore.loadPlatformAccounts()
            let redactedAccounts = ComicPlatform.onlinePlatforms.compactMap { platform -> PlatformAccount? in
                guard var account = accounts[platform] else { return nil }
                account.credential = account.credential.removingSecrets()
                return account
            }
            if let data = encodeValue(redactedAccounts) {
                values["picax.platformAccounts"] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.favorites) {
            if let data = encodeValue(PicaXSQLiteStore.loadLocalFavorites(folderID: "default")) {
                values["picax.localFavorites.default"] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.readingHistory) {
            if let data = encodeValue(PicaXSQLiteStore.loadReadingHistory()) {
                values[ReadingHistoryService.Key.records] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.readLater) {
            if let data = encodeValue(PicaXSQLiteStore.loadReadLater()) {
                values[ReadLaterService.Key.records] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.readingDuration) {
            if let data = encodeValue(PicaXSQLiteStore.loadReadingDuration()) {
                values[ReadingDurationService.Key.records] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.searchHistory) {
            if let data = encodeValue(PicaXSQLiteStore.loadSearchHistory()) {
                values[SearchHistorySettingsKey.records] = BackupDefaultValue.from(data)
            }
        }
        if includedContent.contains(.downloads) {
            if let data = encodeValue(PicaXSQLiteStore.loadDownloadRecords()) {
                values[DownloadSettingsKey.records] = BackupDefaultValue.from(data)
            }
        }
    }

    private static func encodeValue<Value: Encodable>(_ value: Value) -> Data? {
        try? valueEncoder.encode(value)
    }

    private static func isSQLiteBackedDataKey(_ key: String) -> Bool {
        key == "picax.platformAccounts"
            || key == "picax.localFavorites.default"
            || key == ReadingHistoryService.Key.records
            || key == ReadLaterService.Key.records
            || key == ReadingDurationService.Key.records
            || key == SearchHistorySettingsKey.records
            || key == DownloadSettingsKey.records
    }

    private static func shouldExportKey(_ key: String, includedContent: Set<BackupContentKind>) -> Bool {
        if key == DownloadSettingsKey.tasks
            || key == "picax.accounts"
            || key == "picax.session" {
            return false
        }
        guard let contentKind = contentKind(for: key) else { return false }
        return includedContent.contains(contentKind)
    }

    private static func isManagedKey(_ key: String) -> Bool {
        key.hasPrefix("picax.") || key.hasPrefix("settings.")
    }

    private static func shouldRemoveMissingKey(_ key: String, includedContent: Set<BackupContentKind>) -> Bool {
        guard key != DownloadSettingsKey.tasks,
              let contentKind = contentKind(for: key) else { return false }
        return includedContent.contains(contentKind)
    }

    private static func contentKind(for key: String) -> BackupContentKind? {
        if key.hasPrefix("settings.webDAV.") || key.hasPrefix("settings.appLock.") {
            return nil
        }
        if key == "picax.accounts" || key == "picax.session" || key == "picax.platformAccounts" {
            return .accounts
        }
        if key == DownloadSettingsKey.records {
            return .downloads
        }
        if key == ReadingHistoryService.Key.records {
            return .readingHistory
        }
        if key == ReadLaterService.Key.records {
            return .readLater
        }
        if key == ReadingDurationService.Key.records {
            return .readingDuration
        }
        if key == SearchHistorySettingsKey.records {
            return .searchHistory
        }
        if key == BlockingKeywordSettingsKey.common || key == BlockingKeywordSettingsKey.jmComic
            || key == BlockingKeywordSettingsKey.common + ".disabled" || key == BlockingKeywordSettingsKey.jmComic + ".disabled" {
            return .blockingKeywords
        }
        if key.hasPrefix("picax.localFavorites.") {
            return .favorites
        }
        if key.hasPrefix("settings.") || key.hasPrefix("picax.") {
            return .settings
        }
        return nil
    }

    private static func mergedDefaultValue(key: String, importedValue: BackupDefaultValue, defaults: UserDefaults) -> Any? {
        guard let existingValue = defaults.object(forKey: key) else {
            return importedValue.userDefaultsValue()
        }

        if key == BlockingKeywordSettingsKey.common || key == BlockingKeywordSettingsKey.jmComic {
            return uniqueStrings((existingValue as? [String] ?? []) + (importedValue.stringArrayValue ?? []))
        }

        if let existing = existingValue as? Data, let imported = importedValue.decodedData() {
            switch key {
            case SavedComicSearch.storageKey:
                return StoredCollection<SavedComicSearch>.merging(existing: existing, imported: imported) ?? existing
            case ComicPageBookmark.storageKey:
                return StoredCollection<ComicPageBookmark>.merging(existing: existing, imported: imported) ?? existing
            case ComicVersionOverride.storageKey:
                return StoredCollection<ComicVersionOverride>.merging(existing: existing, imported: imported) ?? existing
            default: break
            }
        }
        return existingValue
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func exportDownloadFiles() async throws -> [ExportedBackupFile] {
        try await Task.detached(priority: .utility) {
            let rootURL = try downloadsRootURL()
            guard FileManager.default.fileExists(atPath: rootURL.path),
                  let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            let rootPrefix = rootURL.standardizedFileURL.path + "/"
            var files: [ExportedBackupFile] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let standardizedURL = fileURL.standardizedFileURL
                let values = try standardizedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      standardizedURL.path.hasPrefix(rootPrefix) else {
                    continue
                }
                let relativePath = String(standardizedURL.path.dropFirst(rootPrefix.count))
                guard isSafeRelativePath(relativePath) else {
                    throw BackupArchiveError.invalidPath
                }
                files.append(ExportedBackupFile(
                    relativePath: relativePath,
                    fileURL: standardizedURL,
                    size: UInt64(values.fileSize ?? 0)
                ))
            }
            return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }.value
    }

    fileprivate nonisolated static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.split(separator: "/").contains("..")
    }

    fileprivate nonisolated static func downloadsRootURL() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ComicContentError.invalidResponse("无法访问应用支持目录。")
        }
        return baseURL
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }
}

private struct BackupImportPlan {
    var defaults: [String: Any]
    var defaultKeysToRemove: [String]
    var sqlite: PicaXSQLiteRestorePayload
    var downloadImport: BackupDownloadImport?
}

private struct BackupDownloadImport {
    var files: [BackupFile]
    var mode: BackupImportMode
}

nonisolated private enum DownloadImportTransactionRegistry {
    private static let transactionPrefix = ".PicaXBackupImport-"
    private static let stagedDirectoryName = "StagedDownloads"
    private static let previousDirectoryName = "PreviousDownloads"
    private static let commitMarkerName = "CommitStarted"
    private static let completionMarkerName = "RestoreCommitted"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var activePaths = Set<String>()

    static func createRoot(parent: URL, liveRoot: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try recoverInterruptedTransactions(
            parent: parent,
            liveRoot: liveRoot,
            excluding: activePaths
        )
        let root = parent.appendingPathComponent(
            "\(transactionPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        activePaths.insert(root.path)
        return root
    }

    static func unregister(_ root: URL) {
        lock.lock()
        activePaths.remove(root.path)
        lock.unlock()
    }

    private static func recoverInterruptedTransactions(
        parent: URL,
        liveRoot: URL,
        excluding activePaths: Set<String>
    ) throws {
        let fileManager = FileManager.default
        let candidates = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        .filter {
            guard $0.lastPathComponent.hasPrefix(transactionPrefix),
                  !activePaths.contains($0.path) else {
                return false
            }
            return (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        for root in candidates {
            let completionMarker = root.appendingPathComponent(completionMarkerName)
            if fileManager.fileExists(atPath: completionMarker.path) {
                try fileManager.removeItem(at: root)
                continue
            }

            let previousRoot = root.appendingPathComponent(previousDirectoryName, isDirectory: true)
            let stagedRoot = root.appendingPathComponent(stagedDirectoryName, isDirectory: true)
            let commitMarker = root.appendingPathComponent(commitMarkerName)
            if fileManager.fileExists(atPath: previousRoot.path) {
                if fileManager.fileExists(atPath: liveRoot.path) {
                    try fileManager.removeItem(at: liveRoot)
                }
                try fileManager.moveItem(at: previousRoot, to: liveRoot)
            } else if fileManager.fileExists(atPath: commitMarker.path),
                      !fileManager.fileExists(atPath: stagedRoot.path),
                      fileManager.fileExists(atPath: liveRoot.path) {
                try fileManager.removeItem(at: liveRoot)
            }
            try fileManager.removeItem(at: root)
        }
    }

    static func commitMarker(in root: URL) -> URL {
        root.appendingPathComponent(commitMarkerName)
    }

    static func completionMarker(in root: URL) -> URL {
        root.appendingPathComponent(completionMarkerName)
    }
}

private actor DownloadFilesTransaction {
    private let transactionRoot: URL
    private let stagedRoot: URL
    private let liveRoot: URL
    private let previousRoot: URL
    private var didCommit = false

    private init(transactionRoot: URL, stagedRoot: URL, liveRoot: URL, previousRoot: URL) {
        self.transactionRoot = transactionRoot
        self.stagedRoot = stagedRoot
        self.liveRoot = liveRoot
        self.previousRoot = previousRoot
    }

    static func prepare(
        files: [BackupFile],
        archiveData: Data?,
        mode: BackupImportMode
    ) async throws -> DownloadFilesTransaction {
        let urls = try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let liveRoot = try BackupService.downloadsRootURL()
            let parent = liveRoot.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let transactionRoot = try DownloadImportTransactionRegistry.createRoot(
                parent: parent,
                liveRoot: liveRoot
            )
            let stagedRoot = transactionRoot.appendingPathComponent("StagedDownloads", isDirectory: true)
            let previousRoot = transactionRoot.appendingPathComponent("PreviousDownloads", isDirectory: true)

            do {
                if mode == .merge, fileManager.fileExists(atPath: liveRoot.path) {
                    try fileManager.copyItem(at: liveRoot, to: stagedRoot)
                } else {
                    try fileManager.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
                }

                let stagedPrefix = stagedRoot.standardizedFileURL.path + "/"
                var archivedFileDestinations = [String: URL]()
                for file in files {
                    guard BackupService.isSafeRelativePath(file.relativePath) else {
                        throw BackupArchiveError.invalidPath
                    }
                    let target = stagedRoot
                        .appendingPathComponent(file.relativePath, isDirectory: false)
                        .standardizedFileURL
                    guard target.path.hasPrefix(stagedPrefix) else {
                        throw BackupArchiveError.invalidPath
                    }
                    if mode == .merge, fileManager.fileExists(atPath: target.path) {
                        continue
                    }
                    if let data = file.rawData ?? file.data.flatMap({ Data(base64Encoded: $0) }) {
                        try fileManager.createDirectory(
                            at: target.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try data.write(to: target, options: .atomic)
                    } else {
                        archivedFileDestinations[
                            BackupSQLiteArchive.downloadEntryPath(for: file.relativePath)
                        ] = target
                    }
                }

                if !archivedFileDestinations.isEmpty {
                    guard let archiveData else {
                        throw BackupArchiveError.missingDownloadFile(
                            archivedFileDestinations.keys.sorted().first ?? "downloads"
                        )
                    }
                    try StoredZipArchive.extractEntries(
                        from: archiveData,
                        to: archivedFileDestinations
                    )
                }
            } catch {
                try? fileManager.removeItem(at: transactionRoot)
                DownloadImportTransactionRegistry.unregister(transactionRoot)
                throw error
            }
            return (transactionRoot, stagedRoot, liveRoot, previousRoot)
        }.value

        return DownloadFilesTransaction(
            transactionRoot: urls.0,
            stagedRoot: urls.1,
            liveRoot: urls.2,
            previousRoot: urls.3
        )
    }

    func commit() async throws {
        let transactionRoot = transactionRoot
        let stagedRoot = stagedRoot
        let liveRoot = liveRoot
        let previousRoot = previousRoot
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try Data().write(
                to: DownloadImportTransactionRegistry.commitMarker(in: transactionRoot),
                options: .atomic
            )
            if fileManager.fileExists(atPath: liveRoot.path) {
                try fileManager.moveItem(at: liveRoot, to: previousRoot)
            }
            try fileManager.moveItem(at: stagedRoot, to: liveRoot)
        }.value
        didCommit = true
    }

    func rollback() async throws {
        let transactionRoot = transactionRoot
        let liveRoot = liveRoot
        let previousRoot = previousRoot
        let didCommit = didCommit
        do {
            try await Task.detached(priority: .utility) {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: previousRoot.path) {
                    if fileManager.fileExists(atPath: liveRoot.path) {
                        try fileManager.removeItem(at: liveRoot)
                    }
                    try fileManager.moveItem(at: previousRoot, to: liveRoot)
                } else if didCommit, fileManager.fileExists(atPath: liveRoot.path) {
                    try fileManager.removeItem(at: liveRoot)
                }
                if fileManager.fileExists(atPath: transactionRoot.path) {
                    try fileManager.removeItem(at: transactionRoot)
                }
            }.value
        } catch {
            DownloadImportTransactionRegistry.unregister(transactionRoot)
            throw error
        }
        DownloadImportTransactionRegistry.unregister(transactionRoot)
    }

    func finalize() async {
        let transactionRoot = transactionRoot
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try? Data().write(
                to: DownloadImportTransactionRegistry.completionMarker(in: transactionRoot),
                options: .atomic
            )
            try? fileManager.removeItem(at: transactionRoot)
        }.value
        DownloadImportTransactionRegistry.unregister(transactionRoot)
    }
}

nonisolated private struct ExportedBackupFile: Sendable {
    var relativePath: String
    var fileURL: URL
    var size: UInt64
}

private struct BackupSQLiteContent {
    var defaults: [String: BackupDefaultValue]
    var downloadFiles: [BackupFile]
}

nonisolated private enum BackupSQLiteArchive {
    static let fileName = "data.sqlite3"

    static func downloadEntryPath(for relativePath: String) -> String {
        "downloads/\(relativePath)"
    }

    static func makeDatabase(defaults: [String: BackupDefaultValue], downloadFiles: [BackupFile]) throws -> Data {
        let url = temporaryDatabaseURL()
        try? FileManager.default.removeItem(at: url)
        defer {
            removeDatabaseFiles(for: url)
        }

        var queue: DatabaseQueue? = try DatabaseQueue(path: url.path)
        try queue?.write { database in
            try database.create(table: "defaults") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .blob).notNull()
            }
            try database.create(table: "download_files") { table in
                table.column("relative_path", .text).primaryKey()
            }

            for (key, value) in defaults.sorted(by: { $0.key < $1.key }) {
                try database.execute(
                    sql: "INSERT INTO defaults(key, value) VALUES(?, ?)",
                    arguments: [key, try JSONEncoder().encode(value)]
                )
            }
            for file in downloadFiles.sorted(by: { $0.relativePath < $1.relativePath }) {
                try database.execute(
                    sql: "INSERT INTO download_files(relative_path) VALUES(?)",
                    arguments: [file.relativePath]
                )
            }
        }
        queue = nil
        return try Data(contentsOf: url)
    }

    static func readDatabase(_ data: Data) throws -> BackupSQLiteContent {
        let url = temporaryDatabaseURL()
        try? FileManager.default.removeItem(at: url)
        defer {
            removeDatabaseFiles(for: url)
        }
        try data.write(to: url, options: .atomic)

        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        return try queue.read { database in
            let defaultRows = try Row.fetchAll(
                database,
                sql: "SELECT key, value FROM defaults"
            )
            var defaults: [String: BackupDefaultValue] = [:]
            for row in defaultRows {
                let key: String = row["key"]
                let data: Data = row["value"]
                guard defaults[key] == nil else {
                    throw BackupArchiveError.duplicateEntry
                }
                defaults[key] = try JSONDecoder().decode(BackupDefaultValue.self, from: data)
            }

            let paths = try String.fetchAll(
                database,
                sql: "SELECT relative_path FROM download_files ORDER BY relative_path"
            )
            guard Set(paths).count == paths.count else {
                throw BackupArchiveError.duplicateEntry
            }
            return BackupSQLiteContent(
                defaults: defaults,
                downloadFiles: paths.map { BackupFile(relativePath: $0) }
            )
        }
    }

    private static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaXBackup-\(UUID().uuidString)")
            .appendingPathExtension("sqlite3")
    }

    private static func removeDatabaseFiles(for url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}

nonisolated struct StoredZipEntry: Sendable {
    var path: String
    var data: Data
}

nonisolated struct StoredZipFileEntry: Sendable {
    var path: String
    var fileURL: URL
    var size: UInt64
}

nonisolated enum StoredZipArchive {
    private static let maximumEntryCount = 10_000
    private static let maximumEntryBytes: UInt64 = 512 * 1024 * 1024
    private static let maximumTotalBytes: UInt64 = 8 * 1024 * 1024 * 1024
    private static let maximumCompressionRatio: UInt64 = 200
    private static let extractionBufferSize = 64 * 1024

    static func makeArchive(
        entries: [StoredZipEntry],
        fileEntries: [StoredZipFileEntry] = []
    ) throws -> Data {
        let archive = try Archive(accessMode: .create)
        try populate(archive, entries: entries, fileEntries: fileEntries)
        guard let data = archive.data else {
            throw BackupArchiveError.invalidArchive
        }
        return data
    }

    static func makeArchive(
        entries: [StoredZipEntry],
        fileEntries: [StoredZipFileEntry] = [],
        at destinationURL: URL
    ) throws {
        do {
            let archive = try Archive(url: destinationURL, accessMode: .create)
            try populate(archive, entries: entries, fileEntries: fileEntries)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func populate(
        _ archive: Archive,
        entries: [StoredZipEntry],
        fileEntries: [StoredZipFileEntry]
    ) throws {
        guard entries.count + fileEntries.count <= maximumEntryCount else {
            throw BackupArchiveError.tooManyEntries
        }
        var seenPaths = Set<String>()
        var totalBytes: UInt64 = 0
        for entry in entries {
            try validate(path: entry.path)
            guard seenPaths.insert(entry.path).inserted else {
                throw BackupArchiveError.duplicateEntry
            }
            let entrySize = UInt64(entry.data.count)
            guard entrySize <= maximumEntryBytes,
                  totalBytes <= maximumTotalBytes - entrySize else {
                throw BackupArchiveError.entryTooLarge
            }
            totalBytes += entrySize
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entry.data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let lowerBound = Int(position)
                    let upperBound = min(lowerBound + size, entry.data.count)
                    guard lowerBound >= 0, lowerBound <= upperBound else {
                        throw BackupArchiveError.invalidArchive
                    }
                    return entry.data.subdata(in: lowerBound..<upperBound)
                }
            )
        }
        for entry in fileEntries {
            try validate(path: entry.path)
            guard seenPaths.insert(entry.path).inserted else {
                throw BackupArchiveError.duplicateEntry
            }
            guard entry.size <= maximumEntryBytes,
                  totalBytes <= maximumTotalBytes - entry.size else {
                throw BackupArchiveError.entryTooLarge
            }
            totalBytes += entry.size

            let handle = try FileHandle(forReadingFrom: entry.fileURL)
            do {
                try archive.addEntry(
                    with: entry.path,
                    type: .file,
                    uncompressedSize: Int64(entry.size),
                    compressionMethod: .deflate,
                    provider: { position, size in
                        try handle.seek(toOffset: UInt64(position))
                        return try handle.read(upToCount: size) ?? Data()
                    }
                )
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    static func extractEntry(named path: String, from archive: Data) throws -> Data? {
        try extractEntries(from: archive, matching: [path]).first?.data
    }

    static func extractEntries(
        from archive: Data,
        matching paths: Set<String>? = nil
    ) throws -> [StoredZipEntry] {
        let zip = try Archive(data: archive, accessMode: .read)
        let entries = try limitedEntries(in: zip)
        try validate(entries: entries)
        return try entries.compactMap { entry in
            guard entry.type == .file,
                  paths?.contains(entry.path) ?? true else {
                return nil
            }
            var data = Data()
            data.reserveCapacity(Int(entry.uncompressedSize))
            _ = try zip.extract(
                entry,
                bufferSize: extractionBufferSize,
                skipCRC32: false
            ) { chunk in
                guard data.count <= Int(Self.maximumEntryBytes) - chunk.count else {
                    throw BackupArchiveError.entryTooLarge
                }
                data.append(chunk)
            }
            return StoredZipEntry(path: entry.path, data: data)
        }
    }

    static func extractEntries(
        from archive: Data,
        to destinations: [String: URL]
    ) throws {
        guard !destinations.isEmpty else { return }
        let zip = try Archive(data: archive, accessMode: .read)
        let entries = try limitedEntries(in: zip)
        try validate(entries: entries)
        let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })

        for path in destinations.keys.sorted() {
            guard let destination = destinations[path],
                  let entry = entriesByPath[path],
                  entry.type == .file else {
                let relativePath = path.hasPrefix("downloads/")
                    ? String(path.dropFirst("downloads/".count))
                    : path
                throw BackupArchiveError.missingDownloadFile(relativePath)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporaryURL = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).part")
            guard FileManager.default.createFile(
                atPath: temporaryURL.path,
                contents: nil
            ) else {
                throw BackupArchiveError.invalidArchive
            }
            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                _ = try zip.extract(
                    entry,
                    bufferSize: extractionBufferSize,
                    skipCRC32: false
                ) { chunk in
                    try handle.write(contentsOf: chunk)
                }
                try handle.close()
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    private static func limitedEntries(in archive: Archive) throws -> [Entry] {
        var entries = [Entry]()
        entries.reserveCapacity(min(maximumEntryCount, 256))
        for entry in archive {
            guard entries.count < maximumEntryCount else {
                throw BackupArchiveError.tooManyEntries
            }
            entries.append(entry)
        }
        return entries
    }

    private static func validate(entries: [Entry]) throws {
        guard entries.count <= maximumEntryCount else {
            throw BackupArchiveError.tooManyEntries
        }
        var paths = Set<String>()
        var totalBytes: UInt64 = 0
        for entry in entries {
            try validate(path: entry.path)
            guard paths.insert(entry.path).inserted else {
                throw BackupArchiveError.duplicateEntry
            }
            let size = entry.uncompressedSize
            guard size <= maximumEntryBytes,
                  totalBytes <= maximumTotalBytes - size else {
                throw BackupArchiveError.entryTooLarge
            }
            totalBytes += size
            if size > 0 {
                guard entry.compressedSize > 0,
                      size / max(entry.compressedSize, 1) <= maximumCompressionRatio else {
                    throw BackupArchiveError.suspiciousCompressionRatio
                }
            }
        }
    }

    private static func validate(path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else {
            throw BackupArchiveError.invalidPath
        }
    }

}

nonisolated enum BackupArchiveError: LocalizedError {
    case invalidPath
    case entryTooLarge
    case tooManyEntries
    case duplicateEntry
    case suspiciousCompressionRatio
    case invalidArchive
    case missingManifest
    case unsupportedVersion(Int)
    case unsupportedCompression
    case sqliteFailure
    case invalidPayload(String)
    case missingDownloadFile(String)
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "备份文件路径无效。"
        case .entryTooLarge:
            "备份内容过大，无法导出。"
        case .tooManyEntries:
            "备份文件包含过多条目。"
        case .duplicateEntry:
            "备份文件包含重复条目。"
        case .suspiciousCompressionRatio:
            "备份文件的压缩比例异常。"
        case .invalidArchive:
            "备份文件已损坏。"
        case .missingManifest:
            "这不是可导入的 PicaX 备份。"
        case .unsupportedVersion(let version):
            "不支持此备份格式版本（\(version)）。"
        case .unsupportedCompression:
            "暂不支持此备份压缩格式。"
        case .sqliteFailure:
            "备份数据写入失败。"
        case .invalidPayload(let key):
            "备份中的数据项“\(key)”已损坏或缺失。"
        case .missingDownloadFile(let path):
            "备份缺少下载文件“\(path)”。"
        case .rollbackFailed:
            "恢复失败，且原下载目录未能自动还原；临时恢复目录已保留，请勿继续导入。"
        }
    }
}

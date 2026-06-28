import Foundation
import SQLite3
import SwiftUI
import UniformTypeIdentifiers
import zlib

private let backupSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension UTType {
    static let picaxBackup = UTType(exportedAs: "moye.picax.backup", conformingTo: .data)
    static let picaComicBackup = UTType(importedAs: "moye.picacomic.backup", conformingTo: .data)
}

enum BackupImportMode {
    case overwrite
    case merge
}

struct PicaXBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.picaxBackup] }
    static var writableContentTypes: [UTType] { [.picaxBackup] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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

struct PicaXBackup: Codable {
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

enum BackupContentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case accounts
    case settings
    case favorites
    case readingHistory
    case readingDuration
    case searchHistory
    case blockingKeywords
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:
            "账号和登录状态"
        case .settings:
            "应用设置"
        case .favorites:
            "本地收藏"
        case .readingHistory:
            "阅读历史"
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

    var summary: String {
        switch self {
        case .accounts:
            "已登录账号和平台账号"
        case .settings:
            "外观、首页、搜索、来源等设置"
        case .favorites:
            "本地收藏夹内容"
        case .readingHistory:
            "阅读记录和进度"
        case .readingDuration:
            "阅读时长统计"
        case .searchHistory:
            "搜索记录"
        case .blockingKeywords:
            "通用和平台屏蔽词"
        case .downloads:
            "下载记录和本地文件"
        }
    }

    static var defaultSelection: Set<BackupContentKind> {
        Set(allCases.filter { $0 != .downloads })
    }
}

struct BackupFile: Codable {
    var relativePath: String
    var data: String? = nil
    var rawData: Data? = nil

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case data
    }
}

struct BackupDefaultValue: Codable {
    enum ValueType: String, Codable {
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
        let backupDatabase = try BackupSQLiteArchive.makeDatabase(defaults: exportedDefaults, downloadFiles: downloadFileRecords)
        var entries = [
            StoredZipEntry(path: "backup.json", data: try encoder.encode(backup)),
            StoredZipEntry(path: BackupSQLiteArchive.fileName, data: backupDatabase)
        ]
        entries += exportedDownloadFiles.map { file in
            StoredZipEntry(path: BackupSQLiteArchive.downloadEntryPath(for: file.relativePath), data: file.data)
        }
        let data = try StoredZipArchive.makeArchive(entries: entries)
        return PicaXBackupDocument(data: data)
    }

    static func preview(from data: Data) throws -> BackupImportPreview {
        let backup = try decodeBackup(from: data)
        return BackupImportPreview(backup: backup, data: data)
    }

    static func importBackup(_ backup: PicaXBackup, mode: BackupImportMode, defaults: UserDefaults = .standard) async throws {
        switch mode {
        case .overwrite:
            try await overwrite(with: backup, defaults: defaults)
        case .merge:
            try await merge(with: backup, defaults: defaults)
        }
        defaults.synchronize()
    }

    static func importBackup(from data: Data, mode: BackupImportMode, defaults: UserDefaults = .standard) async throws {
        let backup = try decodeBackup(from: data)
        try await importBackup(backup, mode: mode, defaults: defaults)
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
        let entries = try StoredZipArchive.extractEntries(from: data)
        let entryMap = entries.reduce(into: [String: Data]()) { result, entry in
            result[entry.path] = result[entry.path] ?? entry.data
        }
        guard let manifest = entryMap["backup.json"] else {
            throw BackupArchiveError.missingManifest
        }
        var backup = try decoder.decode(PicaXBackup.self, from: manifest)
        guard let database = entryMap[BackupSQLiteArchive.fileName] else {
            throw BackupArchiveError.missingManifest
        }
        let content = try BackupSQLiteArchive.readDatabase(database)
        backup.defaults = content.defaults
        backup.downloadFiles = content.downloadFiles.map { file in
            var file = file
            if let data = entryMap[BackupSQLiteArchive.downloadEntryPath(for: file.relativePath)] {
                file.rawData = data
            }
            return file
        }
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

    private static func overwrite(with backup: PicaXBackup, defaults: UserDefaults) async throws {
        let includedContent = backup.contentSelection
        let currentKeys = defaults.dictionaryRepresentation().keys.filter { isManagedKey($0) }
        for key in currentKeys where backup.defaults[key] == nil && shouldRemoveMissingKey(key, includedContent: includedContent) {
            defaults.removeObject(forKey: key)
        }

        for (key, value) in backup.defaults {
            if isSQLiteBackedDataKey(key) { continue }
            guard let defaultsValue = value.userDefaultsValue() else { continue }
            defaults.set(defaultsValue, forKey: key)
        }

        applySQLiteBackupValues(backup)

        if includedContent.contains(.downloads) {
            try await replaceDownloadFiles(with: backup.downloadFiles)
        }
    }

    private static func merge(with backup: PicaXBackup, defaults: UserDefaults) async throws {
        for (key, importedValue) in backup.defaults {
            if mergeSQLiteBackupValue(key: key, importedValue: importedValue) {
                continue
            }
            if let mergedValue = mergedDefaultValue(key: key, importedValue: importedValue, defaults: defaults) {
                defaults.set(mergedValue, forKey: key)
            }
        }

        if backup.contentSelection.contains(.downloads) {
            try await mergeDownloadFiles(backup.downloadFiles)
        }
    }

    @MainActor
    private static func appendSQLiteDefaults(to values: inout [String: BackupDefaultValue], includedContent: Set<BackupContentKind>) {
        if includedContent.contains(.accounts) {
            let accounts = PicaXSQLiteStore.loadPlatformAccounts()
            if let data = encodeValue(ComicPlatform.allCases.compactMap { accounts[$0] }) {
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

    @MainActor
    private static func applySQLiteBackupValues(_ backup: PicaXBackup) {
        let content = backup.contentSelection
        if content.contains(.accounts) {
            replaceSQLiteValue(
                backup.defaults["picax.platformAccounts"],
                as: PlatformAccount.self,
                replace: PicaXSQLiteStore.replacePlatformAccounts
            )
        }
        if content.contains(.favorites) {
            replaceSQLiteValue(
                backup.defaults["picax.localFavorites.default"],
                as: StoredLocalFavorite.self
            ) { PicaXSQLiteStore.replaceLocalFavorites($0, folderID: "default") }
        }
        if content.contains(.readingHistory) {
            replaceSQLiteValue(
                backup.defaults[ReadingHistoryService.Key.records],
                as: ReadingHistoryRecord.self,
                replace: PicaXSQLiteStore.replaceReadingHistory
            )
        }
        if content.contains(.readingDuration) {
            replaceSQLiteValue(
                backup.defaults[ReadingDurationService.Key.records],
                as: ReadingDurationRecord.self,
                replace: PicaXSQLiteStore.replaceReadingDuration
            )
        }
        if content.contains(.searchHistory) {
            replaceSQLiteValue(
                backup.defaults[SearchHistorySettingsKey.records],
                as: SearchHistoryRecord.self,
                replace: PicaXSQLiteStore.replaceSearchHistory
            )
        }
        if content.contains(.downloads) {
            replaceSQLiteValue(
                backup.defaults[DownloadSettingsKey.records],
                as: DownloadRecord.self,
                replace: PicaXSQLiteStore.replaceDownloadRecords
            )
        }

    }

    @discardableResult
    @MainActor
    private static func mergeSQLiteBackupValue(key: String, importedValue: BackupDefaultValue) -> Bool {
        guard isSQLiteBackedDataKey(key) else {
            return false
        }
        guard let importedData = importedValue.decodedData() else {
            return true
        }

        if key == "picax.platformAccounts" {
            let accounts = PicaXSQLiteStore.loadPlatformAccounts()
            mergeSQLiteValues(
                existing: ComicPlatform.allCases.compactMap { accounts[$0] },
                importedData: importedData,
                merge: mergePlatformAccounts,
                replace: PicaXSQLiteStore.replacePlatformAccounts
            )
            return true
        }
        if key == "picax.localFavorites.default" {
            mergeSQLiteValues(
                existing: PicaXSQLiteStore.loadLocalFavorites(folderID: "default"),
                importedData: importedData,
                merge: mergeLocalFavorites
            ) { PicaXSQLiteStore.replaceLocalFavorites($0, folderID: "default") }
            return true
        }
        if key == ReadingHistoryService.Key.records {
            mergeSQLiteValues(
                existing: PicaXSQLiteStore.loadReadingHistory(),
                importedData: importedData,
                merge: mergeReadingHistory,
                replace: PicaXSQLiteStore.replaceReadingHistory
            )
            return true
        }
        if key == ReadingDurationService.Key.records {
            mergeSQLiteValues(
                existing: PicaXSQLiteStore.loadReadingDuration(),
                importedData: importedData,
                merge: mergeReadingDuration,
                replace: PicaXSQLiteStore.replaceReadingDuration
            )
            return true
        }
        if key == SearchHistorySettingsKey.records {
            mergeSQLiteValues(
                existing: PicaXSQLiteStore.loadSearchHistory(),
                importedData: importedData,
                merge: mergeSearchHistory,
                replace: PicaXSQLiteStore.replaceSearchHistory
            )
            return true
        }
        if key == DownloadSettingsKey.records {
            mergeSQLiteValues(
                existing: PicaXSQLiteStore.loadDownloadRecords(),
                importedData: importedData,
                merge: mergeDownloadRecords,
                replace: PicaXSQLiteStore.replaceDownloadRecords
            )
            return true
        }
        return true
    }

    @MainActor
    private static func mergeSQLiteValues<Value: Codable>(
        existing: [Value],
        importedData: Data,
        merge: (_ existingData: Data, _ importedData: Data) -> Data?,
        replace: ([Value]) -> Void
    ) {
        guard let existingData = encodeValue(existing) else { return }
        if let data = merge(existingData, importedData),
           let values = decodeValue([Value].self, from: data) {
            replace(values)
        }
    }

    @MainActor
    private static func replaceSQLiteValue<Value: Decodable>(
        _ value: BackupDefaultValue?,
        as type: Value.Type,
        replace: ([Value]) -> Void
    ) {
        guard let data = value?.decodedData(),
              let values = decodeValue([Value].self, from: data) else {
            replace([])
            return
        }
        replace(values)
    }

    private static func encodeValue<Value: Encodable>(_ value: Value) -> Data? {
        try? valueEncoder.encode(value)
    }

    private static func decodeValue<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        try? valueDecoder.decode(type, from: data)
    }

    private static func isSQLiteBackedDataKey(_ key: String) -> Bool {
        key == "picax.platformAccounts"
            || key == "picax.localFavorites.default"
            || key == ReadingHistoryService.Key.records
            || key == ReadingDurationService.Key.records
            || key == SearchHistorySettingsKey.records
            || key == DownloadSettingsKey.records
    }

    private static func shouldExportKey(_ key: String, includedContent: Set<BackupContentKind>) -> Bool {
        if key == DownloadSettingsKey.tasks { return false }
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
        if key == "picax.accounts" || key == "picax.session" || key == "picax.platformAccounts" {
            return .accounts
        }
        if key == DownloadSettingsKey.records {
            return .downloads
        }
        if key == ReadingHistoryService.Key.records {
            return .readingHistory
        }
        if key == ReadingDurationService.Key.records {
            return .readingDuration
        }
        if key == SearchHistorySettingsKey.records {
            return .searchHistory
        }
        if key == BlockingKeywordSettingsKey.common || key == BlockingKeywordSettingsKey.jmComic {
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

        guard let importedData = importedValue.decodedData(),
              let existingData = existingValue as? Data else {
            return existingValue
        }

        if key == "picax.platformAccounts" {
            return mergePlatformAccounts(existingData: existingData, importedData: importedData)
        }
        if key == "picax.accounts" {
            return mergeUserAccounts(existingData: existingData, importedData: importedData)
        }
        if key == ReadingHistoryService.Key.records {
            return mergeReadingHistory(existingData: existingData, importedData: importedData)
        }
        if key == ReadingDurationService.Key.records {
            return mergeReadingDuration(existingData: existingData, importedData: importedData)
        }
        if key == SearchHistorySettingsKey.records {
            return mergeSearchHistory(existingData: existingData, importedData: importedData)
        }
        if key == DownloadSettingsKey.records {
            return mergeDownloadRecords(existingData: existingData, importedData: importedData)
        }
        if key.hasPrefix("picax.localFavorites.") {
            return mergeLocalFavorites(existingData: existingData, importedData: importedData)
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

    private static func mergePlatformAccounts(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([PlatformAccount].self, from: existingData) ?? []
        let imported = decodeValue([PlatformAccount].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.platform, $0) })
        for account in local {
            values[account.platform] = account
        }
        let ordered = ComicPlatform.allCases.compactMap { values[$0] }
        return encodeValue(ordered)
    }

    private static func mergeUserAccounts(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([UserAccount].self, from: existingData) ?? []
        let imported = decodeValue([UserAccount].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for account in local {
            values[account.id] = account
        }
        return encodeValue(Array(values.values).sorted { $0.createdAt > $1.createdAt })
    }

    private static func mergeReadingHistory(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([ReadingHistoryRecord].self, from: existingData) ?? []
        let imported = decodeValue([ReadingHistoryRecord].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.viewedAt > record.viewedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return encodeValue(Array(values.values).sorted { $0.viewedAt > $1.viewedAt })
    }

    private static func mergeReadingDuration(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([ReadingDurationRecord].self, from: existingData) ?? []
        let imported = decodeValue([ReadingDurationRecord].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            guard var existing = values[record.id] else {
                values[record.id] = record
                continue
            }
            if record.lastReadAt > existing.lastReadAt {
                existing.item = record.item
                existing.lastReadAt = record.lastReadAt
            }
            existing.totalSeconds = max(existing.totalSeconds, record.totalSeconds)
            for (key, seconds) in record.dailySeconds {
                existing.dailySeconds[key] = max(existing.dailySeconds[key] ?? 0, seconds)
            }
            values[record.id] = existing
        }
        return encodeValue(Array(values.values).sorted { $0.lastReadAt > $1.lastReadAt })
    }

    private static func mergeSearchHistory(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([SearchHistoryRecord].self, from: existingData) ?? []
        let imported = decodeValue([SearchHistoryRecord].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.searchedAt > record.searchedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return encodeValue(Array(values.values).sorted { $0.searchedAt > $1.searchedAt })
    }

    private static func mergeDownloadRecords(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([DownloadRecord].self, from: existingData) ?? []
        let imported = decodeValue([DownloadRecord].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.updatedAt > record.updatedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return encodeValue(Array(values.values).sorted { $0.updatedAt > $1.updatedAt })
    }

    private static func mergeLocalFavorites(existingData: Data, importedData: Data) -> Data? {
        let local = decodeValue([BackupStoredLocalFavorite].self, from: existingData) ?? []
        let imported = decodeValue([BackupStoredLocalFavorite].self, from: importedData) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.mergeID, $0) })
        for favorite in local {
            values[favorite.mergeID] = favorite
        }
        return encodeValue(Array(values.values).sorted {
            ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast)
        })
    }

    private static func exportDownloadFiles() async throws -> [ExportedBackupFile] {
        try await Task.detached(priority: .utility) {
            let rootURL = try downloadsRootURL()
            guard FileManager.default.fileExists(atPath: rootURL.path),
                  let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            var files: [ExportedBackupFile] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                let data = try Data(contentsOf: fileURL)
                files.append(ExportedBackupFile(relativePath: relativePath, data: data))
            }
            return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }.value
    }

    private static func replaceDownloadFiles(with files: [BackupFile]) async throws {
        try await Task.detached(priority: .utility) {
            let rootURL = try downloadsRootURL()
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try writeDownloadFiles(files, rootURL: rootURL, overwritesExisting: true)
        }.value
    }

    private static func mergeDownloadFiles(_ files: [BackupFile]) async throws {
        try await Task.detached(priority: .utility) {
            let rootURL = try downloadsRootURL()
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try writeDownloadFiles(files, rootURL: rootURL, overwritesExisting: false)
        }.value
    }

    private nonisolated static func writeDownloadFiles(_ files: [BackupFile], rootURL: URL, overwritesExisting: Bool) throws {
        for file in files {
            guard isSafeRelativePath(file.relativePath),
                  let data = file.rawData ?? file.data.flatMap({ Data(base64Encoded: $0) }) else {
                continue
            }
            let fileURL = rootURL.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !overwritesExisting, FileManager.default.fileExists(atPath: fileURL.path) {
                continue
            }
            try data.write(to: fileURL, options: .atomic)
        }
    }

    private nonisolated static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.split(separator: "/").contains("..")
    }

    private nonisolated static func downloadsRootURL() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ComicContentError.invalidResponse("无法访问应用支持目录。")
        }
        return baseURL
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
    }
}

private struct ExportedBackupFile {
    var relativePath: String
    var data: Data
}

private struct BackupStoredLocalFavorite: Codable {
    let id: String
    let platform: ComicPlatform
    let title: String
    let subtitle: String
    let coverURLString: String
    let tags: [String]
    let pageCount: Int?
    let likesCount: Int?
    let favoriteDate: Date?

    var mergeID: String {
        "\(platform.id)-\(id)"
    }
}

private struct BackupSQLiteContent {
    var defaults: [String: BackupDefaultValue]
    var downloadFiles: [BackupFile]
}

private enum BackupSQLiteArchive {
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

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw BackupArchiveError.sqliteFailure
        }
        defer {
            sqlite3_close(db)
        }

        try execute("""
        CREATE TABLE defaults (
            key TEXT PRIMARY KEY NOT NULL,
            value BLOB NOT NULL
        )
        """, db: db)
        try execute("""
        CREATE TABLE download_files (
            relative_path TEXT PRIMARY KEY NOT NULL
        )
        """, db: db)
        try execute("BEGIN IMMEDIATE TRANSACTION", db: db)
        for (key, value) in defaults.sorted(by: { $0.key < $1.key }) {
            guard let data = try? JSONEncoder().encode(value) else { continue }
            try execute(
                "INSERT OR REPLACE INTO defaults(key, value) VALUES(?, ?)",
                bindings: [.text(key), .data(data)],
                db: db
            )
        }
        for file in downloadFiles.sorted(by: { $0.relativePath < $1.relativePath }) {
            try execute(
                "INSERT OR REPLACE INTO download_files(relative_path) VALUES(?)",
                bindings: [.text(file.relativePath)],
                db: db
            )
        }
        try execute("COMMIT", db: db)
        sqlite3_close(db)
        db = nil
        return try Data(contentsOf: url)
    }

    static func readDatabase(_ data: Data) throws -> BackupSQLiteContent {
        let url = temporaryDatabaseURL()
        try? FileManager.default.removeItem(at: url)
        defer {
            removeDatabaseFiles(for: url)
        }
        try data.write(to: url, options: .atomic)

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BackupArchiveError.invalidArchive
        }
        defer {
            sqlite3_close(db)
        }

        var defaults: [String: BackupDefaultValue] = [:]
        try query("SELECT key, value FROM defaults", db: db) { statement in
            guard let keyPointer = sqlite3_column_text(statement, 0) else { return }
            let key = String(cString: keyPointer)
            let byteCount = Int(sqlite3_column_bytes(statement, 1))
            guard byteCount > 0,
                  let bytes = sqlite3_column_blob(statement, 1),
                  let value = try? JSONDecoder().decode(BackupDefaultValue.self, from: Data(bytes: bytes, count: byteCount)) else {
                return
            }
            defaults[key] = value
        }

        var downloadFiles: [BackupFile] = []
        try query("SELECT relative_path FROM download_files ORDER BY relative_path", db: db) { statement in
            guard let pathPointer = sqlite3_column_text(statement, 0) else { return }
            downloadFiles.append(BackupFile(relativePath: String(cString: pathPointer)))
        }

        return BackupSQLiteContent(defaults: defaults, downloadFiles: downloadFiles)
    }

    private static func execute(_ sql: String, bindings: [SQLiteBinding] = [], db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BackupArchiveError.sqliteFailure
        }
        defer {
            sqlite3_finalize(statement)
        }
        bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BackupArchiveError.sqliteFailure
        }
    }

    private static func query(_ sql: String, db: OpaquePointer?, row: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BackupArchiveError.invalidArchive
        }
        defer {
            sqlite3_finalize(statement)
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            try row(statement)
        }
    }

    private static func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, backupSQLiteTransient)
            case .double(let value):
                sqlite3_bind_double(statement, position, value)
            case .data(let value):
                _ = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, position, buffer.baseAddress, Int32(value.count), backupSQLiteTransient)
                }
            }
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

struct StoredZipEntry {
    var path: String
    var data: Data
}

enum StoredZipArchive {
    static func makeArchive(entries: [StoredZipEntry]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var centralRecords: [CentralDirectoryWriteRecord] = []

        for entry in entries {
            let fileName = try fileNameData(for: entry.path)
            let compressedData = try deflateRawDeflate(entry.data)
            let compressedSize = try uint32Size(compressedData.count)
            let uncompressedSize = try uint32Size(entry.data.count)
            let offset = try uint32Size(archive.count)
            let crc32 = CRC32.checksum(entry.data)

            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(8)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc32)
            archive.appendUInt32LE(compressedSize)
            archive.appendUInt32LE(uncompressedSize)
            archive.appendUInt16LE(UInt16(fileName.count))
            archive.appendUInt16LE(0)
            archive.append(fileName)
            archive.append(compressedData)

            centralRecords.append(CentralDirectoryWriteRecord(
                entry: entry,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                offset: offset
            ))
        }

        let centralDirectoryOffset = try uint32Size(archive.count)

        for record in centralRecords {
            let fileName = try fileNameData(for: record.entry.path)

            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(8)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(record.crc32)
            centralDirectory.appendUInt32LE(record.compressedSize)
            centralDirectory.appendUInt32LE(record.uncompressedSize)
            centralDirectory.appendUInt16LE(UInt16(fileName.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(record.offset)
            centralDirectory.append(fileName)
        }

        archive.append(centralDirectory)
        let centralDirectorySize = try uint32Size(centralDirectory.count)
        let entryCount = UInt16(centralRecords.count)

        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(entryCount)
        archive.appendUInt16LE(entryCount)
        archive.appendUInt32LE(centralDirectorySize)
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        return archive
    }

    static func extractEntry(named path: String, from archive: Data) throws -> Data? {
        try extractEntries(from: archive).first { $0.path == path }?.data
    }

    static func extractEntries(from archive: Data) throws -> [StoredZipEntry] {
        if let records = centralDirectoryRecords(in: archive) {
            return try records.compactMap { record in
                guard !record.path.hasSuffix("/") else { return nil }
                return StoredZipEntry(path: record.path, data: try entryData(record: record, archive: archive))
            }
        }
        return try localEntries(from: archive)
    }

    private static func fileNameData(for path: String) throws -> Data {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains(".."),
              let data = path.data(using: .utf8),
              data.count <= Int(UInt16.max) else {
            throw BackupArchiveError.invalidPath
        }
        return data
    }

    private static func uint32Size(_ value: Int) throws -> UInt32 {
        guard value <= Int(UInt32.max) else {
            throw BackupArchiveError.entryTooLarge
        }
        return UInt32(value)
    }

    private struct CentralDirectoryRecord {
        var path: String
        var compression: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private struct CentralDirectoryWriteRecord {
        var entry: StoredZipEntry
        var crc32: UInt32
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var offset: UInt32
    }

    private static func centralDirectoryRecords(in archive: Data) -> [CentralDirectoryRecord]? {
        guard let endOffset = endOfCentralDirectoryOffset(in: archive),
              let entryCount = archive.uint16LE(at: endOffset + 10),
              let centralDirectoryOffset = archive.uint32LE(at: endOffset + 16) else {
            return nil
        }

        var records: [CentralDirectoryRecord] = []
        var offset = Int(centralDirectoryOffset)
        for _ in 0..<Int(entryCount) {
            guard offset + 46 <= archive.count,
                  archive.uint32LE(at: offset) == 0x02014b50,
                  let compression = archive.uint16LE(at: offset + 10),
                  let compressedSize = archive.uint32LE(at: offset + 20),
                  let uncompressedSize = archive.uint32LE(at: offset + 24),
                  let fileNameLength = archive.uint16LE(at: offset + 28),
                  let extraLength = archive.uint16LE(at: offset + 30),
                  let commentLength = archive.uint16LE(at: offset + 32),
                  let localHeaderOffset = archive.uint32LE(at: offset + 42) else {
                return nil
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + Int(fileNameLength)
            guard nameEnd <= archive.count,
                  let path = String(data: archive.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
                return nil
            }
            records.append(CentralDirectoryRecord(
                path: path,
                compression: compression,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localHeaderOffset)
            ))
            offset = nameEnd + Int(extraLength) + Int(commentLength)
        }
        return records
    }

    private static func endOfCentralDirectoryOffset(in archive: Data) -> Int? {
        guard archive.count >= 22 else { return nil }
        let lowerBound = max(0, archive.count - 22 - Int(UInt16.max))
        var offset = archive.count - 22
        while offset >= lowerBound {
            if archive.uint32LE(at: offset) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private static func entryData(record: CentralDirectoryRecord, archive: Data) throws -> Data {
        let offset = record.localHeaderOffset
        guard offset + 30 <= archive.count,
              archive.uint32LE(at: offset) == 0x04034b50,
              let fileNameLength = archive.uint16LE(at: offset + 26),
              let extraLength = archive.uint16LE(at: offset + 28) else {
            throw BackupArchiveError.invalidArchive
        }
        let dataStart = offset + 30 + Int(fileNameLength) + Int(extraLength)
        let dataEnd = dataStart + record.compressedSize
        guard dataEnd <= archive.count else {
            throw BackupArchiveError.invalidArchive
        }
        let compressedData = archive.subdata(in: dataStart..<dataEnd)
        return try decodedEntryData(
            compressedData,
            compression: record.compression,
            uncompressedSize: record.uncompressedSize
        )
    }

    private static func localEntries(from archive: Data) throws -> [StoredZipEntry] {
        var entries: [StoredZipEntry] = []
        var offset = 0
        while offset + 30 <= archive.count {
            guard let signature = archive.uint32LE(at: offset) else { return entries }
            if signature != 0x04034b50 {
                return entries
            }
            guard let compression = archive.uint16LE(at: offset + 8),
                  let compressedSize = archive.uint32LE(at: offset + 18),
                  let uncompressedSize = archive.uint32LE(at: offset + 22),
                  let fileNameLength = archive.uint16LE(at: offset + 26),
                  let extraLength = archive.uint16LE(at: offset + 28) else {
                throw BackupArchiveError.invalidArchive
            }

            let nameStart = offset + 30
            let nameEnd = nameStart + Int(fileNameLength)
            let dataStart = nameEnd + Int(extraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard nameEnd <= archive.count, dataEnd <= archive.count else {
                throw BackupArchiveError.invalidArchive
            }

            if let fileName = String(data: archive.subdata(in: nameStart..<nameEnd), encoding: .utf8),
               !fileName.hasSuffix("/") {
                let compressedData = archive.subdata(in: dataStart..<dataEnd)
                let data = try decodedEntryData(
                    compressedData,
                    compression: compression,
                    uncompressedSize: Int(uncompressedSize)
                )
                entries.append(StoredZipEntry(path: fileName, data: data))
            }
            offset = dataEnd
        }
        return entries
    }

    private static func decodedEntryData(_ data: Data, compression: UInt16, uncompressedSize: Int) throws -> Data {
        switch compression {
        case 0:
            return data
        case 8:
            return try inflateRawDeflate(data, uncompressedSize: uncompressedSize)
        default:
            throw BackupArchiveError.unsupportedCompression
        }
    }

    private static func inflateRawDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize >= 0 else { throw BackupArchiveError.invalidArchive }
        if data.isEmpty {
            return Data()
        }

        var stream = z_stream()
        let version = ZLIB_VERSION
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, version, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw BackupArchiveError.unsupportedCompression
        }
        defer {
            inflateEnd(&stream)
        }

        var output = Data(count: uncompressedSize)
        let outputCapacity = output.count
        let status = data.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer -> Int32 in
                guard let source = sourceBuffer.bindMemory(to: Bytef.self).baseAddress,
                      let destination = destinationBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_BUF_ERROR
                }
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else {
            throw BackupArchiveError.invalidArchive
        }
        output.count = Int(stream.total_out)
        return output
    }

    private static func deflateRawDeflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        let version = ZLIB_VERSION
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            version,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw BackupArchiveError.unsupportedCompression
        }
        defer {
            deflateEnd(&stream)
        }

        let outputCapacity = Int(deflateBound(&stream, uLong(data.count)))
        var output = Data(count: max(outputCapacity, 1))
        let outputCount = output.count
        let status = data.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer -> Int32 in
                if data.count > 0 {
                    guard let source = sourceBuffer.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_BUF_ERROR
                    }
                    stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source)
                }
                guard let destination = destinationBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_BUF_ERROR
                }
                stream.avail_in = uInt(data.count)
                stream.next_out = destination
                stream.avail_out = uInt(outputCount)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else {
            throw BackupArchiveError.unsupportedCompression
        }
        output.count = Int(stream.total_out)
        return output
    }
}

enum BackupArchiveError: LocalizedError {
    case invalidPath
    case entryTooLarge
    case invalidArchive
    case missingManifest
    case unsupportedCompression
    case sqliteFailure

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "备份文件路径无效。"
        case .entryTooLarge:
            "备份内容过大，无法导出。"
        case .invalidArchive:
            "备份文件已损坏。"
        case .missingManifest:
            "这不是可导入的 PicaX 备份。"
        case .unsupportedCompression:
            "暂不支持此备份压缩格式。"
        case .sqliteFailure:
            "备份数据写入失败。"
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8)
        ])
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    func uint16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

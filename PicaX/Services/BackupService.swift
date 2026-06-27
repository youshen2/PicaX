import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum BackupImportMode {
    case overwrite
    case merge
}

struct PicaXBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

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

    var title: String {
        backup.includesDownloads ? "包含已下载漫画" : "不包含已下载漫画"
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
    var includesDownloads: Bool
    var defaults: [String: BackupDefaultValue]
    var downloadFiles: [BackupFile]
}

struct BackupFile: Codable {
    var relativePath: String
    var data: String
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
    private static let formatVersion = 1
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

    static func makeDocument(includesDownloads: Bool, defaults: UserDefaults = .standard) async throws -> PicaXBackupDocument {
        let backup = PicaXBackup(
            formatVersion: formatVersion,
            createdAt: Date(),
            includesDownloads: includesDownloads,
            defaults: exportDefaults(includesDownloads: includesDownloads, defaults: defaults),
            downloadFiles: includesDownloads ? try await exportDownloadFiles() : []
        )
        let data = try encoder.encode(backup)
        return PicaXBackupDocument(data: data)
    }

    static func preview(from data: Data) throws -> BackupImportPreview {
        let backup = try decoder.decode(PicaXBackup.self, from: data)
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
        let backup = try decoder.decode(PicaXBackup.self, from: data)
        try await importBackup(backup, mode: mode, defaults: defaults)
    }

    private static func exportDefaults(includesDownloads: Bool, defaults: UserDefaults) -> [String: BackupDefaultValue] {
        defaults.dictionaryRepresentation().reduce(into: [String: BackupDefaultValue]()) { result, element in
            let key = element.key
            guard shouldExportKey(key, includesDownloads: includesDownloads),
                  let value = BackupDefaultValue.from(element.value) else {
                return
            }
            result[key] = value
        }
    }

    private static func overwrite(with backup: PicaXBackup, defaults: UserDefaults) async throws {
        let currentKeys = defaults.dictionaryRepresentation().keys.filter { isManagedKey($0) }
        for key in currentKeys where backup.defaults[key] == nil && shouldRemoveMissingKey(key, backupIncludesDownloads: backup.includesDownloads) {
            defaults.removeObject(forKey: key)
        }

        for (key, value) in backup.defaults {
            guard let defaultsValue = value.userDefaultsValue() else { continue }
            defaults.set(defaultsValue, forKey: key)
        }

        if backup.includesDownloads {
            try await replaceDownloadFiles(with: backup.downloadFiles)
        }
    }

    private static func merge(with backup: PicaXBackup, defaults: UserDefaults) async throws {
        for (key, importedValue) in backup.defaults {
            if let mergedValue = mergedDefaultValue(key: key, importedValue: importedValue, defaults: defaults) {
                defaults.set(mergedValue, forKey: key)
            }
        }

        if backup.includesDownloads {
            try await mergeDownloadFiles(backup.downloadFiles)
        }
    }

    private static func shouldExportKey(_ key: String, includesDownloads: Bool) -> Bool {
        guard isManagedKey(key) else { return false }
        if key == DownloadSettingsKey.tasks { return false }
        if !includesDownloads, key == DownloadSettingsKey.records { return false }
        return true
    }

    private static func isManagedKey(_ key: String) -> Bool {
        key.hasPrefix("picax.") || key.hasPrefix("settings.")
    }

    private static func shouldRemoveMissingKey(_ key: String, backupIncludesDownloads: Bool) -> Bool {
        if !backupIncludesDownloads, key == DownloadSettingsKey.records || key == DownloadSettingsKey.tasks {
            return false
        }
        return true
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
        let local = (try? JSONDecoder().decode([PlatformAccount].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([PlatformAccount].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.platform, $0) })
        for account in local {
            values[account.platform] = account
        }
        let ordered = ComicPlatform.allCases.compactMap { values[$0] }
        return try? JSONEncoder().encode(ordered)
    }

    private static func mergeUserAccounts(existingData: Data, importedData: Data) -> Data? {
        let local = (try? JSONDecoder().decode([UserAccount].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([UserAccount].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for account in local {
            values[account.id] = account
        }
        return try? JSONEncoder().encode(Array(values.values).sorted { $0.createdAt > $1.createdAt })
    }

    private static func mergeReadingHistory(existingData: Data, importedData: Data) -> Data? {
        let local = (try? JSONDecoder().decode([ReadingHistoryRecord].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([ReadingHistoryRecord].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.viewedAt > record.viewedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return try? JSONEncoder().encode(Array(values.values).sorted { $0.viewedAt > $1.viewedAt })
    }

    private static func mergeSearchHistory(existingData: Data, importedData: Data) -> Data? {
        let local = (try? JSONDecoder().decode([SearchHistoryRecord].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([SearchHistoryRecord].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.searchedAt > record.searchedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return try? JSONEncoder().encode(Array(values.values).sorted { $0.searchedAt > $1.searchedAt })
    }

    private static func mergeDownloadRecords(existingData: Data, importedData: Data) -> Data? {
        let local = (try? JSONDecoder().decode([DownloadRecord].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([DownloadRecord].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, $0) })
        for record in local {
            if let existing = values[record.id] {
                values[record.id] = existing.updatedAt > record.updatedAt ? existing : record
            } else {
                values[record.id] = record
            }
        }
        return try? JSONEncoder().encode(Array(values.values).sorted { $0.updatedAt > $1.updatedAt })
    }

    private static func mergeLocalFavorites(existingData: Data, importedData: Data) -> Data? {
        let local = (try? JSONDecoder().decode([BackupStoredLocalFavorite].self, from: existingData)) ?? []
        let imported = (try? JSONDecoder().decode([BackupStoredLocalFavorite].self, from: importedData)) ?? []
        var values = Dictionary(uniqueKeysWithValues: imported.map { ($0.mergeID, $0) })
        for favorite in local {
            values[favorite.mergeID] = favorite
        }
        return try? JSONEncoder().encode(Array(values.values).sorted {
            ($0.favoriteDate ?? .distantPast) > ($1.favoriteDate ?? .distantPast)
        })
    }

    private static func exportDownloadFiles() async throws -> [BackupFile] {
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

            var files: [BackupFile] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                let data = try Data(contentsOf: fileURL)
                files.append(BackupFile(relativePath: relativePath, data: data.base64EncodedString()))
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
                  let data = Data(base64Encoded: file.data) else {
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

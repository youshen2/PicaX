import Foundation
import SQLite3

enum PicaComicBackupImporter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    static func preview(from data: Data) throws -> BackupImportPreview {
        let entries = try StoredZipArchive.extractEntries(from: data)
        let entryMap = entries.reduce(into: [String: Data]()) { result, entry in
            result[entry.path] = result[entry.path] ?? entry.data
        }
        let appdata = try appdata(from: entryMap)

        var defaults: [String: BackupDefaultValue] = [:]
        var includedContent = Set<BackupContentKind>()
        var downloadFiles: [BackupFile] = []

        let settingDefaults = mappedSettings(from: appdata)
        defaults.merge(settingDefaults) { _, new in new }
        if !settingDefaults.isEmpty {
            includedContent.insert(.settings)
        }

        if let blockingKeywords = stringArray(appdata["blockingKeywords"]), !blockingKeywords.isEmpty {
            defaults[BlockingKeywordSettingsKey.common] = BackupDefaultValue.from(uniqueStrings(blockingKeywords))
            includedContent.insert(.blockingKeywords)
        }
        if let jmKeywords = stringArray(appdata["jmBlockingKeywords"] ?? appdata["jmBlockingKeyword"]), !jmKeywords.isEmpty {
            defaults[BlockingKeywordSettingsKey.jmComic] = BackupDefaultValue.from(uniqueStrings(jmKeywords))
            includedContent.insert(.blockingKeywords)
        }

        let cookieRows = sqliteRows(named: "cookies.db", in: entryMap, query: "select name, value, domain, path, expires, secure from cookies;")
        let accounts = platformAccounts(from: entries, cookieRows: cookieRows)
        if !accounts.isEmpty, let data = try? encoder.encode(accounts) {
            defaults["picax.platformAccounts"] = BackupDefaultValue.from(data)
            includedContent.insert(.accounts)
        }

        let searchRecords = searchHistoryRecords(from: appdata)
        if !searchRecords.isEmpty, let data = try? encoder.encode(searchRecords) {
            defaults[SearchHistorySettingsKey.records] = BackupDefaultValue.from(data)
            includedContent.insert(.searchHistory)
        }

        let readingRecords = readingHistoryRecords(from: entryMap)
        if !readingRecords.isEmpty, let data = try? encoder.encode(readingRecords) {
            defaults[ReadingHistoryService.Key.records] = BackupDefaultValue.from(data)
            includedContent.insert(.readingHistory)
        }

        let favoriteItems = localFavoriteItems(from: entryMap)
        if !favoriteItems.isEmpty, let data = try? encoder.encode(favoriteItems) {
            defaults["picax.localFavorites.default"] = BackupDefaultValue.from(data)
            includedContent.insert(.favorites)
        }

        let downloads = downloadedRecords(from: entries, entryMap: entryMap)
        if !downloads.records.isEmpty, let data = try? encoder.encode(downloads.records) {
            defaults[DownloadSettingsKey.records] = BackupDefaultValue.from(data)
            downloadFiles = downloads.files
            includedContent.insert(.downloads)
        }

        guard !includedContent.isEmpty else {
            throw PicaComicImportError.emptyBackup
        }

        let backup = PicaXBackup(
            formatVersion: 1,
            createdAt: Date(),
            includedContent: BackupContentKind.allCases.filter { includedContent.contains($0) },
            defaults: defaults,
            downloadFiles: downloadFiles
        )
        return BackupImportPreview(backup: backup, data: data, sourceTitle: "PicaComic 备份")
    }

    private static func appdata(from entries: [String: Data]) throws -> [String: Any] {
        guard let data = entries["appdata"] else {
            throw PicaComicImportError.missingAppData
        }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PicaComicImportError.invalidAppData
        }
        return value
    }

    private static func mappedSettings(from appdata: [String: Any]) -> [String: BackupDefaultValue] {
        guard let settings = appdata["settings"] as? [Any] else { return [:] }
        var result: [String: BackupDefaultValue] = [:]

        if let value = boolSetting(settings, at: 2) {
            result[AppBehaviorSettingsKey.checksUpdatesOnLaunch] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 32) {
            let mode = switch value {
            case "1":
                AppAppearanceMode.light.rawValue
            case "2":
                AppAppearanceMode.dark.rawValue
            default:
                AppAppearanceMode.system.rawValue
            }
            result[AppAppearanceSettingsKey.colorScheme] = BackupDefaultValue.from(mode)
        }
        if let value = stringSetting(settings, at: 61) {
            result[AppBehaviorSettingsKey.checksClipboardForComicLinks] = BackupDefaultValue.from(value == "0")
        }
        if let value = intSetting(settings, at: 35), value > 0 {
            result[ImageCacheSettingsKey.maxDiskSizeMB] = BackupDefaultValue.from(value)
        }
        if let value = intSetting(settings, at: 79) {
            result[DownloadSettingsKey.concurrentDownloadCount] = BackupDefaultValue.from(min(max(value, 1), 6))
        }
        if let value = boolSetting(settings, at: 102) {
            result[DownloadSettingsKey.downloadsCommentsByDefault] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 72) {
            result[ComicListSettingsKey.showsFavoriteState] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 73) {
            result[ComicListSettingsKey.showsReadingProgress] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 93) {
            result[ReadFilterSettingsKey.hidesReadComicsInLists] = BackupDefaultValue.from(value)
        }
        if let value = intSetting(settings, at: 94) {
            result[ReadFilterSettingsKey.hiddenProgressThreshold] = BackupDefaultValue.from(min(max(value, 0), 100))
        }
        if let value = readerReadingMode(from: stringSetting(settings, at: 9)) {
            result[ReaderSettingsKey.readingMode] = BackupDefaultValue.from(value.rawValue)
        }
        if let value = intSetting(settings, at: 28) {
            result[ReaderSettingsKey.preloadImageCount] = BackupDefaultValue.from(min(max(value, 0), 15))
        }
        if let value = boolSetting(settings, at: 18) {
            result[ReaderSettingsKey.reducesImageBrightnessInDarkMode] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 0) {
            result[ReaderSettingsKey.tapPagingEnabled] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 70) {
            result[ReaderSettingsKey.tapPagingInverted] = BackupDefaultValue.from(value)
        }
        if let value = intSetting(settings, at: 40) {
            result[ReaderSettingsKey.tapPagingEdgePercent] = BackupDefaultValue.from(min(max(value, 0), 50))
        }
        if let value = boolSetting(settings, at: 49) {
            result[ReaderSettingsKey.doubleTapZoomEnabled] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 55) {
            result[ReaderSettingsKey.longPressZoomEnabled] = BackupDefaultValue.from(value)
        }
        if let value = intSetting(settings, at: 33), value > 0 {
            result[ReaderSettingsKey.autoPagingInterval] = BackupDefaultValue.from(Double(value))
        }
        if let value = boolSetting(settings, at: 99) {
            result[ReaderSettingsKey.showsChapterCommentsAtEnd] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 98) {
            result[ReaderSettingsKey.showsSystemStatus] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 1), PicacgSortMode(rawValue: value) != nil {
            result[PlatformFeatureSettingsKey.picacgDefaultSort] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 5) {
            result[PlatformFeatureSettingsKey.picacgShowsAvatarFrame] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 6) {
            result[PlatformFeatureSettingsKey.picacgAutoPunchIn] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 30) {
            let sort = value == "1" ? PicacgFavoriteSort.newest.rawValue : PicacgFavoriteSort.oldest.rawValue
            result[PlatformFeatureSettingsKey.picacgFavoriteSort] = BackupDefaultValue.from(sort)
        }
        if let value = boolSetting(settings, at: 15) {
            result[PlatformFeatureSettingsKey.jmAutoSelectAPIEndpoint] = BackupDefaultValue.from(value)
        }
        if let value = jmAPIEndpoint(from: intSetting(settings, at: 17)) {
            result[PlatformFeatureSettingsKey.jmAPIEndpoint] = BackupDefaultValue.from(value.rawValue)
        }
        if let value = jmImageEndpoint(from: intSetting(settings, at: 37)) {
            result[PlatformFeatureSettingsKey.jmImageEndpoint] = BackupDefaultValue.from(value.rawValue)
        }
        if let value = stringSetting(settings, at: 42) {
            let sort = value == "1" ? JmFavoriteSort.updated.rawValue : JmFavoriteSort.latest.rawValue
            result[PlatformFeatureSettingsKey.jmFavoriteSort] = BackupDefaultValue.from(sort)
        }
        if let value = boolSetting(settings, at: 88) {
            result[PlatformFeatureSettingsKey.jmAutoCheckIn] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 89), !value.isEmpty {
            result[PlatformFeatureSettingsKey.jmAppVersion] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 85), !value.isEmpty {
            let urls = value
                .split(separator: ",")
                .map { normalizedURLString(String($0)) }
                .filter { URL(string: $0)?.host != nil }
            if !urls.isEmpty {
                result[PlatformFeatureSettingsKey.jmCustomAPIBaseURLs] = BackupDefaultValue.from(urls.joined(separator: "\n"))
            }
        }
        if let value = stringSetting(settings, at: 86), URL(string: normalizedURLString(value))?.host != nil {
            result[PlatformFeatureSettingsKey.jmCustomImageBaseURL] = BackupDefaultValue.from(normalizedURLString(value))
        }
        if let value = stringSetting(settings, at: 31), URL(string: normalizedURLString(value))?.host != nil {
            result[PlatformFeatureSettingsKey.frontendBaseURL(.htManga)] = BackupDefaultValue.from(normalizedURLString(value))
        }
        if let value = stringSetting(settings, at: 87), !value.isEmpty {
            result[PlatformFeatureSettingsKey.hitomiDataDomain] = BackupDefaultValue.from(value)
        }
        if let value = ehentaiFrontendBaseURL(from: stringSetting(settings, at: 20)) {
            result[PlatformFeatureSettingsKey.frontendBaseURL(.eHentai)] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 29) {
            result[PlatformFeatureSettingsKey.ehentaiPrefersOriginalImage] = BackupDefaultValue.from(value)
        }
        if let value = boolSetting(settings, at: 47) {
            result[PlatformFeatureSettingsKey.ehentaiIgnoresContentWarning] = BackupDefaultValue.from(value)
        }
        if let value = stringSetting(settings, at: 75), !value.isEmpty {
            result[PlatformFeatureSettingsKey.ehentaiProfile] = BackupDefaultValue.from(value)
        }

        return result
    }

    private static func platformAccounts(from entries: [StoredZipEntry], cookieRows: [[String: PicaComicSQLiteValue]]) -> [PlatformAccount] {
        var accounts: [ComicPlatform: PlatformAccount] = [:]
        let sourceData = entries
            .filter { $0.path.hasPrefix("comic_source/") && $0.path.hasSuffix(".data") }
            .compactMap { entry -> (String, [String: Any])? in
                let key = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
                guard let json = try? JSONSerialization.jsonObject(with: entry.data) as? [String: Any] else {
                    return nil
                }
                return (key, json)
            }

        for (source, json) in sourceData {
            guard let platform = platform(sourceKey: source) else { continue }
            let accountData = json["account"]
            let username = accountUsername(accountData: accountData, json: json, fallback: platform.title)
            let password = (accountData as? [Any])?.element(at: 1) as? String
            let cookies = normalizedCookiesForPlatform(platform, cookies: cookiesForPlatform(platform, rows: cookieRows))
            let token = platformToken(platform: platform, json: json, cookies: cookies)
            let importedToken = platform == .picacg && password?.nonEmptyValue != nil ? nil : token
            let refreshToken = platformRefreshToken(platform: platform, cookies: cookies)
            guard !(token?.isEmpty ?? true) || !(password?.isEmpty ?? true) || !cookies.isEmpty || !(refreshToken?.isEmpty ?? true) else {
                continue
            }
            let profile = accountProfile(platform: platform, json: json, username: username)
            let credential = PlatformCredential(
                token: importedToken?.nonEmptyValue,
                refreshToken: refreshToken?.nonEmptyValue,
                tokenType: platformTokenType(platform: platform, token: importedToken),
                password: password?.nonEmptyValue,
                cookies: cookies,
                userAgent: nil,
                baseURL: PlatformFeatureSettings.defaultFrontendBaseURL(for: platform),
                source: cookies.isEmpty ? .api : .web,
                profile: profile
            )
            accounts[platform] = PlatformAccount(platform: platform, username: username, credential: credential)
        }

        for platform in ComicPlatform.allCases where accounts[platform] == nil {
            let cookies = normalizedCookiesForPlatform(platform, cookies: cookiesForPlatform(platform, rows: cookieRows))
            let token = platformToken(platform: platform, json: [:], cookies: cookies)
            let refreshToken = platformRefreshToken(platform: platform, cookies: cookies)
            guard !cookies.isEmpty || !(token?.isEmpty ?? true) || !(refreshToken?.isEmpty ?? true) else {
                continue
            }
            let credential = PlatformCredential(
                token: token?.nonEmptyValue,
                refreshToken: refreshToken?.nonEmptyValue,
                tokenType: platformTokenType(platform: platform, token: token),
                password: nil,
                cookies: cookies,
                userAgent: nil,
                baseURL: PlatformFeatureSettings.defaultFrontendBaseURL(for: platform),
                source: .web,
                profile: PlatformAccountProfile(email: nil, username: nil, nickname: platform.title)
            )
            accounts[platform] = PlatformAccount(platform: platform, username: platform.title, credential: credential)
        }

        return ComicPlatform.allCases.compactMap { platform in
            accounts[platform]
        }
    }

    private static func searchHistoryRecords(from appdata: [String: Any]) -> [SearchHistoryRecord] {
        let values = stringArray(appdata["searchHistory"] ?? appdata["search"]) ?? []
        let now = Date()
        return uniqueStrings(values).enumerated().map { index, keyword in
            SearchHistoryRecord(
                keyword: keyword,
                target: .aggregate(ComicPlatform.allCases),
                searchedAt: now.addingTimeInterval(Double(-index))
            )
        }
    }

    private static func readingHistoryRecords(from entries: [String: Data]) -> [ReadingHistoryRecord] {
        let rows = sqliteRows(named: "history.db", in: entries, query: "select target, title, subtitle, cover, time, type, ep, page, readEpisode, max_page from history order by time desc;")
        return rows.compactMap { row in
            guard let platform = platform(type: row["type"]?.intValue),
                  let target = row["target"]?.stringValue,
                  let title = row["title"]?.stringValue,
                  !target.isEmpty,
                  !title.isEmpty else {
                return nil
            }
            let item = ComicListItem(
                id: normalizedComicID(target, platform: platform),
                platform: platform,
                title: title,
                subtitle: row["subtitle"]?.stringValue ?? "",
                coverURLString: row["cover"]?.stringValue ?? "",
                tags: [],
                pageCount: row["max_page"]?.intValue,
                likesCount: nil,
                favoriteDate: nil
            )
            let viewedAt = date(milliseconds: row["time"]?.intValue) ?? Date()
            let ep = max((row["ep"]?.intValue ?? 0) - 1, 0)
            let page = max((row["page"]?.intValue ?? 0) - 1, 0)
            let totalPages = row["max_page"]?.intValue ?? 0
            let readChapters = readEpisodeSet(row["readEpisode"]?.stringValue)
            let hasProgress = (row["ep"]?.intValue ?? 0) > 0 || (row["page"]?.intValue ?? 0) > 0
            let progress = hasProgress
                ? ReadingProgress(
                    status: .reading,
                    chapterIndex: ep,
                    pageIndex: page,
                    totalPages: totalPages,
                    totalChapters: max(readChapters.count, ep + 1),
                    readChapterIndexes: readChapters,
                    updatedAt: viewedAt
                )
                : nil
            return ReadingHistoryRecord(item: item, viewedAt: viewedAt, progress: progress)
        }
    }

    private static func localFavoriteItems(from entries: [String: Data]) -> [PicaComicStoredLocalFavorite] {
        let rows = favoriteRows(from: entries)
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let platform = platform(type: row["type"]?.intValue),
                  let target = row["target"]?.stringValue,
                  let title = row["name"]?.stringValue,
                  !target.isEmpty,
                  !title.isEmpty else {
                return nil
            }
            let id = normalizedComicID(target, platform: platform)
            guard seen.insert("\(platform.id)-\(id)").inserted else { return nil }
            return PicaComicStoredLocalFavorite(
                id: id,
                platform: platform,
                title: title,
                subtitle: row["author"]?.stringValue ?? "",
                coverURLString: row["cover_path"]?.stringValue ?? "",
                tags: tags(from: row["tags"]?.stringValue),
                pageCount: nil,
                likesCount: nil,
                favoriteDate: date(string: row["time"]?.stringValue)
            )
        }
    }

    private static func downloadedRecords(from entries: [StoredZipEntry], entryMap: [String: Data]) -> (records: [DownloadRecord], files: [BackupFile]) {
        let rows = sqliteRows(named: "download/download.db", in: entryMap, query: "select id, title, subtitle, time, directory, size, json from download order by time desc;")
        let fileEntries = entries
            .filter { $0.path.hasPrefix("download/") && !$0.path.hasSuffix("/") }
            .reduce(into: [String: Data]()) { result, entry in
                result[entry.path] = result[entry.path] ?? entry.data
            }
        var records: [DownloadRecord] = []
        var files: [BackupFile] = []

        for row in rows {
            guard let metadata = downloadedMetadata(from: row),
                  let directory = row["directory"]?.stringValue,
                  !directory.isEmpty else {
                continue
            }
            let copied = copiedDownloadFiles(
                originalDirectory: directory,
                metadata: metadata,
                fileEntries: fileEntries
            )
            guard !copied.chapters.isEmpty else { continue }
            files.append(contentsOf: copied.files)
            let item = ComicListItem(
                id: metadata.id,
                platform: metadata.platform,
                title: metadata.title,
                subtitle: metadata.subtitle,
                coverURLString: metadata.coverURLString,
                tags: metadata.tags,
                pageCount: copied.chapters.first?.pageCount,
                likesCount: nil,
                favoriteDate: nil
            )
            let updatedAt = date(milliseconds: row["time"]?.intValue) ?? Date()
            records.append(DownloadRecord(
                item: item,
                chapters: copied.chapters,
                totalChapterCount: max(metadata.chapterTitles.count, copied.chapters.count),
                totalBytes: copied.chapters.reduce(0) { $0 + $1.bytes },
                directoryName: directoryName(for: item),
                coverFileName: copied.coverFileName,
                detail: nil,
                comments: [],
                updatedAt: updatedAt
            ))
        }

        return (records, files)
    }

    private static func copiedDownloadFiles(
        originalDirectory: String,
        metadata: PicaComicDownloadMetadata,
        fileEntries: [String: Data]
    ) -> (chapters: [DownloadedChapterRecord], files: [BackupFile], coverFileName: String?) {
        let originalPrefix = "download/\(originalDirectory)/"
        let item = ComicListItem(
            id: metadata.id,
            platform: metadata.platform,
            title: metadata.title,
            subtitle: metadata.subtitle,
            coverURLString: metadata.coverURLString,
            tags: metadata.tags,
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
        let baseDirectory = directoryName(for: item)
        var files: [BackupFile] = []
        var grouped: [Int: [(String, Data)]] = [:]
        var coverFileName: String?

        for (path, data) in fileEntries where path.hasPrefix(originalPrefix) {
            let relative = String(path.dropFirst(originalPrefix.count))
            guard !relative.isEmpty else { continue }
            let components = relative.split(separator: "/").map(String.init)
            guard let fileName = components.last,
                  isImageFileName(fileName) else {
                continue
            }
            if components.count == 1, fileName.lowercased().hasPrefix("cover") {
                coverFileName = fileName
                files.append(BackupFile(relativePath: "\(baseDirectory)/\(fileName)", data: data.base64EncodedString()))
                continue
            }
            if components.count > 1, let chapter = Int(components[0]) {
                grouped[max(chapter - 1, 0), default: []].append((fileName, data))
            } else if components.count == 1 {
                grouped[0, default: []].append((fileName, data))
            }
        }

        let downloadedIndexes = Set(metadata.downloadedChapterIndexes)
        var chapters: [DownloadedChapterRecord] = []
        for (chapterIndex, imageFiles) in grouped.sorted(by: { $0.key < $1.key }) {
            if !downloadedIndexes.isEmpty, !downloadedIndexes.contains(chapterIndex) {
                continue
            }
            let chapterTitle = metadata.chapterTitles.element(at: chapterIndex) ?? "第\(chapterIndex + 1)章"
            let chapter = ComicChapter(id: "\(metadata.platform.id)-\(metadata.id)-\(chapterIndex + 1)", title: chapterTitle, subtitle: nil)
            let chapterDirectory = "\(baseDirectory)/\(String(format: "%03d-%@", chapterIndex + 1, safeFileName(chapterTitle)))"
            var bytes: Int64 = 0
            let sortedImages = imageFiles.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            for (pageIndex, file) in sortedImages.enumerated() {
                bytes += Int64(file.1.count)
                let ext = URL(fileURLWithPath: file.0).pathExtension.nonEmptyValue ?? "jpg"
                let newName = String(format: "%04d.%@", pageIndex + 1, ext)
                files.append(BackupFile(relativePath: "\(chapterDirectory)/\(newName)", data: file.1.base64EncodedString()))
            }
            chapters.append(DownloadedChapterRecord(
                index: chapterIndex,
                chapter: chapter,
                pageCount: sortedImages.count,
                bytes: bytes,
                downloadedAt: Date()
            ))
        }

        return (chapters, files, coverFileName)
    }

    private static func downloadedMetadata(from row: [String: PicaComicSQLiteValue]) -> PicaComicDownloadMetadata? {
        guard let rawID = row["id"]?.stringValue,
              let title = row["title"]?.stringValue else {
            return nil
        }
        let json = row["json"]?.stringValue.flatMap { $0.data(using: .utf8) }
        let object = json.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let platform = platform(downloadID: rawID)
        let id = normalizedComicID(rawID, platform: platform, json: object)
        let subtitle = row["subtitle"]?.stringValue ?? ""
        let tags = downloadedTags(platform: platform, json: object)
        let chapterTitles = downloadedChapterTitles(platform: platform, json: object)
        let downloadedIndexes = intArray(object["downloadedChapters"] ?? object["downloadedEps"])
        let coverURLString = downloadedCover(platform: platform, json: object)
        return PicaComicDownloadMetadata(
            platform: platform,
            id: id,
            title: title,
            subtitle: subtitle,
            tags: tags,
            chapterTitles: chapterTitles.isEmpty ? ["第一章"] : chapterTitles,
            downloadedChapterIndexes: downloadedIndexes,
            coverURLString: coverURLString
        )
    }

    private static func favoriteRows(from entries: [String: Data]) -> [[String: PicaComicSQLiteValue]] {
        guard let data = entries["local_favorite.db"] ?? entries["local_favorite_temp.db"] else {
            return []
        }
        guard let db = try? PicaComicSQLiteDatabase(data: data, fileName: "local_favorite.db") else {
            return []
        }
        let tableRows = (try? db.rows("select name from sqlite_master where type='table';")) ?? []
        let tables = tableRows
            .compactMap { $0["name"]?.stringValue }
            .filter { $0 != "folder_sync" && $0 != "folder_order" }
        return tables.flatMap { table in
            (try? db.rows("select target, name, author, type, tags, cover_path, time from \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\";")) ?? []
        }
    }

    private static func sqliteRows(named name: String, in entries: [String: Data], query: String) -> [[String: PicaComicSQLiteValue]] {
        guard let data = entries[name],
              let db = try? PicaComicSQLiteDatabase(data: data, fileName: URL(fileURLWithPath: name).lastPathComponent) else {
            return []
        }
        return (try? db.rows(query)) ?? []
    }

    private static func platform(sourceKey: String) -> ComicPlatform? {
        switch sourceKey {
        case "picacg":
            .picacg
        case "jm":
            .jmComic
        case "nhentai":
            .nhentai
        case "ehentai":
            .eHentai
        case "hitomi":
            .hitomi
        case "htmanga":
            .htManga
        default:
            nil
        }
    }

    private static func platform(type: Int?) -> ComicPlatform? {
        switch type {
        case 0:
            .picacg
        case 1:
            .eHentai
        case 2:
            .jmComic
        case 3:
            .hitomi
        case 4:
            .htManga
        case 5, 6:
            .nhentai
        default:
            nil
        }
    }

    private static func platform(downloadID: String) -> ComicPlatform {
        if downloadID.starts(with: "jm") { return .jmComic }
        if downloadID.starts(with: "hitomi") { return .hitomi }
        if downloadID.starts(with: "nhentai") { return .nhentai }
        if downloadID.starts(with: "Ht") { return .htManga }
        if downloadID.allSatisfy(\.isNumber) { return .eHentai }
        if let prefix = downloadID.split(separator: "-").first,
           let platform = platform(sourceKey: String(prefix)) {
            return platform
        }
        return .picacg
    }

    private static func normalizedComicID(_ value: String, platform: ComicPlatform, json: [String: Any] = [:]) -> String {
        switch platform {
        case .jmComic:
            if let id = (json["comic"] as? [String: Any])?["id"] as? String {
                return id
            }
            return value.removingPrefix("jm")
        case .hitomi:
            return firstNumber(in: value) ?? value.removingPrefix("hitomi")
        case .htManga:
            if let id = (json["comic"] as? [String: Any])?["id"] as? String {
                return id
            }
            return value.removingPrefix("Ht")
        case .nhentai:
            return firstNumber(in: value) ?? value.removingPrefix("nhentai")
        case .picacg, .eHentai:
            return value
        }
    }

    private static func downloadedTags(platform: ComicPlatform, json: [String: Any]) -> [String] {
        switch platform {
        case .picacg:
            return stringArray((json["comicItem"] as? [String: Any])?["tags"]) ?? []
        case .jmComic:
            return stringArray((json["comic"] as? [String: Any])?["tags"]) ?? []
        case .hitomi:
            let values = ((json["comic"] as? [String: Any])?["tags"] as? [[String: Any]]) ?? []
            return values.compactMap { $0["name"] as? String }
        case .eHentai:
            let tagGroups = (json["gallery"] as? [String: Any])?["tags"] as? [String: Any] ?? [:]
            return tagGroups.values.flatMap { stringArray($0) ?? [] }
        case .htManga:
            let tagGroups = (json["comic"] as? [String: Any])?["tags"] as? [String: Any] ?? [:]
            return Array(tagGroups.keys)
        case .nhentai:
            return stringArray(json["tags"]) ?? []
        }
    }

    private static func downloadedChapterTitles(platform: ComicPlatform, json: [String: Any]) -> [String] {
        switch platform {
        case .picacg:
            return stringArray(json["chapters"]) ?? []
        case .jmComic:
            let comic = json["comic"] as? [String: Any] ?? [:]
            if let epNames = stringArray(comic["epNames"]), !epNames.isEmpty {
                return epNames
            }
            if let series = comic["series"] as? [Any], !series.isEmpty {
                return series.indices.map { "第\($0 + 1)章" }
            }
            return []
        default:
            return []
        }
    }

    private static func downloadedCover(platform: ComicPlatform, json: [String: Any]) -> String {
        switch platform {
        case .nhentai:
            return json["cover"] as? String ?? ""
        case .hitomi:
            return json["cover"] as? String ?? ""
        case .eHentai:
            return (json["gallery"] as? [String: Any])?["cover"] as? String ?? ""
        case .htManga:
            return (json["comic"] as? [String: Any])?["coverPath"] as? String ?? ""
        case .jmComic:
            let id = (json["comic"] as? [String: Any])?["id"] as? String ?? ""
            return id.isEmpty ? "" : "https://cdn-msp.jmapiproxyxxx.vip/media/albums/\(id)_3x4.jpg"
        case .picacg:
            return ""
        }
    }

    private static func accountUsername(accountData: Any?, json: [String: Any], fallback: String) -> String {
        if let list = accountData as? [Any], let username = list.first as? String, !username.isEmpty {
            return username
        }
        if let name = json["name"] as? String, !name.isEmpty {
            return name
        }
        if let user = json["user"] as? [String: Any] {
            return (user["email"] as? String)?.nonEmptyValue
                ?? (user["name"] as? String)?.nonEmptyValue
                ?? fallback
        }
        return fallback
    }

    private static func accountProfile(platform: ComicPlatform, json: [String: Any], username: String) -> PlatformAccountProfile? {
        if let user = json["user"] as? [String: Any] {
            return PlatformAccountProfile(
                email: user["email"] as? String,
                username: user["_id"] as? String ?? username,
                nickname: user["name"] as? String
            )
        }
        if let name = json["name"] as? String, !name.isEmpty {
            return PlatformAccountProfile(email: nil, username: username, nickname: name)
        }
        return PlatformAccountProfile(email: nil, username: username, nickname: platform.title)
    }

    private static func platformToken(platform: ComicPlatform, json: [String: Any], cookies: [StoredHTTPCookie]) -> String? {
        switch platform {
        case .picacg:
            return firstString(json, keys: ["token", "authorization", "access_token"]) ?? cookieValue(named: "token", in: cookies) ?? cookieValue(named: "access_token", in: cookies)
        case .nhentai:
            return cookieValue(named: "access_token", in: cookies)
        case .jmComic, .eHentai, .hitomi, .htManga:
            return nil
        }
    }

    private static func platformRefreshToken(platform: ComicPlatform, cookies: [StoredHTTPCookie]) -> String? {
        switch platform {
        case .nhentai:
            return cookieValue(named: "refresh_token", in: cookies)
        case .picacg, .jmComic, .eHentai, .hitomi, .htManga:
            return nil
        }
    }

    private static func platformTokenType(platform: ComicPlatform, token: String?) -> String? {
        guard token?.nonEmptyValue != nil else { return nil }
        switch platform {
        case .nhentai:
            return "User"
        case .picacg, .jmComic, .eHentai, .hitomi, .htManga:
            return nil
        }
    }

    private static func firstString(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func cookieValue(named name: String, in cookies: [StoredHTTPCookie]) -> String? {
        cookies.first { $0.name == name }?.value.nonEmptyValue
    }

    private static func cookiesForPlatform(_ platform: ComicPlatform, rows: [[String: PicaComicSQLiteValue]]) -> [StoredHTTPCookie] {
        let hosts: [String] = switch platform {
        case .nhentai:
            ["nhentai.net", ".nhentai.net"]
        case .eHentai:
            ["e-hentai.org", ".e-hentai.org", "exhentai.org", ".exhentai.org"]
        case .htManga:
            ["wnacg.com", ".wnacg.com", "www.wnacg.com", ".www.wnacg.com"]
        case .hitomi:
            ["hitomi.la", ".hitomi.la"]
        case .picacg:
            ["picacomic.com", ".picacomic.com", "picaapi.picacomic.com", ".picaapi.picacomic.com"]
        case .jmComic:
            []
        }
        guard !hosts.isEmpty else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"]?.stringValue,
                  let value = row["value"]?.stringValue,
                  let domain = row["domain"]?.stringValue else {
                return nil
            }
            if platform == .eHentai,
               ["ipb_member_id", "ipb_pass_hash", "igneous", "star"].contains(name) {
                return storedCookie(row: row, name: name, value: value, domain: domain)
            }
            guard hosts.contains(where: { cookieDomain(domain, matchesHost: $0) }) else {
                return nil
            }
            return storedCookie(row: row, name: name, value: value, domain: domain)
        }
    }

    private static func storedCookie(row: [String: PicaComicSQLiteValue], name: String, value: String, domain: String) -> StoredHTTPCookie {
        StoredHTTPCookie(
            name: name,
            value: value,
            domain: domain,
            path: row["path"]?.stringValue ?? "/",
            expiresDate: cookieExpiresDate(row["expires"]?.intValue),
            isSecure: row["secure"]?.intValue == 1
        )
    }

    private static func cookieExpiresDate(_ milliseconds: Int?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return date(milliseconds: milliseconds)
    }

    private static func normalizedCookiesForPlatform(_ platform: ComicPlatform, cookies: [StoredHTTPCookie]) -> [StoredHTTPCookie] {
        guard platform == .eHentai else { return cookies }
        let ehentaiDomains = [".e-hentai.org", ".exhentai.org"]
        var result = cookies
        for cookie in cookies where ["ipb_member_id", "ipb_pass_hash", "igneous", "star"].contains(cookie.name) {
            for domain in ehentaiDomains {
                var copy = cookie
                copy.domain = domain
                result.append(copy)
            }
        }
        return Dictionary(grouping: result, by: \.id)
            .compactMap { $0.value.first }
            .sorted { $0.id < $1.id }
    }

    private static func cookieDomain(_ domain: String, matchesHost host: String) -> Bool {
        let normalizedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingPrefix(".")
        let normalizedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingPrefix(".")
        guard !normalizedDomain.isEmpty, !normalizedHost.isEmpty else { return false }
        return normalizedDomain == normalizedHost || normalizedDomain.hasSuffix(".\(normalizedHost)") || normalizedHost.hasSuffix(".\(normalizedDomain)")
    }

    private static func stringSetting(_ settings: [Any], at index: Int) -> String? {
        settings.element(at: index) as? String
    }

    private static func intSetting(_ settings: [Any], at index: Int) -> Int? {
        if let value = settings.element(at: index) as? Int { return value }
        if let value = settings.element(at: index) as? String { return Int(value) }
        return nil
    }

    private static func boolSetting(_ settings: [Any], at index: Int) -> Bool? {
        guard let value = stringSetting(settings, at: index) else { return nil }
        if value == "1" { return true }
        if value == "0" { return false }
        return nil
    }

    private static func readerReadingMode(from value: String?) -> ReaderReadingMode? {
        switch value {
        case "1":
            .leftToRight
        case "2":
            .rightToLeft
        case "3":
            .topToBottom
        case "4":
            .topToBottomContinuous
        default:
            nil
        }
    }

    private static func jmAPIEndpoint(from index: Int?) -> JmAPIEndpoint? {
        switch index {
        case 0:
            .cdnTwice
        case 1:
            .cdnSha
        case 2:
            .cdnAspa
        case 3:
            .cdnNtr
        default:
            nil
        }
    }

    private static func jmImageEndpoint(from index: Int?) -> JmImageEndpoint? {
        switch index {
        case 0:
            .mspProxy1
        case 1:
            .mspProxy3
        case 2:
            .mspProxy2
        case 3:
            .mspProxy3Backup
        default:
            nil
        }
    }

    private static func ehentaiFrontendBaseURL(from value: String?) -> String? {
        switch value {
        case "0":
            EhentaiSite.eHentai.rawValue
        case "1":
            EhentaiSite.exhentai.rawValue
        default:
            nil
        }
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return nil
    }

    private static func intArray(_ value: Any?) -> [Int] {
        if let values = value as? [Int] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap {
                if let value = $0 as? Int { return value }
                if let value = $0 as? String { return Int(value) }
                return nil
            }
        }
        return []
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func tags(from value: String?) -> [String] {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func readEpisodeSet(_ value: String?) -> Set<Int> {
        Set(value?
            .split(separator: ",")
            .compactMap { Int($0) } ?? [])
    }

    private static func date(milliseconds: Int?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private static func date(string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return dateFormatter.date(from: string)
    }

    private static func normalizedURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func firstNumber(in value: String) -> String? {
        value.range(of: #"\d+"#, options: .regularExpression).map { String(value[$0]) }
    }

    private static func directoryName(for item: ComicListItem) -> String {
        "\(item.platform.rawValue)/\(safeFileName("\(item.id)-\(item.title)"))"
    }

    private static func safeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : String(cleaned.prefix(80))
    }

    private static func isImageFileName(_ value: String) -> Bool {
        switch URL(fileURLWithPath: value).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "gif":
            true
        default:
            false
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct PicaComicDownloadMetadata {
    let platform: ComicPlatform
    let id: String
    let title: String
    let subtitle: String
    let tags: [String]
    let chapterTitles: [String]
    let downloadedChapterIndexes: [Int]
    let coverURLString: String
}

private struct PicaComicStoredLocalFavorite: Codable {
    let id: String
    let platform: ComicPlatform
    let title: String
    let subtitle: String
    let coverURLString: String
    let tags: [String]
    let pageCount: Int?
    let likesCount: Int?
    let favoriteDate: Date?
}

private enum PicaComicImportError: LocalizedError {
    case missingAppData
    case invalidAppData
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .missingAppData:
            "未找到 PicaComic 备份数据。"
        case .invalidAppData:
            "PicaComic 备份数据无法读取。"
        case .emptyBackup:
            "此备份中没有可导入的内容。"
        }
    }
}

private enum PicaComicSQLiteValue {
    case null
    case integer(Int)
    case double(Double)
    case string(String)
    case blob(Data)

    var stringValue: String? {
        switch self {
        case .string(let value):
            value
        case .integer(let value):
            String(value)
        case .double(let value):
            String(value)
        case .null, .blob:
            nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value):
            value
        case .double(let value):
            Int(value)
        case .string(let value):
            Int(value)
        case .null, .blob:
            nil
        }
    }
}

private final class PicaComicSQLiteDatabase {
    private var database: OpaquePointer?
    private let url: URL

    init(data: Data, fileName: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaComicImport-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw PicaComicImportError.invalidAppData
        }
    }

    deinit {
        sqlite3_close(database)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func rows(_ query: String) throws -> [[String: PicaComicSQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }

        var result: [[String: PicaComicSQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: PicaComicSQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let namePointer = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: namePointer)
                row[name] = value(statement: statement, index: index)
            }
            result.append(row)
        }
        return result
    }

    private func value(statement: OpaquePointer?, index: Int32) -> PicaComicSQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .string(String(cString: text))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return .null }
            return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))))
        default:
            return .null
        }
    }
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func trimmingPrefix(_ prefix: String) -> String {
        var value = self
        while value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        return value
    }
}

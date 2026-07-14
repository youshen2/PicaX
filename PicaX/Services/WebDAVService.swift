import Combine
import Foundation
import Security

struct WebDAVConfiguration: Sendable {
    let baseURL: URL
    let username: String
    let password: String
    let remoteDirectory: String

    init(serverURL: String, username: String, password: String, remoteDirectory: String) throws {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw WebDAVError.invalidServerURL
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else {
            throw WebDAVError.invalidServerURL
        }

        let directory = remoteDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." }
            .joined(separator: "/")

        baseURL = url
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.remoteDirectory = directory.isEmpty ? WebDAVSettingsKey.defaultRemoteDirectory : directory
    }

    var displayServerURL: String {
        baseURL.absoluteString
    }
}

struct WebDAVRemoteBackup: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let modifiedAt: Date?
    let size: Int64?
}

enum WebDAVError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case keychain(OSStatus)
    case notConfigured
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "请输入完整的 HTTP 或 HTTPS WebDAV 地址。"
        case .invalidResponse:
            "WebDAV 服务器返回了无法识别的响应。"
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                "WebDAV 请求失败（HTTP \(statusCode)）：\(message)"
            } else {
                "WebDAV 请求失败（HTTP \(statusCode)）。"
            }
        case .keychain(let status):
            "无法访问 Keychain（错误 \(status)）。"
        case .notConfigured:
            "请先填写并保存 WebDAV 配置。"
        case .operationInProgress:
            "另一项 WebDAV 操作仍在进行中。"
        }
    }
}

enum WebDAVConfigurationStore {
    static func load(defaults: UserDefaults = .standard) throws -> WebDAVConfiguration {
        let serverURL = defaults.string(forKey: WebDAVSettingsKey.serverURL) ?? ""
        guard !serverURL.isEmpty else { throw WebDAVError.notConfigured }
        return try WebDAVConfiguration(
            serverURL: serverURL,
            username: defaults.string(forKey: WebDAVSettingsKey.username) ?? "",
            password: try WebDAVCredentialStore.password(),
            remoteDirectory: defaults.string(forKey: WebDAVSettingsKey.remoteDirectory)
                ?? WebDAVSettingsKey.defaultRemoteDirectory
        )
    }

    static func save(
        serverURL: String,
        username: String,
        password: String,
        remoteDirectory: String,
        defaults: UserDefaults = .standard
    ) throws -> WebDAVConfiguration {
        let configuration = try WebDAVConfiguration(
            serverURL: serverURL,
            username: username,
            password: password,
            remoteDirectory: remoteDirectory
        )
        try WebDAVCredentialStore.save(password: configuration.password)
        defaults.set(configuration.displayServerURL, forKey: WebDAVSettingsKey.serverURL)
        defaults.set(configuration.username, forKey: WebDAVSettingsKey.username)
        defaults.set(configuration.remoteDirectory, forKey: WebDAVSettingsKey.remoteDirectory)
        return configuration
    }
}

private enum WebDAVCredentialStore {
    private static let service = "moye.PicaX.WebDAV"
    private static let account = "password"

    static func password() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WebDAVError.keychain(status)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(password: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WebDAVError.keychain(status)
        }
    }
}

struct WebDAVClient {
    let configuration: WebDAVConfiguration
    var session: URLSession = .shared

    func testConnection() async throws {
        try await ensureRemoteDirectory()
        _ = try await listBackups()
    }

    func listBackups() async throws -> [WebDAVRemoteBackup] {
        try await ensureRemoteDirectory()
        var request = makeRequest(url: remoteDirectoryURL, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:resourcetype/><d:getlastmodified/><d:getcontentlength/></d:prop>
        </d:propfind>
        """.utf8)
        let (data, _) = try await perform(request, acceptedStatusCodes: [207])
        let entries = try WebDAVMultiStatusParser.parse(data)
        return entries
            .filter { !$0.isCollection }
            .compactMap { entry -> WebDAVRemoteBackup? in
                guard let name = entry.name,
                      name.lowercased().hasSuffix(".picax"),
                      name != WebDAVSettingsKey.syncFileName else { return nil }
                return WebDAVRemoteBackup(name: name, modifiedAt: entry.modifiedAt, size: entry.size)
            }
            .sorted { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
    }

    func upload(_ data: Data, named fileName: String) async throws {
        try await ensureRemoteDirectory()
        var request = makeRequest(url: fileURL(named: fileName), method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await perform(request, acceptedStatusCodes: [200, 201, 204])
    }

    func download(named fileName: String) async throws -> Data {
        let request = makeRequest(url: fileURL(named: fileName), method: "GET")
        return try await perform(request, acceptedStatusCodes: [200]).0
    }

    func downloadIfPresent(named fileName: String) async throws -> Data? {
        let request = makeRequest(url: fileURL(named: fileName), method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else {
            throw requestError(response: response, data: data)
        }
        return data
    }

    func delete(_ backup: WebDAVRemoteBackup) async throws {
        let request = makeRequest(url: fileURL(named: backup.name), method: "DELETE")
        _ = try await perform(request, acceptedStatusCodes: [200, 204])
    }

    private func ensureRemoteDirectory() async throws {
        var currentURL = configuration.baseURL
        for component in configuration.remoteDirectory.split(separator: "/") {
            currentURL.appendPathComponent(String(component), isDirectory: true)
            let request = makeRequest(url: currentURL, method: "MKCOL")
            _ = try await perform(request, acceptedStatusCodes: [200, 201, 204, 405])
        }
    }

    private var remoteDirectoryURL: URL {
        configuration.remoteDirectory.split(separator: "/").reduce(configuration.baseURL) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    private func fileURL(named fileName: String) -> URL {
        remoteDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        if !configuration.username.isEmpty || !configuration.password.isEmpty {
            let credentials = Data("\(configuration.username):\(configuration.password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest, acceptedStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard acceptedStatusCodes.contains(response.statusCode) else {
            throw requestError(response: response, data: data)
        }
        return (data, response)
    }

    private func requestError(response: HTTPURLResponse, data: Data) -> WebDAVError {
        let message = String(data: data.prefix(300), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .requestFailed(statusCode: response.statusCode, message: message)
    }
}

@MainActor
final class WebDAVSyncService: ObservableObject {
    enum Activity: Equatable {
        case idle
        case testing
        case loading
        case backingUp
        case syncing
        case downloading(String)
        case deleting(String)

        var title: String? {
            switch self {
            case .idle: nil
            case .testing: "正在测试连接"
            case .loading: "正在刷新"
            case .backingUp: "正在备份"
            case .syncing: "正在同步"
            case .downloading: "正在下载"
            case .deleting: "正在删除"
            }
        }
    }

    @Published private(set) var activity = Activity.idle
    @Published private(set) var backups: [WebDAVRemoteBackup] = []
    @Published private(set) var lastAutomaticSyncError: String?

    var isBusy: Bool { activity != .idle }

    func test(configuration: WebDAVConfiguration) async throws {
        try begin(.testing)
        defer { activity = .idle }
        try await WebDAVClient(configuration: configuration).testConnection()
    }

    func refresh(configuration: WebDAVConfiguration) async throws {
        try begin(.loading)
        defer { activity = .idle }
        backups = try await WebDAVClient(configuration: configuration).listBackups()
    }

    func createBackup(configuration: WebDAVConfiguration, includedContent: Set<BackupContentKind>) async throws -> String {
        try begin(.backingUp)
        defer { activity = .idle }
        let fileName = "PicaX-Backup-\(Self.fileNameFormatter.string(from: Date())).picax"
        let data = try await BackupService.makeData(includedContent: includedContent)
        let client = WebDAVClient(configuration: configuration)
        try await client.upload(data, named: fileName)
        backups = try await client.listBackups()
        return fileName
    }

    func synchronize(configuration: WebDAVConfiguration, includedContent: Set<BackupContentKind>) async throws {
        try begin(.syncing)
        defer { activity = .idle }
        try await synchronizeWithoutActivity(configuration: configuration, includedContent: includedContent)
    }

    func download(_ backup: WebDAVRemoteBackup, configuration: WebDAVConfiguration) async throws -> BackupImportPreview {
        try begin(.downloading(backup.name))
        defer { activity = .idle }
        let data = try await WebDAVClient(configuration: configuration).download(named: backup.name)
        let preview = try BackupService.preview(from: data)
        return BackupImportPreview(backup: preview.backup, data: data, sourceTitle: "WebDAV · \(backup.name)")
    }

    func delete(_ backup: WebDAVRemoteBackup, configuration: WebDAVConfiguration) async throws {
        try begin(.deleting(backup.name))
        defer { activity = .idle }
        let client = WebDAVClient(configuration: configuration)
        try await client.delete(backup)
        backups = try await client.listBackups()
    }

    func synchronizeAutomaticallyIfNeeded(defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: WebDAVSettingsKey.automaticSyncEnabled), !isBusy else { return }
        let lastSyncTimestamp = defaults.double(forKey: WebDAVSettingsKey.lastSuccessfulSyncAt)
        if lastSyncTimestamp > 0,
           Date().timeIntervalSince1970 - lastSyncTimestamp < 15 * 60 {
            return
        }

        do {
            let configuration = try WebDAVConfigurationStore.load(defaults: defaults)
            let rawSelection = defaults.string(forKey: WebDAVSettingsKey.syncContentSelection)
                ?? WebDAVSyncContentSettings.defaultRawValue
            let includedContent = WebDAVSyncContentSettings.selection(from: rawSelection)
            guard !includedContent.isEmpty else { return }
            try begin(.syncing)
            defer { activity = .idle }
            try await synchronizeWithoutActivity(
                configuration: configuration,
                includedContent: includedContent,
                defaults: defaults
            )
            lastAutomaticSyncError = nil
        } catch {
            lastAutomaticSyncError = error.localizedDescription
        }
    }

    private func synchronizeWithoutActivity(
        configuration: WebDAVConfiguration,
        includedContent: Set<BackupContentKind>,
        defaults: UserDefaults = .standard
    ) async throws {
        let client = WebDAVClient(configuration: configuration)
        if let remoteData = try await client.downloadIfPresent(named: WebDAVSettingsKey.syncFileName) {
            let preview = try BackupService.preview(from: remoteData)
            let backup = BackupService.filteredBackup(preview.backup, includedContent: includedContent)
            if !backup.contentSelection.isEmpty {
                try await BackupService.importBackup(backup, mode: .merge, defaults: defaults)
                NotificationCenter.default.post(name: .picaxBackupDidImport, object: nil)
            }
        }

        let mergedData = try await BackupService.makeData(includedContent: includedContent, defaults: defaults)
        try await client.upload(mergedData, named: WebDAVSettingsKey.syncFileName)
        defaults.set(Date().timeIntervalSince1970, forKey: WebDAVSettingsKey.lastSuccessfulSyncAt)
        backups = try await client.listBackups()
    }

    private func begin(_ nextActivity: Activity) throws {
        guard activity == .idle else { throw WebDAVError.operationInProgress }
        activity = nextActivity
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}

private struct WebDAVMultiStatusEntry {
    var href = ""
    var modifiedAt: Date?
    var size: Int64?
    var isCollection = false

    var name: String? {
        let decodedPath = href.removingPercentEncoding ?? href
        return decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init)
    }
}

private final class WebDAVMultiStatusParser: NSObject, XMLParserDelegate {
    private var entries: [WebDAVMultiStatusEntry] = []
    private var currentEntry: WebDAVMultiStatusEntry?
    private var text = ""

    static func parse(_ data: Data) throws -> [WebDAVMultiStatusEntry] {
        let delegate = WebDAVMultiStatusParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? WebDAVError.invalidResponse
        }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.localName(qName ?? elementName)
        text = ""
        if name == "response" {
            currentEntry = WebDAVMultiStatusEntry()
        } else if name == "collection" {
            currentEntry?.isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.localName(qName ?? elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "href":
            currentEntry?.href = value
        case "getlastmodified":
            currentEntry?.modifiedAt = Self.httpDateFormatter.date(from: value)
        case "getcontentlength":
            currentEntry?.size = Int64(value)
        case "response":
            if let currentEntry {
                entries.append(currentEntry)
            }
            currentEntry = nil
        default:
            break
        }
        text = ""
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter
    }()
}

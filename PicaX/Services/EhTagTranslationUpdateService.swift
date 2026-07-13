import Combine
import Foundation

enum EhTagTranslationUpdateError: LocalizedError {
    case invalidResponse
    case requestFailed(resource: String, statusCode: Int)
    case invalidText(resource: String)
    case invalidDatabase

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "标签数据库返回了无法识别的响应。"
        case let .requestFailed(resource, statusCode):
            "下载 \(resource) 失败（HTTP \(statusCode)）。"
        case let .invalidText(resource):
            "标签数据库中的 \(resource) 格式无效。"
        case .invalidDatabase:
            "下载的标签数据不完整，已继续使用当前数据库。"
        }
    }
}

@MainActor
final class EhTagTranslationUpdateService: ObservableObject {
    @Published private(set) var info = EhTagTranslationService.databaseInfo
    @Published private(set) var isUpdating = false
    @Published private(set) var statusMessage: String?

    nonisolated private static let databaseNamespaces = [
        "rows",
        "artist",
        "character",
        "cosplayer",
        "female",
        "group",
        "language",
        "location",
        "male",
        "mixed",
        "other",
        "parody",
        "reclass"
    ]
    nonisolated private static let rawRoot = URL(string: "https://raw.githubusercontent.com/EhTagTranslation/Database/master")!

    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        statusMessage = nil
        defer { isUpdating = false }

        do {
            let session = AppNetworkSettings.makeSession()
            async let version = Self.downloadText(path: "version", session: session)
            let translations = try await Self.downloadDatabase(session: session)
            let downloadedVersion = try await version.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !downloadedVersion.isEmpty else {
                throw EhTagTranslationUpdateError.invalidText(resource: "version")
            }
            try EhTagTranslationService.installDownloadedDatabase(
                translations,
                version: downloadedVersion
            )
            info = EhTagTranslationService.databaseInfo
            statusMessage = "标签翻译库已更新。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restoreBundled() {
        do {
            try EhTagTranslationService.restoreBundledDatabase()
            info = EhTagTranslationService.databaseInfo
            statusMessage = "已恢复使用内置标签翻译库。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    nonisolated private static func downloadDatabase(
        session: URLSession
    ) async throws -> [String: [String: String]] {
        try await withThrowingTaskGroup(
            of: (String, [String: String]).self,
            returning: [String: [String: String]].self
        ) { group in
            for namespace in databaseNamespaces {
                group.addTask {
                    let resource = "database/\(namespace).md"
                    let text = try await downloadText(path: resource, session: session)
                    let translations = parseMarkdownTable(text)
                    guard !translations.isEmpty else {
                        throw EhTagTranslationUpdateError.invalidText(resource: resource)
                    }
                    return (namespace, translations)
                }
            }

            var result: [String: [String: String]] = [:]
            for try await (namespace, translations) in group {
                result[namespace] = translations
            }
            return result
        }
    }

    nonisolated private static func downloadText(path: String, session: URLSession) async throws -> String {
        let url = rawRoot.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("PicaX", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw EhTagTranslationUpdateError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw EhTagTranslationUpdateError.requestFailed(resource: path, statusCode: response.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw EhTagTranslationUpdateError.invalidText(resource: path)
        }
        return text
    }

    nonisolated private static func parseMarkdownTable(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("|") else { continue }
            let cells = markdownCells(in: trimmedLine)
            guard cells.count >= 2 else { continue }
            let rawTag = cells[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let translatedTitle = cells[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTag.isEmpty,
                  !translatedTitle.isEmpty,
                  rawTag != "原始标签",
                  !rawTag.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                continue
            }
            result[rawTag] = translatedTitle
        }
        return result
    }

    nonisolated private static func markdownCells(in line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in line {
            if isEscaped {
                if character != "|" {
                    current.append("\\")
                }
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }
        if isEscaped {
            current.append("\\")
        }
        cells.append(current)
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }
}

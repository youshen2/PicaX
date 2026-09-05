import Foundation

nonisolated enum ClashYAMLImportWorker {
    static func parse(
        text: String
    ) async throws -> ClashYAMLProxyParser.ParseResult {
        try await Task.detached(priority: .userInitiated) {
            try ClashYAMLProxyParser.parse(text)
        }.value
    }

    static func parse(
        fileURL: URL
    ) async throws -> ClashYAMLProxyParser.ParseResult {
        try await Task.detached(priority: .userInitiated) {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            let resourceValues = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
            guard resourceValues.isRegularFile != false else {
                throw ImportError.notAFile
            }
            if let fileSize = resourceValues.fileSize,
               fileSize > maximumDocumentSize {
                throw ClashYAMLProxyParser.ParseError.tooLarge
            }
            let data = try Data(
                contentsOf: fileURL,
                options: [.mappedIfSafe]
            )
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.notUTF8
            }
            return try ClashYAMLProxyParser.parse(text)
        }.value
    }

    enum ImportError: LocalizedError {
        case notAFile
        case notUTF8

        var errorDescription: String? {
            switch self {
            case .notAFile:
                return "所选项目不是 YAML 文件。"
            case .notUTF8:
                return "YAML 文件不是 UTF-8 文本。"
            }
        }
    }

    static let maximumDocumentSize = 5 * 1_024 * 1_024
}

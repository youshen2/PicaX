import Foundation

struct AppReleaseNotes: Equatable, Identifiable, Sendable {
    let version: String
    let sourceRevision: String
    let previousVersion: String?
    let entries: [String]

    var id: String {
        "\(version)-\(sourceRevision)"
    }

    var displayVersion: String {
        AppVersion.displayName(for: version)
    }

    var displayPreviousVersion: String? {
        guard let previousVersion else { return nil }
        return AppVersion.displayName(for: previousVersion)
    }
}

enum AppReleaseNotesLoader {
    static func load(from bundle: Bundle = .main) -> AppReleaseNotes? {
        guard let metadataURL = bundle.url(forResource: "ReleaseNotes", withExtension: "json"),
              let markdownURL = bundle.url(forResource: "ReleaseNotes", withExtension: "md"),
              let metadataData = try? Data(contentsOf: metadataURL),
              let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            return nil
        }

        return parse(metadataData: metadataData, markdown: markdown)
    }

    static func parse(metadataData: Data, markdown: String) -> AppReleaseNotes? {
        guard let metadata = try? JSONDecoder().decode(AppReleaseNotesMetadata.self, from: metadataData),
              metadata.schemaVersion == 2,
              !metadata.version.isEmpty,
              !metadata.sourceRevision.isEmpty else {
            return nil
        }

        let entries = markdown
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let normalizedLine = String(line).trimmingCharacters(in: .whitespaces)
                guard normalizedLine.hasPrefix("- ") else { return nil }

                let entry = String(normalizedLine.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
                return entry.isEmpty ? nil : entry
            }
        guard !entries.isEmpty else { return nil }

        return AppReleaseNotes(
            version: metadata.version,
            sourceRevision: metadata.sourceRevision,
            previousVersion: metadata.previousVersion,
            entries: entries
        )
    }
}

private struct AppReleaseNotesMetadata: Decodable {
    let schemaVersion: Int
    let version: String
    let sourceRevision: String
    let previousVersion: String?
}

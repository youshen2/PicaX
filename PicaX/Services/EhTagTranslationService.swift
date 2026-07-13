import Foundation

struct EhTagSuggestion: Identifiable, Hashable, Sendable {
    let namespace: String
    let namespaceTitle: String
    let tag: String
    let translatedTitle: String
    fileprivate let normalizedTag: String
    fileprivate let normalizedLastTagWord: String
    fileprivate let normalizedTranslatedTitle: String

    nonisolated init(namespace: String, namespaceTitle: String, tag: String, translatedTitle: String) {
        let normalizedTag = EhTagTranslationService.normalizedTag(tag)
        self.namespace = namespace
        self.namespaceTitle = namespaceTitle
        self.tag = tag
        self.translatedTitle = translatedTitle
        self.normalizedTag = normalizedTag
        self.normalizedLastTagWord = normalizedTag.split(separator: " ").last.map(String.init) ?? normalizedTag
        self.normalizedTranslatedTitle = EhTagTranslationService.normalizedTag(translatedTitle)
    }

    var id: String { "\(namespace):\(tag)" }
    var query: String { "\(namespace):\(quotedTagIfNeeded)" }

    var categoryQuery: String {
        query
    }

    private var quotedTagIfNeeded: String {
        tag.contains(" ") ? "\"\(tag)\"" : tag
    }
}

enum EhTagTranslationService {
    struct DatabaseInfo: Sendable {
        let usesDownloadedDatabase: Bool
        let version: String?
        let updatedAt: Date?
    }

    nonisolated private static let fallbackRows = [
        "language": "语言",
        "artist": "画师",
        "male": "男性",
        "female": "女性",
        "mixed": "混合",
        "other": "其他",
        "parody": "原作",
        "character": "角色",
        "group": "团队",
        "cosplayer": "Coser",
        "reclass": "重新分类",
        "uploader": "上传者"
    ]

    nonisolated private static let suggestionNamespaces = [
        "female",
        "male",
        "parody",
        "character",
        "other",
        "mixed",
        "language",
        "artist",
        "group",
        "cosplayer"
    ]
    nonisolated private static let categoryNamespaces = [
        "male",
        "female",
        "parody",
        "character",
        "mixed",
        "artist",
        "group",
        "cosplayer",
        "other"
    ]
    nonisolated private static let snapshotBox = SnapshotBox(
        initialValue: makeSnapshot(translations: loadTranslations())
    )

    nonisolated private static var snapshot: Snapshot {
        snapshotBox.value
    }

    nonisolated static func translatedGroupTitle(_ title: String) -> String {
        let namespace = normalizedNamespace(title)
        return snapshot.translations["rows"]?[namespace] ?? fallbackRows[namespace] ?? title
    }

    nonisolated static func translatedTagTitle(title: String, query: String, namespace: String) -> String {
        let namespace = normalizedNamespace(namespace)
        let rawTag = rawTagValue(title: title, query: query, namespace: namespace)
        let translated = translatedTag(rawTag, namespace: namespace)
        guard translated != rawTag else {
            return title
        }
        return translated
    }

    static func suggestions(for text: String, limit: Int = 60) -> [EhTagSuggestion] {
        let snapshot = snapshot
        let (namespaceFilter, fragment) = suggestionFragment(from: text)
        guard !fragment.isEmpty else { return [] }

        var result = [EhTagSuggestion]()
        result.reserveCapacity(min(limit, 20))
        for suggestion in suggestionCandidates(fragment: fragment, snapshot: snapshot) {
            if let namespaceFilter, suggestion.namespace != namespaceFilter {
                continue
            }
            guard matches(fragment: fragment, suggestion: suggestion) else { continue }
            result.append(suggestion)
            if result.count >= limit {
                break
            }
        }
        return result
    }

    static func categorySuggestions(limitPerNamespace: Int = 20) -> [EhTagSuggestion] {
        let suggestionIndex = snapshot.suggestionIndex
        return categoryNamespaces.flatMap { namespace in
            suggestionIndex.lazy.filter { $0.namespace == namespace }.prefix(limitPerNamespace)
        }
    }

    static func searchQueryByTranslatingChineseTerms(_ query: String) -> String {
        SearchQueryTagTermTranslator.translatedQuery(query) { rawValue, rawNamespace in
            translatedSearchTerm(rawValue, namespace: rawNamespace)
        }
    }

    nonisolated static func translatedAnyTagTitle(_ title: String) -> String {
        let rawTag = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTag.isEmpty else { return title }
        let translations = snapshot.translations
        for namespace in suggestionNamespaces {
            let translated = translatedTag(rawTag, namespace: namespace, translations: translations)
            if translated != rawTag {
                return translated
            }
        }
        return title
    }

    private nonisolated static func translatedTag(_ tag: String, namespace: String) -> String {
        translatedTag(tag, namespace: namespace, translations: snapshot.translations)
    }

    private nonisolated static func translatedTag(
        _ tag: String,
        namespace: String,
        translations: [String: [String: String]]
    ) -> String {
        if tag.contains(" | ") {
            for value in tag.components(separatedBy: " | ") {
                let translated = translatedTag(value, namespace: namespace, translations: translations)
                if translated != value {
                    return translated
                }
            }
            return tag
        }

        let normalized = normalizedTag(tag)
        if let translated = translations[namespace]?[normalized] {
            return translated
        }
        if namespace != "reclass", normalized.hasSuffix("s") {
            let singular = String(normalized.dropLast())
            if let translated = translations[namespace]?[singular] {
                return translated
            }
        }
        return tag
    }

    private nonisolated static func rawTagValue(title: String, query: String, namespace: String) -> String {
        let currentNamespace = normalizedNamespace(namespace)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separatorIndex = trimmedQuery.firstIndex(of: ":") {
            let queryNamespace = normalizedNamespace(String(trimmedQuery[..<separatorIndex]))
            if queryNamespace == currentNamespace {
                return String(trimmedQuery[trimmedQuery.index(after: separatorIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedNamespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\t"))
            .lowercased()
    }

    fileprivate nonisolated static func normalizedTag(_ value: String) -> String {
        htmlDecoded(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func suggestionFragment(from text: String) -> (namespace: String?, fragment: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init) else {
            return (nil, "")
        }
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (normalizedNamespace(parts[0]), normalizedTag(parts[1]))
        }
        return (nil, normalizedTag(token))
    }

    private nonisolated static func buildSuggestionIndex(
        namespaces: [String],
        translations: [String: [String: String]]
    ) -> [EhTagSuggestion] {
        namespaces.flatMap { namespace in
            let namespaceTitle = translations["rows"]?[namespace] ?? fallbackRows[namespace] ?? namespace
            return (translations[namespace] ?? [:])
                .keys
                .sorted()
                .map { tag in
                    EhTagSuggestion(
                        namespace: namespace,
                        namespaceTitle: namespaceTitle,
                        tag: tag,
                        translatedTitle: translatedTag(tag, namespace: namespace, translations: translations)
                    )
                }
        }
    }

    private nonisolated static func buildSearchNamespaceAliases(
        translations: [String: [String: String]]
    ) -> [String: String] {
        var aliases: [String: String] = [:]
        let rowNamespaces = translations["rows"].map { Array($0.keys) } ?? []
        let namespaces = Set(suggestionNamespaces + categoryNamespaces + Array(fallbackRows.keys) + rowNamespaces)
        for namespace in namespaces {
            let normalized = normalizedNamespace(namespace)
            aliases[normalized] = normalized
        }
        for (namespace, title) in fallbackRows {
            aliases[normalizedTag(title)] = normalizedNamespace(namespace)
        }
        for (namespace, title) in translations["rows"] ?? [:] {
            aliases[normalizedTag(title)] = normalizedNamespace(namespace)
        }
        return aliases
    }

    private nonisolated static func buildExactTranslatedTagsByNamespace(
        translations: [String: [String: String]]
    ) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for namespace in suggestionNamespaces {
            for (tag, translatedTitle) in translations[namespace] ?? [:] {
                guard SearchQueryTagTermTranslator.containsTranslatedText(translatedTitle) else { continue }
                let normalizedTitle = normalizedTag(translatedTitle)
                guard !normalizedTitle.isEmpty else { continue }
                if result[namespace]?[normalizedTitle] != nil { continue }
                result[namespace, default: [:]][normalizedTitle] = tag
            }
        }
        return result
    }

    private nonisolated static func buildExactTranslatedSuggestionIndex(
        suggestionIndex: [EhTagSuggestion]
    ) -> [String: EhTagSuggestion] {
        var result: [String: EhTagSuggestion] = [:]
        for suggestion in suggestionIndex {
            guard SearchQueryTagTermTranslator.containsTranslatedText(suggestion.translatedTitle) else { continue }
            let normalizedTitle = normalizedTag(suggestion.translatedTitle)
            guard !normalizedTitle.isEmpty else { continue }
            if result[normalizedTitle] != nil { continue }
            result[normalizedTitle] = suggestion
        }
        return result
    }

    private static func translatedSearchTerm(_ rawValue: String, namespace rawNamespace: String?) -> SearchQueryTagTermTranslation? {
        let snapshot = snapshot
        let value = htmlDecoded(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let namespace = normalizedSearchNamespace(rawNamespace, aliases: snapshot.searchNamespaceAliases) {
            let normalizedValue = normalizedTag(value)
            if SearchQueryTagTermTranslator.containsTranslatedText(value),
               let tag = snapshot.exactTranslatedTagsByNamespace[namespace]?[normalizedValue] {
                return SearchQueryTagTermTranslation(query: "\(namespace):\(SearchQueryTagTermTranslator.quoted(value: tag))")
            }
            if !SearchQueryTagTermTranslator.containsTranslatedText(value),
               let tag = normalizedEnglishTag(value, namespace: namespace, translations: snapshot.translations) {
                return SearchQueryTagTermTranslation(query: "\(namespace):\(SearchQueryTagTermTranslator.quoted(value: tag))")
            }
            return nil
        }

        guard SearchQueryTagTermTranslator.containsTranslatedText(value) else { return nil }
        let normalizedValue = normalizedTag(value)
        guard let suggestion = snapshot.exactTranslatedSuggestionIndex[normalizedValue] else { return nil }
        return SearchQueryTagTermTranslation(query: suggestion.query)
    }

    private static func normalizedSearchNamespace(_ rawNamespace: String?, aliases: [String: String]) -> String? {
        guard let rawNamespace else { return nil }
        let normalizedTag = normalizedTag(rawNamespace)
        if let namespace = aliases[normalizedTag] {
            return namespace
        }
        let normalizedNamespace = normalizedNamespace(rawNamespace)
        return aliases[normalizedNamespace]
    }

    private static func normalizedEnglishTag(
        _ value: String,
        namespace: String,
        translations: [String: [String: String]]
    ) -> String? {
        let normalized = normalizedTag(value)
        guard translations[namespace]?[normalized] != nil else { return nil }
        return normalized
    }

    private static func matches(fragment: String, suggestion: EhTagSuggestion) -> Bool {
        if suggestion.normalizedTag.hasPrefix(fragment) {
            return true
        }
        if suggestion.normalizedLastTagWord.hasPrefix(fragment) {
            return true
        }
        return suggestion.normalizedTranslatedTitle.contains(fragment)
    }

    private static func suggestionCandidates(fragment: String, snapshot: Snapshot) -> [EhTagSuggestion] {
        guard let scalar = fragment.unicodeScalars.first, scalar.isASCII else {
            return snapshot.suggestionIndex
        }
        return snapshot.suggestionBuckets[String(Character(scalar))] ?? []
    }

    private nonisolated static func loadTranslations() -> [String: [String: String]] {
        if let data = try? Data(contentsOf: downloadedDatabaseURL),
           let value = try? JSONDecoder().decode([String: [String: String]].self, from: data),
           isValidDatabase(value) {
            return value
        }
        return loadBundledTranslations()
    }

    private nonisolated static func loadBundledTranslations() -> [String: [String: String]] {
        guard let url = Bundle.main.url(forResource: "EhTagTranslations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return value
    }

    nonisolated static var databaseInfo: DatabaseInfo {
        let usesDownloadedDatabase = FileManager.default.fileExists(atPath: downloadedDatabaseURL.path)
        return DatabaseInfo(
            usesDownloadedDatabase: usesDownloadedDatabase,
            version: usesDownloadedDatabase ? UserDefaults.standard.string(forKey: EhTagTranslationSettingsKey.downloadedVersion) : nil,
            updatedAt: usesDownloadedDatabase ? UserDefaults.standard.object(forKey: EhTagTranslationSettingsKey.lastUpdatedAt) as? Date : nil
        )
    }

    nonisolated static func installDownloadedDatabase(
        _ translations: [String: [String: String]],
        version: String
    ) throws {
        guard isValidDatabase(translations) else {
            throw EhTagTranslationUpdateError.invalidDatabase
        }
        let directory = downloadedDatabaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(translations)
        try data.write(to: downloadedDatabaseURL, options: .atomic)
        UserDefaults.standard.set(version, forKey: EhTagTranslationSettingsKey.downloadedVersion)
        UserDefaults.standard.set(Date(), forKey: EhTagTranslationSettingsKey.lastUpdatedAt)
        snapshotBox.replace(with: makeSnapshot(translations: translations))
        NotificationCenter.default.post(name: .picaxEhTagTranslationsDidChange, object: nil)
    }

    nonisolated static func restoreBundledDatabase() throws {
        if FileManager.default.fileExists(atPath: downloadedDatabaseURL.path) {
            try FileManager.default.removeItem(at: downloadedDatabaseURL)
        }
        UserDefaults.standard.removeObject(forKey: EhTagTranslationSettingsKey.downloadedVersion)
        UserDefaults.standard.removeObject(forKey: EhTagTranslationSettingsKey.lastUpdatedAt)
        snapshotBox.replace(with: makeSnapshot(translations: loadBundledTranslations()))
        NotificationCenter.default.post(name: .picaxEhTagTranslationsDidChange, object: nil)
    }

    private nonisolated static var downloadedDatabaseURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("PicaX", isDirectory: true)
            .appendingPathComponent("EhTagTranslations.downloaded.json")
    }

    private nonisolated static func isValidDatabase(_ translations: [String: [String: String]]) -> Bool {
        guard translations["rows"]?.count ?? 0 >= 10,
              translations["female"]?.count ?? 0 >= 100,
              translations["male"]?.count ?? 0 >= 100 else {
            return false
        }
        return translations.values.reduce(0) { $0 + $1.count } >= 1_000
    }

    private nonisolated static func makeSnapshot(
        translations: [String: [String: String]]
    ) -> Snapshot {
        let suggestionIndex = buildSuggestionIndex(
            namespaces: suggestionNamespaces,
            translations: translations
        )
        return Snapshot(
            translations: translations,
            suggestionIndex: suggestionIndex,
            suggestionBuckets: Dictionary(grouping: suggestionIndex) {
                $0.normalizedTag.first.map(String.init) ?? ""
            },
            searchNamespaceAliases: buildSearchNamespaceAliases(translations: translations),
            exactTranslatedTagsByNamespace: buildExactTranslatedTagsByNamespace(translations: translations),
            exactTranslatedSuggestionIndex: buildExactTranslatedSuggestionIndex(suggestionIndex: suggestionIndex)
        )
    }

    private struct Snapshot: Sendable {
        let translations: [String: [String: String]]
        let suggestionIndex: [EhTagSuggestion]
        let suggestionBuckets: [String: [EhTagSuggestion]]
        let searchNamespaceAliases: [String: String]
        let exactTranslatedTagsByNamespace: [String: [String: String]]
        let exactTranslatedSuggestionIndex: [String: EhTagSuggestion]
    }

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var storedValue: Snapshot

        nonisolated init(initialValue: Snapshot) {
            storedValue = initialValue
        }

        nonisolated var value: Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }

        nonisolated func replace(with value: Snapshot) {
            lock.lock()
            storedValue = value
            lock.unlock()
        }
    }

    private nonisolated static func htmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SearchQueryTagTermTranslation: Sendable {
    let query: String
}

enum SearchQueryTagTermTranslator {
    nonisolated static func translatedQuery(
        _ query: String,
        resolver: (String, String?) -> SearchQueryTagTermTranslation?
    ) -> String {
        let tokens = searchTokens(from: query)
        guard !tokens.isEmpty else { return query }
        return tokens.map { token in
            translatedToken(token, resolver: resolver)
        }.joined(separator: " ")
    }

    nonisolated static func quoted(value: String) -> String {
        value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
    }

    nonisolated static func containsTranslatedText(_ value: String) -> Bool {
        value.unicodeScalars.contains { !$0.isASCII }
    }

    private nonisolated static func translatedToken(
        _ token: String,
        resolver: (String, String?) -> SearchQueryTagTermTranslation?
    ) -> String {
        let (prefix, body) = leadingSearchOperator(in: token)
        guard !body.isEmpty else { return token }

        if let split = namespaceSplit(in: body) {
            let value = unquoted(split.value)
            if let translation = resolver(value, split.namespace) {
                return prefix + translation.query
            }
            return token
        }

        let value = unquoted(body)
        guard let translation = resolver(value, nil) else { return token }
        return prefix + translation.query
    }

    private nonisolated static func searchTokens(from query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false

        for character in query {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character.isWhitespace, !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private nonisolated static func leadingSearchOperator(in token: String) -> (prefix: String, body: String) {
        guard let first = token.first, first == "-" || first == "+" else {
            return ("", token)
        }
        return (String(first), String(token.dropFirst()))
    }

    private nonisolated static func namespaceSplit(in token: String) -> (namespace: String, value: String)? {
        var isQuoted = false
        for index in token.indices {
            let character = token[index]
            if character == "\"" {
                isQuoted.toggle()
            } else if character == ":", !isQuoted {
                let namespace = String(token[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(token[token.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !namespace.isEmpty, !value.isEmpty else { return nil }
                return (namespace, value)
            }
        }
        return nil
    }

    private nonisolated static func unquoted(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count >= 2, result.first == "\"", result.last == "\"" {
            result.removeFirst()
            result.removeLast()
        }
        return result
    }
}

import Foundation

struct EhTagSuggestion: Identifiable, Hashable {
    let namespace: String
    let namespaceTitle: String
    let tag: String
    let translatedTitle: String
    fileprivate let normalizedTag: String
    fileprivate let normalizedLastTagWord: String
    fileprivate let normalizedTranslatedTitle: String

    init(namespace: String, namespaceTitle: String, tag: String, translatedTitle: String) {
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
    private static let fallbackRows = [
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

    private static let translations = loadTranslations()
    private static let suggestionNamespaces = [
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
    private static let categoryNamespaces = [
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
    private static let suggestionIndex = buildSuggestionIndex(namespaces: suggestionNamespaces)
    private static let suggestionBuckets = Dictionary(grouping: suggestionIndex) {
        $0.normalizedTag.first.map(String.init) ?? ""
    }

    static func translatedGroupTitle(_ title: String) -> String {
        let namespace = normalizedNamespace(title)
        return translations["rows"]?[namespace] ?? fallbackRows[namespace] ?? title
    }

    static func translatedTagTitle(title: String, query: String, namespace: String) -> String {
        let namespace = normalizedNamespace(namespace)
        let rawTag = rawTagValue(title: title, query: query, namespace: namespace)
        let translated = translatedTag(rawTag, namespace: namespace)
        guard translated != rawTag else {
            return title
        }
        return translated
    }

    static func suggestions(for text: String, limit: Int = 60) -> [EhTagSuggestion] {
        let (namespaceFilter, fragment) = suggestionFragment(from: text)
        guard !fragment.isEmpty else { return [] }

        var result = [EhTagSuggestion]()
        result.reserveCapacity(min(limit, 20))
        for suggestion in suggestionCandidates(fragment: fragment) {
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
        categoryNamespaces.flatMap { namespace in
            suggestionIndex.lazy.filter { $0.namespace == namespace }.prefix(limitPerNamespace)
        }
    }

    static func translatedAnyTagTitle(_ title: String) -> String {
        let rawTag = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTag.isEmpty else { return title }
        for namespace in suggestionNamespaces {
            let translated = translatedTag(rawTag, namespace: namespace)
            if translated != rawTag {
                return translated
            }
        }
        return title
    }

    private static func translatedTag(_ tag: String, namespace: String) -> String {
        if tag.contains(" | ") {
            for value in tag.components(separatedBy: " | ") {
                let translated = translatedTag(value, namespace: namespace)
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

    private static func rawTagValue(title: String, query: String, namespace: String) -> String {
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

    private static func normalizedNamespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\t"))
            .lowercased()
    }

    fileprivate static func normalizedTag(_ value: String) -> String {
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

    private static func buildSuggestionIndex(namespaces: [String]) -> [EhTagSuggestion] {
        namespaces.flatMap { namespace in
            let namespaceTitle = translatedGroupTitle(namespace)
            return (translations[namespace] ?? [:])
                .keys
                .sorted()
                .map { tag in
                    EhTagSuggestion(
                        namespace: namespace,
                        namespaceTitle: namespaceTitle,
                        tag: tag,
                        translatedTitle: translatedTag(tag, namespace: namespace)
                    )
                }
        }
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

    private static func suggestionCandidates(fragment: String) -> [EhTagSuggestion] {
        guard let scalar = fragment.unicodeScalars.first, scalar.isASCII else {
            return suggestionIndex
        }
        return suggestionBuckets[String(Character(scalar))] ?? []
    }

    private static func loadTranslations() -> [String: [String: String]] {
        guard let url = Bundle.main.url(forResource: "EhTagTranslations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return value
    }

    private static func htmlDecoded(_ value: String) -> String {
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

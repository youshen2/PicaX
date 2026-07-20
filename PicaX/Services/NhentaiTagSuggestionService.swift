import Foundation

struct NhentaiTagSuggestion: Identifiable, Hashable, Sendable {
    let group: String
    let groupTitle: String
    let tag: String
    let translatedTitle: String
    fileprivate let normalizedTag: String
    fileprivate let normalizedLastTagWord: String
    fileprivate let normalizedTranslatedTitle: String

    nonisolated init(group: String, groupTitle: String, tag: String, translatedTitle: String) {
        let normalizedTag = NhentaiTagSuggestionService.normalizedTag(tag)
        self.group = group
        self.groupTitle = groupTitle
        self.tag = tag
        self.translatedTitle = translatedTitle
        self.normalizedTag = normalizedTag
        self.normalizedLastTagWord = normalizedTag.split(separator: " ").last.map(String.init) ?? normalizedTag
        self.normalizedTranslatedTitle = NhentaiTagSuggestionService.normalizedTag(translatedTitle)
    }

    var id: String { "\(group):\(tag)" }

    var query: String {
        group == "language" ? "language:\(tag)" : quotedTagIfNeeded
    }

    private var quotedTagIfNeeded: String {
        tag.contains(" ") ? "\"\(tag)\"" : tag
    }
}

enum NhentaiTagSuggestionService {
    nonisolated private static let groupOrder = ["language", "tag", "character", "parody"]
    nonisolated private static let groupTitles = [
        "language": "语言",
        "tag": "标签",
        "character": "角色",
        "parody": "原作"
    ]
    nonisolated private static let suggestions = loadSuggestions()
    nonisolated private static let suggestionBuckets = Dictionary(grouping: suggestions) {
        $0.normalizedTag.first.map(String.init) ?? ""
    }
    nonisolated private static let searchGroupAliases = buildSearchGroupAliases()
    nonisolated private static let exactTranslatedSuggestionsByGroup = buildExactTranslatedSuggestionsByGroup()
    nonisolated private static let exactTranslatedSuggestionIndex = buildExactTranslatedSuggestionIndex()

    nonisolated static func prepare() {
        _ = suggestions
        _ = suggestionBuckets
        _ = searchGroupAliases
        _ = exactTranslatedSuggestionsByGroup
        _ = exactTranslatedSuggestionIndex
    }

    static func suggestions(for text: String, limit: Int = 60) -> [NhentaiTagSuggestion] {
        let fragment = normalizedFragment(from: text)
        guard !fragment.isEmpty else { return [] }

        var result = [NhentaiTagSuggestion]()
        result.reserveCapacity(min(limit, 20))
        for suggestion in suggestionCandidates(fragment: fragment) {
            guard matches(fragment: fragment, suggestion: suggestion) else { continue }
            result.append(suggestion)
            if result.count >= limit {
                break
            }
        }
        return result
    }

    static func categorySuggestions(limitPerGroup: Int = 50) -> [NhentaiTagSuggestion] {
        groupOrder.flatMap { group in
            suggestions.lazy.filter { $0.group == group }.prefix(limitPerGroup)
        }
    }

    static func searchQueryByTranslatingChineseTerms(_ query: String) -> String {
        SearchQueryTagTermTranslator.translatedQuery(query) { rawValue, rawGroup in
            translatedSearchTerm(rawValue, group: rawGroup)
        }
    }

    nonisolated static func translatedTitle(forTagName tagName: String, group: String? = nil) -> String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tagName }

        if let namespace = ehentaiNamespace(for: group) {
            let translated = EhTagTranslationService.translatedTagTitle(
                title: trimmed,
                query: "\(namespace):\(trimmed)",
                namespace: namespace
            )
            if translated != trimmed {
                return translated
            }
        }
        return EhTagTranslationService.translatedAnyTagTitle(trimmed)
    }

    fileprivate nonisolated static func normalizedTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedFragment(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init) else {
            return ""
        }
        if let separatorIndex = token.firstIndex(of: ":") {
            return normalizedTag(String(token[token.index(after: separatorIndex)...]))
        }
        return normalizedTag(token)
    }

    private nonisolated static func loadSuggestions() -> [NhentaiTagSuggestion] {
        guard let url = Bundle.main.url(forResource: "NhentaiTagSuggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return fallbackSuggestions()
        }

        return groupOrder.flatMap { group in
            buildSuggestions(group: group, tags: values[group] ?? [])
        }
    }

    private nonisolated static func buildSuggestions(group: String, tags: [String]) -> [NhentaiTagSuggestion] {
        let title = groupTitles[group] ?? group
        return tags.map { tag in
            NhentaiTagSuggestion(
                group: group,
                groupTitle: title,
                tag: tag,
                translatedTitle: EhTagTranslationService.translatedAnyTagTitle(tag)
            )
        }
    }

    private nonisolated static func fallbackSuggestions() -> [NhentaiTagSuggestion] {
        buildSuggestions(group: "language", tags: ["chinese", "japanese", "english"]) +
            buildSuggestions(group: "tag", tags: ["big breasts", "full color", "cosplay", "doujinshi", "manga"])
    }

    private nonisolated static func buildSearchGroupAliases() -> [String: String] {
        var aliases: [String: String] = [:]
        for group in groupOrder {
            aliases[normalizedTag(group)] = group
        }
        for (group, title) in groupTitles {
            aliases[normalizedTag(title)] = group
        }
        return aliases
    }

    private nonisolated static func buildExactTranslatedSuggestionsByGroup() -> [String: [String: NhentaiTagSuggestion]] {
        var result: [String: [String: NhentaiTagSuggestion]] = [:]
        for suggestion in suggestions {
            guard SearchQueryTagTermTranslator.containsTranslatedText(suggestion.translatedTitle) else { continue }
            let normalizedTitle = normalizedTag(suggestion.translatedTitle)
            guard !normalizedTitle.isEmpty else { continue }
            if result[suggestion.group]?[normalizedTitle] != nil { continue }
            result[suggestion.group, default: [:]][normalizedTitle] = suggestion
        }
        return result
    }

    private nonisolated static func buildExactTranslatedSuggestionIndex() -> [String: NhentaiTagSuggestion] {
        var result: [String: NhentaiTagSuggestion] = [:]
        for suggestion in suggestions {
            guard SearchQueryTagTermTranslator.containsTranslatedText(suggestion.translatedTitle) else { continue }
            let normalizedTitle = normalizedTag(suggestion.translatedTitle)
            guard !normalizedTitle.isEmpty else { continue }
            if result[normalizedTitle] != nil { continue }
            result[normalizedTitle] = suggestion
        }
        return result
    }

    private static func translatedSearchTerm(_ rawValue: String, group rawGroup: String?) -> SearchQueryTagTermTranslation? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let group = normalizedSearchGroup(rawGroup) {
            let normalizedValue = normalizedTag(value)
            if SearchQueryTagTermTranslator.containsTranslatedText(value),
               let suggestion = exactTranslatedSuggestionsByGroup[group]?[normalizedValue] {
                return SearchQueryTagTermTranslation(query: suggestion.query)
            }
            if !SearchQueryTagTermTranslator.containsTranslatedText(value),
               let suggestion = englishSuggestion(value, group: group) {
                return SearchQueryTagTermTranslation(query: suggestion.query)
            }
            return nil
        }

        guard SearchQueryTagTermTranslator.containsTranslatedText(value) else { return nil }
        let normalizedValue = normalizedTag(value)
        guard let suggestion = exactTranslatedSuggestionIndex[normalizedValue] else { return nil }
        return SearchQueryTagTermTranslation(query: suggestion.query)
    }

    private static func normalizedSearchGroup(_ rawGroup: String?) -> String? {
        guard let rawGroup else { return nil }
        return searchGroupAliases[normalizedTag(rawGroup)]
    }

    private static func englishSuggestion(_ value: String, group: String) -> NhentaiTagSuggestion? {
        let normalizedValue = normalizedTag(value)
        return suggestions.first {
            $0.group == group && $0.normalizedTag == normalizedValue
        }
    }

    private static func matches(fragment: String, suggestion: NhentaiTagSuggestion) -> Bool {
        if suggestion.normalizedTag.hasPrefix(fragment) {
            return true
        }
        if suggestion.normalizedLastTagWord.hasPrefix(fragment) {
            return true
        }
        return suggestion.normalizedTranslatedTitle.contains(fragment)
    }

    private static func suggestionCandidates(fragment: String) -> [NhentaiTagSuggestion] {
        guard let scalar = fragment.unicodeScalars.first, scalar.isASCII else {
            return suggestions
        }
        return suggestionBuckets[String(Character(scalar))] ?? []
    }

    private nonisolated static func ehentaiNamespace(for group: String?) -> String? {
        switch normalizedTag(group ?? "") {
        case "artist", "character", "group", "language", "parody":
            return normalizedTag(group ?? "")
        case "category":
            return "reclass"
        default:
            return nil
        }
    }
}

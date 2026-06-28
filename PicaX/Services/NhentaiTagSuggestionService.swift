import Foundation

struct NhentaiTagSuggestion: Identifiable, Hashable {
    let group: String
    let groupTitle: String
    let tag: String
    let translatedTitle: String
    fileprivate let normalizedTag: String
    fileprivate let normalizedLastTagWord: String
    fileprivate let normalizedTranslatedTitle: String

    init(group: String, groupTitle: String, tag: String, translatedTitle: String) {
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
    private static let groupOrder = ["language", "tag", "character", "parody"]
    private static let groupTitles = [
        "language": "语言",
        "tag": "标签",
        "character": "角色",
        "parody": "原作"
    ]
    private static let suggestions = loadSuggestions()
    private static let suggestionBuckets = Dictionary(grouping: suggestions) {
        $0.normalizedTag.first.map(String.init) ?? ""
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

    fileprivate static func normalizedTag(_ value: String) -> String {
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

    private static func loadSuggestions() -> [NhentaiTagSuggestion] {
        guard let url = Bundle.main.url(forResource: "NhentaiTagSuggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return fallbackSuggestions()
        }

        return groupOrder.flatMap { group in
            buildSuggestions(group: group, tags: values[group] ?? [])
        }
    }

    private static func buildSuggestions(group: String, tags: [String]) -> [NhentaiTagSuggestion] {
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

    private static func fallbackSuggestions() -> [NhentaiTagSuggestion] {
        buildSuggestions(group: "language", tags: ["chinese", "japanese", "english"]) +
            buildSuggestions(group: "tag", tags: ["big breasts", "full color", "cosplay", "doujinshi", "manga"])
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
}

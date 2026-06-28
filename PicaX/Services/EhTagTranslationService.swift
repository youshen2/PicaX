import Foundation

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

    private static func normalizedTag(_ value: String) -> String {
        htmlDecoded(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

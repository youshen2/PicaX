import Foundation

struct ComicListTagResolver: Sendable {
    private let nhentaiCache: [Int: StoredNhentaiTagName]

    nonisolated init(comics: [ComicListItem]) {
        nhentaiCache = PicaXSQLiteStore.loadNhentaiTagNames(ids: Self.nhentaiTagIDs(in: comics))
    }

    nonisolated init(nhentaiCache: [Int: StoredNhentaiTagName]) {
        self.nhentaiCache = nhentaiCache
    }

    nonisolated func matchingTags(for comic: ComicListItem) -> [String] {
        rawTags(for: comic).flatMap { tag in
            let translated = Self.displayTitle(for: tag, platform: comic.platform)
            let plainTitle = MarkdownImageTagContent(translated).plainText
            var candidates = [tag, translated, plainTitle]
            if let scoped = Self.scopedTag(from: tag) {
                candidates.append("\(scoped.namespace):\(plainTitle)")
                if comic.platform == .hitomi, scoped.namespace == "series" {
                    candidates.append("parody:\(scoped.value)")
                }
            }
            return candidates
        }
    }

    nonisolated func tagReferences(for comic: ComicListItem) -> [ComicTagReference] {
        rawTags(for: comic).map { tag in
            ComicTagReference(
                title: Self.displayTitle(for: tag, platform: comic.platform),
                query: tag,
                platform: comic.platform,
                urlString: nil
            )
        }
    }

    private nonisolated func rawTags(for comic: ComicListItem) -> [String] {
        comic.tags.map { tag in
            guard comic.platform == .nhentai,
                  let id = Self.nhentaiTagID(from: tag),
                  let record = nhentaiCache[id] else {
                return tag
            }
            return "\(record.group):\(record.name)"
        }
    }

    nonisolated func displayTagsByID(for comics: [ComicListItem]) -> [String: [String]] {
        var result: [String: [String]] = [:]

        for (index, comic) in comics.enumerated() {
            if index.isMultiple(of: 64), Task.isCancelled {
                break
            }
            let displayTags = displayTags(for: comic)
            if displayTags != comic.tags {
                result[comic.readingHistoryID] = displayTags
            }
        }
        return result
    }

    private nonisolated func displayTags(for comic: ComicListItem) -> [String] {
        let tags = rawTags(for: comic).compactMap { tag -> String? in
            if comic.platform == .nhentai, Self.nhentaiTagID(from: tag) != nil {
                return nil
            }
            return Self.displayTitle(for: tag, platform: comic.platform)
        }
        guard tags.isEmpty,
              comic.platform == .nhentai,
              comic.tags.contains(where: { Self.nhentaiTagID(from: $0) != nil }) else {
            return tags
        }
        return ["正在解析标签"]
    }

    private nonisolated static func nhentaiTagIDs(in comics: [ComicListItem]) -> [Int] {
        var ids: [Int] = []
        for comic in comics where comic.platform == .nhentai {
            ids.append(contentsOf: comic.tags.compactMap(nhentaiTagID(from:)))
        }
        return ids
    }

    private nonisolated static func displayTitle(
        for tag: String,
        platform: ComicPlatform
    ) -> String {
        let normalized = normalizedTag(tag)
        switch platform {
        case .nhentai:
            if let scopedTag = scopedTag(from: normalized) {
                return NhentaiTagSuggestionService.translatedTitle(
                    forTagName: scopedTag.value,
                    group: scopedTag.namespace
                )
            }
            return NhentaiTagSuggestionService.translatedTitle(forTagName: normalized)
        case .eHentai, .hitomi:
            if let scopedTag = scopedTag(from: normalized) {
                if platform == .hitomi, scopedTag.namespace == "tag" {
                    return EhTagTranslationService.translatedAnyTagTitle(scopedTag.value)
                }
                let namespace = platform == .hitomi && scopedTag.namespace == "series" ? "parody" : scopedTag.namespace
                return EhTagTranslationService.translatedTagTitle(
                    title: scopedTag.value,
                    query: "\(namespace):\(scopedTag.value)",
                    namespace: namespace
                )
            }
            return EhTagTranslationService.translatedAnyTagTitle(normalized)
        case .picacg, .jmComic, .htManga:
            return tag
        }
    }

    private nonisolated static func nhentaiTagID(from tag: String) -> Int? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("tag:") else { return nil }
        return Int(trimmed.dropFirst("tag:".count))
    }

    private nonisolated static func scopedTag(from tag: String) -> (namespace: String, value: String)? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.firstIndex(of: ":") else { return nil }
        let namespace = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !namespace.isEmpty, !value.isEmpty else { return nil }
        return (namespace, value)
    }

    nonisolated static func normalizedTag(_ value: String) -> String {
        let trimmed = sexMarkerNormalized(value)
        if let separator = trimmed.firstIndex(of: ":") {
            let namespace = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(trimmed[trimmed.index(after: separator)...])
            return "\(namespace):\(unquotedTagValue(name))"
        }
        return unquotedTagValue(trimmed)
    }

    private nonisolated static func unquotedTagValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
    }

    private nonisolated static func sexMarkerNormalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ♀", with: "")
            .replacingOccurrences(of: " ♂", with: "")
            .replacingOccurrences(of: "♀", with: "")
            .replacingOccurrences(of: "♂", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

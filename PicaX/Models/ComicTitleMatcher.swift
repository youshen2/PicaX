import Foundation

nonisolated struct ComicTitleMatchingConfiguration: Hashable, Sendable {
    let isEnabled: Bool
    let similarityThreshold: Int

    init(
        isEnabled: Bool = ComicTitleMatchingSettingsKey.defaultIsEnabled,
        similarityThreshold: Int = ComicTitleMatchingSettingsKey.defaultSimilarityThreshold
    ) {
        self.isEnabled = isEnabled
        self.similarityThreshold = min(max(similarityThreshold, 50), 100)
    }
}

nonisolated enum ComicTitleMatcher {
    static func titlesMatch(
        _ lhs: ComicListItem,
        _ rhs: ComicListItem,
        configuration: ComicTitleMatchingConfiguration
    ) -> Bool {
        guard configuration.isEnabled,
              languagesAreCompatible(lhs.language, rhs.language) else {
            return false
        }

        return titleCandidatesMatch(
            normalizedTitleCandidates(lhs.title),
            normalizedTitleCandidates(rhs.title),
            threshold: configuration.similarityThreshold
        )
    }

    static func similarityPercent(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedTitle(lhs)
        let right = normalizedTitle(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let maximumLength = max(left.count, right.count)
        let distance = editDistance(left, right, maximumDistance: maximumLength) ?? maximumLength
        return (1 - Double(distance) / Double(maximumLength)) * 100
    }

    fileprivate static func normalizedTitle(_ title: String) -> [UInt32] {
        let folded = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.unicodeScalars.compactMap { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? scalar.value : nil
        }
    }

    fileprivate static func normalizedTitleCandidates(_ title: String) -> [[UInt32]] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }

        var candidates: [[UInt32]] = []
        var seen = Set<[UInt32]>()

        func append(_ value: String, minimumLength: Int) {
            let normalized = normalizedTitle(value)
            let requiredLength = containsEastAsianText(normalized) ? min(minimumLength, 2) : minimumLength
            guard normalized.count >= requiredLength,
                  !isNumericOnly(normalized),
                  seen.insert(normalized).inserted else {
                return
            }
            candidates.append(normalized)
        }

        let separatedTitle = trimmedTitle
            .replacingOccurrences(of: " / ", with: "|")
            .replacingOccurrences(of: " ／ ", with: "|")
        let aliases = separatedTitle.components(
            separatedBy: CharacterSet(charactersIn: "|｜\n")
        )
        let strippedTitle = strippingBracketedMetadata(from: separatedTitle)
        let hasBracketMetadata = !strippedTitle.isEmpty
            && normalizedTitle(strippedTitle) != normalizedTitle(separatedTitle)
        if aliases.count == 1, !hasBracketMetadata {
            append(trimmedTitle, minimumLength: 2)
        }

        for alias in aliases {
            let strippedAlias = strippingBracketedMetadata(from: alias)
            let hasAliasMetadata = !strippedAlias.isEmpty
                && normalizedTitle(strippedAlias) != normalizedTitle(alias)
            append(hasAliasMetadata ? strippedAlias : alias, minimumLength: 4)
        }

        return candidates
    }

    fileprivate static func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let normalized = language
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty,
              !["n/a", "na", "unknown", "other", "其他", "未知"].contains(normalized) else {
            return nil
        }

        switch normalized {
        case "chinese", "chinese translated", "中文", "简体中文", "繁體中文", "繁体中文", "中国語":
            return "chinese"
        case "japanese", "日本語", "日文":
            return "japanese"
        case "english", "英文", "英語":
            return "english"
        default:
            return normalized
        }
    }

    fileprivate static func languagesAreCompatible(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let left = normalizedLanguage(lhs),
              let right = normalizedLanguage(rhs) else {
            return true
        }
        return left == right
    }

    fileprivate static func normalizedTitlesMatch(
        _ lhs: [UInt32],
        _ rhs: [UInt32],
        threshold: Int
    ) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }

        let clampedThreshold = min(max(threshold, 0), 100)
        let maximumLength = max(lhs.count, rhs.count)
        let maximumDistance = Int(
            floor(Double(maximumLength) * Double(100 - clampedThreshold) / 100)
        )
        guard abs(lhs.count - rhs.count) <= maximumDistance else { return false }
        return editDistance(lhs, rhs, maximumDistance: maximumDistance) != nil
    }

    fileprivate static func titleCandidatesMatch(
        _ lhs: [[UInt32]],
        _ rhs: [[UInt32]],
        threshold: Int
    ) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        for left in lhs {
            for right in rhs where possibleLengthMatch(left.count, right.count, threshold: threshold) {
                if normalizedTitlesMatch(left, right, threshold: threshold) {
                    return true
                }
            }
        }
        return false
    }

    private static func possibleLengthMatch(_ lhs: Int, _ rhs: Int, threshold: Int) -> Bool {
        let maximumLength = max(lhs, rhs)
        let maximumDistance = Int(
            floor(Double(maximumLength) * Double(100 - min(max(threshold, 0), 100)) / 100)
        )
        return abs(lhs - rhs) <= maximumDistance
    }

    private static func strippingBracketedMetadata(from value: String) -> String {
        let closingBracket: [Character: Character] = [
            "[": "]",
            "【": "】",
            "［": "］"
        ]
        var expectedClosings: [Character] = []
        var result = ""

        for character in value {
            if let closing = closingBracket[character] {
                expectedClosings.append(closing)
                if expectedClosings.count == 1 {
                    result.append(" ")
                }
                continue
            }
            if character == expectedClosings.last {
                expectedClosings.removeLast()
                if expectedClosings.isEmpty {
                    result.append(" ")
                }
                continue
            }
            if expectedClosings.isEmpty {
                result.append(character)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNumericOnly(_ value: [UInt32]) -> Bool {
        value.allSatisfy { rawValue in
            guard let scalar = UnicodeScalar(rawValue) else { return false }
            return CharacterSet.decimalDigits.contains(scalar)
        }
    }

    private static func containsEastAsianText(_ value: [UInt32]) -> Bool {
        value.contains { scalar in
            (0x2E80...0x9FFF).contains(scalar)
                || (0x3040...0x30FF).contains(scalar)
                || (0xAC00...0xD7AF).contains(scalar)
                || (0x20000...0x3134F).contains(scalar)
        }
    }

    private static func editDistance(
        _ lhs: [UInt32],
        _ rhs: [UInt32],
        maximumDistance: Int
    ) -> Int? {
        if lhs.isEmpty { return rhs.count <= maximumDistance ? rhs.count : nil }
        if rhs.isEmpty { return lhs.count <= maximumDistance ? lhs.count : nil }

        let shorter: [UInt32]
        let longer: [UInt32]
        if lhs.count <= rhs.count {
            shorter = lhs
            longer = rhs
        } else {
            shorter = rhs
            longer = lhs
        }

        var previous = Array(0...shorter.count)
        var current = Array(repeating: 0, count: shorter.count + 1)

        for (longerIndex, longerScalar) in longer.enumerated() {
            current[0] = longerIndex + 1
            var rowMinimum = current[0]

            for (shorterIndex, shorterScalar) in shorter.enumerated() {
                let substitutionCost = longerScalar == shorterScalar ? 0 : 1
                current[shorterIndex + 1] = min(
                    previous[shorterIndex + 1] + 1,
                    current[shorterIndex] + 1,
                    previous[shorterIndex] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[shorterIndex + 1])
            }

            if rowMinimum > maximumDistance {
                return nil
            }
            swap(&previous, &current)
        }

        let distance = previous[shorter.count]
        return distance <= maximumDistance ? distance : nil
    }
}

nonisolated struct ComicTitleMatchIndex: Sendable {
    private struct Entry: Sendable {
        let normalizedTitle: [UInt32]
        let language: String?
        let platform: ComicPlatform
    }

    private let configuration: ComicTitleMatchingConfiguration
    private var entriesByLength: [Int: [Entry]] = [:]
    private var itemIDs = Set<String>()

    init(items: [ComicListItem], configuration: ComicTitleMatchingConfiguration) {
        self.configuration = configuration
        guard configuration.isEnabled else { return }

        for item in items {
            insert(item)
        }
    }

    @discardableResult
    mutating func insert(_ item: ComicListItem) -> Bool {
        guard configuration.isEnabled,
              itemIDs.insert(item.readingHistoryID).inserted else {
            return false
        }
        let titles = ComicTitleMatcher.normalizedTitleCandidates(item.title)
        guard !titles.isEmpty else { return false }
        let language = ComicTitleMatcher.normalizedLanguage(item.language)
        for title in titles {
            entriesByLength[title.count, default: []].append(
                Entry(
                    normalizedTitle: title,
                    language: language,
                    platform: item.platform
                )
            )
        }
        return true
    }

    @discardableResult
    mutating func insertBridge(_ item: ComicListItem) -> Bool {
        guard ComicTitleMatcher.normalizedLanguage(item.language) != nil else { return false }
        return insert(item)
    }

    func containsMatch(for item: ComicListItem, requiresDifferentPlatform: Bool = false) -> Bool {
        guard configuration.isEnabled else { return false }
        let titles = ComicTitleMatcher.normalizedTitleCandidates(item.title)
        guard !titles.isEmpty else { return false }

        let threshold = configuration.similarityThreshold
        let language = ComicTitleMatcher.normalizedLanguage(item.language)

        for title in titles {
            let minimumLength = Int(ceil(Double(title.count * threshold) / 100))
            let maximumLength = Int(floor(Double(title.count * 100) / Double(threshold)))
            guard minimumLength <= maximumLength else { continue }

            for length in minimumLength...maximumLength {
                guard let entries = entriesByLength[length] else { continue }
                for entry in entries {
                    if requiresDifferentPlatform, entry.platform == item.platform {
                        continue
                    }
                    if let language,
                       let entryLanguage = entry.language,
                       language != entryLanguage {
                        continue
                    }
                    if ComicTitleMatcher.normalizedTitlesMatch(
                        title,
                        entry.normalizedTitle,
                        threshold: threshold
                    ) {
                        return true
                    }
                }
            }
        }
        return false
    }
}

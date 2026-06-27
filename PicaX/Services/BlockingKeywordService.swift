import Combine
import Foundation

enum BlockingKeywordScope: Int, CaseIterable, Identifiable {
    case common
    case jmComic

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .common:
            "通用"
        case .jmComic:
            "JMComic"
        }
    }

    var storageKey: String {
        switch self {
        case .common:
            BlockingKeywordSettingsKey.common
        case .jmComic:
            BlockingKeywordSettingsKey.jmComic
        }
    }
}

struct BlockingKeywordFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isSuccess: Bool
}

@MainActor
final class BlockingKeywordService: ObservableObject {
    @Published private(set) var commonKeywords: [String]
    @Published private(set) var jmComicKeywords: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        commonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        jmComicKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
    }

    func keywords(for scope: BlockingKeywordScope) -> [String] {
        switch scope {
        case .common:
            commonKeywords
        case .jmComic:
            jmComicKeywords
        }
    }

    @discardableResult
    func add(_ rawKeyword: String, scope: BlockingKeywordScope) -> BlockingKeywordFeedback {
        let keyword = normalizedKeyword(rawKeyword)
        guard !keyword.isEmpty else {
            return BlockingKeywordFeedback(title: "没有添加", message: "屏蔽词不能为空。", isSuccess: false)
        }

        var keywords = keywords(for: scope)
        guard !keywords.contains(where: { $0.compare(keyword, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            return BlockingKeywordFeedback(title: "屏蔽词已存在", message: "\(scope.title) 分区已经包含“\(keyword)”。", isSuccess: false)
        }

        keywords.append(keyword)
        setKeywords(keywords, for: scope)
        return BlockingKeywordFeedback(title: "已添加屏蔽词", message: "已添加到\(scope.title)分区：\(keyword)", isSuccess: true)
    }

    @discardableResult
    func add(tag: ComicTagReference) -> BlockingKeywordFeedback {
        switch tag.platform {
        case .jmComic:
            add(tag.title, scope: .jmComic)
        default:
            add("tag:\(tag.title)", scope: .common)
        }
    }

    func remove(_ keyword: String, scope: BlockingKeywordScope) {
        let normalized = normalizedKeyword(keyword)
        var keywords = keywords(for: scope)
        keywords.removeAll { $0 == normalized }
        setKeywords(keywords, for: scope)
    }

    func remove(at offsets: IndexSet, displayedKeywords: [String], scope: BlockingKeywordScope) {
        for index in offsets {
            guard displayedKeywords.indices.contains(index) else { continue }
            remove(displayedKeywords[index], scope: scope)
        }
    }

    func blockedKeyword(for item: ComicListItem) -> String? {
        Self.blockedKeyword(for: item, commonKeywords: commonKeywords)
    }

    func visibleItems(from items: [ComicListItem]) -> [ComicListItem] {
        items.filter { blockedKeyword(for: $0) == nil }
    }

    func reloadFromDefaults() {
        commonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        jmComicKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
    }

    nonisolated static func jmKeywordByApplyingBlocks(to keyword: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let jmKeywords = loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
        guard !trimmed.isEmpty, !jmKeywords.isEmpty else { return trimmed }

        let blockingSet = Set(jmKeywords)
        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { word in
                guard word.hasPrefix("-") else { return true }
                return !blockingSet.contains(String(word.dropFirst()))
            }
        let cleanedKeyword = words.joined(separator: " ")
        return cleanedKeyword + jmKeywords.map { " -\($0)" }.joined()
    }

    nonisolated static func blockedKeyword(for item: ComicListItem, commonKeywords: [String]) -> String? {
        for keyword in commonKeywords {
            let rule = blockingRule(for: keyword)
            guard !rule.word.isEmpty else { continue }

            switch rule.mode {
            case 0:
                if contains(item.title, rule.word) || contains(item.subtitle, rule.word) {
                    return keyword
                }
            case 1:
                if contains(item.title, rule.word) {
                    return keyword
                }
            case 2:
                if contains(item.subtitle, rule.word) {
                    return keyword
                }
            case 3:
                break
            default:
                break
            }

            if rule.mode == 0 || rule.mode == 3 {
                if item.tags.contains(where: { tagMatches($0, word: rule.word) }) {
                    return keyword
                }
            }
        }

        return nil
    }

    private func setKeywords(_ keywords: [String], for scope: BlockingKeywordScope) {
        let normalized = uniqueKeywords(keywords)
        switch scope {
        case .common:
            commonKeywords = normalized
        case .jmComic:
            jmComicKeywords = normalized
        }
        defaults.set(normalized, forKey: scope.storageKey)
    }

    private func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for keyword in keywords.map(normalizedKeyword) where !keyword.isEmpty {
            let key = keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(keyword)
        }
        return result
    }

    private nonisolated static func loadKeywords(defaults: UserDefaults, key: String) -> [String] {
        defaults.stringArray(forKey: key)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private nonisolated static func contains(_ value: String, _ keyword: String) -> Bool {
        value.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private nonisolated static func tagMatches(_ tag: String, word: String) -> Bool {
        let candidates = tagCandidates(for: tag)
        return candidates.contains { candidate in
            candidate.compare(word, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private nonisolated static func tagCandidates(for tag: String) -> [String] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed, sexMarkerNormalized(trimmed)]

        if let colonIndex = trimmed.firstIndex(of: ":") {
            let right = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append(right)
            candidates.append(sexMarkerNormalized(right))
        }

        return candidates.filter { !$0.isEmpty }
    }

    private nonisolated static func blockingRule(for rawValue: String) -> (mode: Int, word: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("title:") {
            return (1, String(trimmed.dropFirst("title:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if trimmed.hasPrefix("uploader:") {
            return (2, String(trimmed.dropFirst("uploader:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if trimmed.hasPrefix("tag:") {
            return (3, String(trimmed.dropFirst("tag:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (0, trimmed)
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

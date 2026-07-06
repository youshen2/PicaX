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
    private(set) var commonKeywordMatcher: BlockingKeywordMatcher

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedCommonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        commonKeywords = loadedCommonKeywords
        jmComicKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
        commonKeywordMatcher = BlockingKeywordMatcher(keywords: loadedCommonKeywords)
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
        commonKeywordMatcher.blockedKeyword(for: item)
    }

    func visibleItems(from items: [ComicListItem]) -> [ComicListItem] {
        items.filter { blockedKeyword(for: $0) == nil }
    }

    func reloadFromDefaults() {
        let loadedCommonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        commonKeywordMatcher = BlockingKeywordMatcher(keywords: loadedCommonKeywords)
        commonKeywords = loadedCommonKeywords
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
        BlockingKeywordMatcher(keywords: commonKeywords).blockedKeyword(for: item)
    }

    private func setKeywords(_ keywords: [String], for scope: BlockingKeywordScope) {
        let normalized = uniqueKeywords(keywords)
        switch scope {
        case .common:
            commonKeywordMatcher = BlockingKeywordMatcher(keywords: normalized)
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
}

struct BlockingKeywordMatcher: Sendable {
    let fingerprint: Int

    private let rules: [BlockingKeywordRule]

    nonisolated init(keywords: [String]) {
        var hasher = Hasher()
        var rules: [BlockingKeywordRule] = []
        rules.reserveCapacity(keywords.count)

        for keyword in keywords {
            hasher.combine(keyword)
            guard let rule = BlockingKeywordRule(rawValue: keyword) else { continue }
            rules.append(rule)
        }

        self.rules = rules
        fingerprint = hasher.finalize()
    }

    nonisolated var isEmpty: Bool {
        rules.isEmpty
    }

    nonisolated func blockedKeyword(for item: ComicListItem) -> String? {
        guard !rules.isEmpty else { return nil }

        let title = Self.comparisonValue(item.title)
        let subtitle = Self.comparisonValue(item.subtitle)
        var tagCandidateSet: Set<String>?

        for rule in rules {
            switch rule.mode {
            case .all:
                if title.contains(rule.comparisonWord) || subtitle.contains(rule.comparisonWord) {
                    return rule.rawValue
                }
                if Self.tagCandidateSet(for: item.tags, cachedIn: &tagCandidateSet).contains(rule.comparisonWord) {
                    return rule.rawValue
                }
            case .title:
                if title.contains(rule.comparisonWord) {
                    return rule.rawValue
                }
            case .uploader:
                if subtitle.contains(rule.comparisonWord) {
                    return rule.rawValue
                }
            case .tag:
                if Self.tagCandidateSet(for: item.tags, cachedIn: &tagCandidateSet).contains(rule.comparisonWord) {
                    return rule.rawValue
                }
            }
        }

        return nil
    }

    private nonisolated static func tagCandidateSet(for tags: [String], cachedIn cache: inout Set<String>?) -> Set<String> {
        if let cache {
            return cache
        }
        let candidates = Set(tags.flatMap(tagCandidates(for:)))
        cache = candidates
        return candidates
    }

    private nonisolated static func tagCandidates(for tag: String) -> [String] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed, sexMarkerNormalized(trimmed)]

        if let colonIndex = trimmed.firstIndex(of: ":") {
            let right = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append(right)
            candidates.append(sexMarkerNormalized(right))
        }

        return candidates
            .filter { !$0.isEmpty }
            .map(comparisonValue)
    }

    private nonisolated static func comparisonValue(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

private struct BlockingKeywordRule: Sendable {
    enum Mode: Sendable {
        case all
        case title
        case uploader
        case tag
    }

    let rawValue: String
    let mode: Mode
    let comparisonWord: String

    nonisolated init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("title:") {
            let word = String(trimmed.dropFirst("title:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            self.rawValue = rawValue
            mode = .title
            comparisonWord = Self.comparisonValue(word)
            return
        }
        if trimmed.hasPrefix("uploader:") {
            let word = String(trimmed.dropFirst("uploader:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            self.rawValue = rawValue
            mode = .uploader
            comparisonWord = Self.comparisonValue(word)
            return
        }
        if trimmed.hasPrefix("tag:") {
            let word = String(trimmed.dropFirst("tag:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            self.rawValue = rawValue
            mode = .tag
            comparisonWord = Self.comparisonValue(word)
            return
        }
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = rawValue
        mode = .all
        comparisonWord = Self.comparisonValue(trimmed)
    }

    private nonisolated static func comparisonValue(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

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
    @Published private(set) var disabledKeywords: [String: Set<String>] = [:]

    private let defaults: UserDefaults
    private(set) var commonKeywordMatcher: BlockingKeywordMatcher

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedCommonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        commonKeywords = loadedCommonKeywords
        jmComicKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
        commonKeywordMatcher = BlockingKeywordMatcher(keywords: loadedCommonKeywords)
        reloadFromDefaults()
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
            add(tag.displayTitle, scope: .jmComic)
        case .nhentai, .eHentai, .hitomi:
            add("tag:\(tag.query)", scope: .common)
        default:
            add("tag:\(tag.displayTitle)", scope: .common)
        }
    }

    func remove(_ keyword: String, scope: BlockingKeywordScope) {
        let normalized = normalizedKeyword(keyword)
        var keywords = keywords(for: scope)
        keywords.removeAll { $0 == normalized }
        setKeywords(keywords, for: scope)
        setEnabled(true, keyword: normalized, scope: scope)
    }

    func remove(at offsets: IndexSet, displayedKeywords: [String], scope: BlockingKeywordScope) {
        for index in offsets {
            guard displayedKeywords.indices.contains(index) else { continue }
            remove(displayedKeywords[index], scope: scope)
        }
    }

    func isEnabled(_ keyword: String, scope: BlockingKeywordScope) -> Bool {
        !(disabledKeywords[scope.storageKey]?.contains(keyword) ?? false)
    }

    func setEnabled(_ enabled: Bool, keyword: String, scope: BlockingKeywordScope) {
        var disabled = disabledKeywords[scope.storageKey] ?? []
        if enabled { disabled.remove(keyword) } else { disabled.insert(keyword) }
        defaults.set(Array(disabled).sorted(), forKey: scope.storageKey + ".disabled")
        reloadFromDefaults()
    }

    func replace(_ original: String, with replacement: String, scope: BlockingKeywordScope) -> BlockingKeywordFeedback {
        if normalizedKeyword(replacement) == original {
            return BlockingKeywordFeedback(title: "已保存", message: original, isSuccess: true)
        }
        let wasEnabled = isEnabled(original, scope: scope)
        let feedback = add(replacement, scope: scope)
        if feedback.isSuccess {
            remove(original, scope: scope)
            setEnabled(wasEnabled, keyword: normalizedKeyword(replacement), scope: scope)
        }
        return feedback
    }

    func blockedKeyword(for item: ComicListItem) -> String? {
        commonKeywordMatcher.blockedKeyword(for: item)
    }

    func visibleItems(from items: [ComicListItem]) -> [ComicListItem] {
        guard !commonKeywordMatcher.isEmpty else { return items }
        let tagResolver = ComicListTagResolver(comics: items)
        return items.filter { commonKeywordMatcher.blockedKeyword(for: $0, tagResolver: tagResolver) == nil }
    }

    func reloadFromDefaults() {
        let disabled = Dictionary(uniqueKeysWithValues: BlockingKeywordScope.allCases.map {
            ($0.storageKey, Set(defaults.stringArray(forKey: $0.storageKey + ".disabled") ?? []))
        })
        let loadedCommonKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.common)
        commonKeywordMatcher = BlockingKeywordMatcher(keywords: loadedCommonKeywords.filter {
            !(disabled[BlockingKeywordSettingsKey.common]?.contains($0) ?? false)
        })
        disabledKeywords = disabled
        commonKeywords = loadedCommonKeywords
        jmComicKeywords = Self.loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic)
    }

    nonisolated static func jmKeywordByApplyingBlocks(to keyword: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let disabled = Set(defaults.stringArray(forKey: BlockingKeywordSettingsKey.jmComic + ".disabled") ?? [])
        let jmKeywords = loadKeywords(defaults: defaults, key: BlockingKeywordSettingsKey.jmComic).filter { !disabled.contains($0) }
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
            commonKeywordMatcher = BlockingKeywordMatcher(keywords: normalized.filter { isEnabled($0, scope: .common) })
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

    nonisolated func blockedKeyword(
        for item: ComicListItem,
        tagResolver: ComicListTagResolver? = nil
    ) -> String? {
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
                if Self.tagCandidateSet(for: item, resolver: tagResolver, cachedIn: &tagCandidateSet).contains(ComicListTagResolver.normalizedTag(rule.comparisonWord)) {
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
                if Self.tagCandidateSet(for: item, resolver: tagResolver, cachedIn: &tagCandidateSet).contains(rule.comparisonWord) {
                    return rule.rawValue
                }
            }
        }

        return nil
    }

    private nonisolated static func tagCandidateSet(
        for item: ComicListItem,
        resolver: ComicListTagResolver?,
        cachedIn cache: inout Set<String>?
    ) -> Set<String> {
        if let cache {
            return cache
        }
        let resolver = resolver ?? ComicListTagResolver(comics: [item])
        let candidates = Set(resolver.matchingTags(for: item).flatMap(tagCandidates(for:)))
        cache = candidates
        return candidates
    }

    private nonisolated static func tagCandidates(for tag: String) -> [String] {
        let trimmed = ComicListTagResolver.normalizedTag(tag)
        var candidates = [trimmed]

        if let colonIndex = trimmed.firstIndex(of: ":") {
            let right = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append(right)
        }

        return candidates
            .filter { !$0.isEmpty }
            .map(comparisonValue)
    }

    private nonisolated static func comparisonValue(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
            comparisonWord = Self.comparisonValue(ComicListTagResolver.normalizedTag(word))
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

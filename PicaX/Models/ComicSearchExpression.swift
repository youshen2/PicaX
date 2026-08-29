import Foundation

nonisolated struct ComicSearchClause: Equatable, Hashable, Sendable {
    let terms: [String]

    var breakpointKey: String {
        terms.joined(separator: "&")
    }

    var displayKeyword: String {
        terms.joined(separator: " & ")
    }

    func keyword(for platform: ComicPlatform) -> String {
        guard terms.count > 1 else { return terms[0] }

        switch platform {
        case .nhentai, .eHentai:
            return terms.map(Self.quotedTag).joined(separator: " ")
        case .picacg, .htManga, .jmComic, .hitomi:
            return terms.joined(separator: " ")
        }
    }

    private static func quotedTag(_ term: String) -> String {
        term.contains(where: \.isWhitespace) ? "\"\(term)\"" : term
    }
}

nonisolated enum ComicSearchExpressionParser {
    static func clauses(from rawKeyword: String) -> [ComicSearchClause] {
        rawKeyword
            .components(separatedBy: "/")
            .compactMap { rawClause in
                let terms = rawClause
                    .components(separatedBy: "&")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return terms.isEmpty ? nil : ComicSearchClause(terms: terms)
            }
    }
}

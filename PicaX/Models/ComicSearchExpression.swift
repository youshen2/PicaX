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
        case .picacg, .htManga, .jmComic, .hitomi, .local:
            return terms.joined(separator: " ")
        }
    }

    private static func quotedTag(_ term: String) -> String {
        term.contains(where: \.isWhitespace) && !term.contains("\"") ? "\"\(term)\"" : term
    }
}

nonisolated enum ComicSearchExpressionParser {
    static let maximumClauseCount = 256

    static func clauses(from rawKeyword: String) throws -> [ComicSearchClause] {
        var parser = Parser(keyword: rawKeyword)
        return try parser.parse()
    }

    private struct Parser {
        let keyword: String
        var operands: [[ComicSearchClause]] = []
        var operators: [ComicSearchExpressionTokenizer.Kind] = []
        var needsOperand = true

        mutating func parse() throws -> [ComicSearchClause] {
            for token in ComicSearchExpressionTokenizer.tokens(in: keyword) {
                switch token.kind {
                case .term:
                    guard needsOperand else { throw ComicSearchExpressionError.missingOperator }
                    let term = keyword[token.range].trimmingCharacters(in: .whitespacesAndNewlines)
                    operands.append([ComicSearchClause(terms: [term])])
                    needsOperand = false
                case .openingParenthesis:
                    guard needsOperand else { throw ComicSearchExpressionError.missingOperator }
                    operators.append(.openingParenthesis)
                case .closingParenthesis:
                    appendEmptyOperandIfNeeded()
                    while let operation = operators.last, operation != .openingParenthesis {
                        try reduce()
                    }
                    guard operators.popLast() == .openingParenthesis else {
                        throw ComicSearchExpressionError.unbalancedParentheses
                    }
                    needsOperand = false
                case .slash, .ampersand:
                    appendEmptyOperandIfNeeded()
                    while let operation = operators.last,
                          operation != .openingParenthesis,
                          operation.precedence >= token.kind.precedence {
                        try reduce()
                    }
                    operators.append(token.kind)
                    needsOperand = true
                }
            }

            appendEmptyOperandIfNeeded()
            while !operators.isEmpty {
                try reduce()
            }
            return operands.last ?? []
        }

        private mutating func appendEmptyOperandIfNeeded() {
            if needsOperand {
                operands.append([])
            }
        }

        private mutating func reduce() throws {
            let operation = operators.removeLast()
            guard operation != .openingParenthesis else {
                throw ComicSearchExpressionError.unbalancedParentheses
            }
            let right = operands.removeLast()
            let left = operands.removeLast()
            var result: [ComicSearchClause] = []
            var seen = Set<Set<String>>()

            func append(_ clause: ComicSearchClause) throws {
                guard seen.insert(Set(clause.terms)).inserted else { return }
                guard result.count < maximumClauseCount else {
                    throw ComicSearchExpressionError.tooManyClauses
                }
                result.append(clause)
            }

            if operation == .slash || left.isEmpty || right.isEmpty {
                for clause in left + right {
                    try append(clause)
                }
            } else {
                for lhs in left {
                    for rhs in right {
                        var terms = Set(lhs.terms)
                        let combined = lhs.terms + rhs.terms.filter { terms.insert($0).inserted }
                        try append(ComicSearchClause(terms: combined))
                    }
                }
            }
            operands.append(result)
        }
    }
}

nonisolated enum ComicSearchExpressionError: LocalizedError {
    case unbalancedParentheses
    case missingOperator
    case tooManyClauses

    var errorDescription: String? {
        switch self {
        case .unbalancedParentheses:
            "搜索关键词的括号未配对，请检查左、右括号。"
        case .missingOperator:
            "关键词与括号分组之间请使用 / 或 & 连接；标签本身包含括号时，请用双引号包住标签。"
        case .tooManyClauses:
            "搜索组合超过 \(ComicSearchExpressionParser.maximumClauseCount) 组，请减少 / 分支。"
        }
    }
}

import Foundation

nonisolated enum ComicSearchExpressionTokenizer {
    enum Kind: Equatable {
        case term
        case slash
        case ampersand
        case openingParenthesis
        case closingParenthesis

        var precedence: Int {
            self == .ampersand ? 2 : 1
        }
    }

    struct Token {
        let kind: Kind
        let range: Range<String.Index>
    }

    static func tokens(in keyword: String) -> [Token] {
        var result: [Token] = []
        var termStart = keyword.startIndex
        var isQuoted = false
        var isEscaped = false

        func appendTerm(endingAt end: String.Index) {
            let range = termStart..<end
            guard !keyword[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(Token(kind: .term, range: range))
        }

        for index in keyword.indices {
            let character = keyword[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if isQuoted, character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                continue
            }
            guard !isQuoted else { continue }

            let kind: Kind
            switch character {
            case "/": kind = .slash
            case "&": kind = .ampersand
            case "(", "（": kind = .openingParenthesis
            case ")", "）": kind = .closingParenthesis
            default: continue
            }
            appendTerm(endingAt: index)
            let end = keyword.index(after: index)
            result.append(Token(kind: kind, range: index..<end))
            termStart = end
        }
        appendTerm(endingAt: keyword.endIndex)
        return result
    }

    static func currentOperandRange(in keyword: String) -> Range<String.Index> {
        var end = keyword.endIndex
        for token in tokens(in: keyword).reversed() {
            switch token.kind {
            case .closingParenthesis:
                end = token.range.lowerBound
            case .term:
                return token.range
            case .openingParenthesis, .slash, .ampersand:
                return token.range.upperBound..<end
            }
        }
        return keyword.startIndex..<end
    }
}

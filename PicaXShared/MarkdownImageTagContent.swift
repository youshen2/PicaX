import Foundation

nonisolated struct MarkdownImageTagContent: Equatable, Sendable {
    enum Segment: Equatable, Sendable {
        case text(String)
        case image(String)

        var imageURL: URL? {
            guard case .image(let value) = self else { return nil }
            if value.hasPrefix("//") {
                return URL(string: "https:\(value)")
            }
            guard let url = URL(string: value), url.scheme?.isEmpty == false else {
                return nil
            }
            return url
        }
    }

    let segments: [Segment]

    init(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("!["), let parsedSegments = Self.parse(value) else {
            segments = value.isEmpty ? [] : [.text(value)]
            return
        }
        segments = parsedSegments
    }

    var plainText: String {
        segments.compactMap { segment in
            guard case .text(let value) = segment else { return nil }
            return value
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var accessibilityLabel: String {
        plainText.isEmpty ? "图片标签" : plainText
    }

    private static func parse(_ value: String) -> [Segment]? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let content = try? AttributedString(markdown: value, options: options) else {
            return nil
        }

        var containsImage = false
        var rawSegments: [Segment] = []
        for run in content.runs {
            if let imageURL = run.imageURL {
                containsImage = true
                rawSegments.append(.image(imageURL.absoluteString))
            } else {
                appendText(String(content[run.range].characters), to: &rawSegments)
            }
        }
        guard containsImage else { return nil }

        let normalizedSegments = rawSegments.compactMap { segment -> Segment? in
            guard case .text(let text) = segment else { return segment }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : .text(value)
        }
        return normalizedSegments.isEmpty ? nil : normalizedSegments
    }

    private static func appendText(_ text: String, to segments: inout [Segment]) {
        guard !text.isEmpty else { return }
        if case .text(let previous)? = segments.last {
            segments[segments.count - 1] = .text(previous + text)
        } else {
            segments.append(.text(text))
        }
    }
}

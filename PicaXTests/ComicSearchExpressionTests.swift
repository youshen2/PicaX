import XCTest
@testable import PicaX

final class ComicSearchExpressionTests: XCTestCase {
    func testNormalSearchPreservesInternalWhitespace() throws {
        let clause = try XCTUnwrap(
            ComicSearchExpressionParser.clauses(from: "  magical   girl  ").first
        )

        XCTAssertEqual(clause.terms, ["magical   girl"])
        XCTAssertEqual(clause.keyword(for: .nhentai), "magical   girl")
    }

    func testSlashCreatesIndependentSearchClauses() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: "猫 娘 / 萝 莉")

        XCTAssertEqual(clauses.map(\.terms), [["猫 娘"], ["萝 莉"]])
        XCTAssertEqual(clauses.map(\.breakpointKey), ["猫 娘", "萝 莉"])
    }

    func testAmpersandCreatesAllTagClause() throws {
        let clause = try XCTUnwrap(
            ComicSearchExpressionParser.clauses(from: "magical girl & 萝 莉").first
        )

        XCTAssertEqual(clause.terms, ["magical girl", "萝 莉"])
        XCTAssertEqual(clause.keyword(for: .nhentai), "\"magical girl\" \"萝 莉\"")
        XCTAssertEqual(clause.keyword(for: .picacg), "magical girl 萝 莉")
    }

    func testMixedOperatorsUseSlashBetweenAllTagClauses() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: "猫娘&萝莉/御 姐")

        XCTAssertEqual(clauses.map(\.terms), [["猫娘", "萝莉"], ["御 姐"]])
        XCTAssertEqual(clauses.map(\.breakpointKey), ["猫娘&萝莉", "御 姐"])
    }

    func testEmptyOperandsAreIgnored() throws {
        XCTAssertEqual(
            try ComicSearchExpressionParser.clauses(from: " / 猫娘 && / ").map(\.terms),
            [["猫娘"]]
        )
    }

    func testParenthesizedAlternativesDistributeAcrossCombinedTags() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: "(A/B)&(C/D)")
        XCTAssertEqual(clauses.map(\.terms), [["A", "C"], ["A", "D"], ["B", "C"], ["B", "D"]])
        XCTAssertEqual(clauses.map(\.breakpointKey), ["A&C", "A&D", "B&C", "B&D"])
    }

    func testNestedParenthesesPreserveOperatorPrecedence() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: "A & （B / (C & D)） / E")
        XCTAssertEqual(clauses.map(\.terms), [["A", "B"], ["A", "C", "D"], ["E"]])
    }

    func testQuotedTagKeepsLiteralParenthesesAndOperators() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: #"(character:"A (B/C)" / D)&"E & F""#)
        XCTAssertEqual(clauses.map(\.terms), [[#"character:"A (B/C)""#, #""E & F""#], ["D", #""E & F""#]])
        XCTAssertEqual(clauses.first?.keyword(for: .eHentai), #"character:"A (B/C)" "E & F""#)
    }

    func testRepeatedCombinationsAreSearchedOnce() throws {
        let clauses = try ComicSearchExpressionParser.clauses(from: "(A/B)&(A/B)")
        XCTAssertEqual(clauses.map(\.terms), [["A"], ["A", "B"], ["B"]])
    }

    func testInvalidParenthesesAndMissingOperatorsAreRejected() {
        for keyword in ["(A/B", "A/B)", "A(B/C)", "(A/B)(C/D)"] {
            XCTAssertThrowsError(try ComicSearchExpressionParser.clauses(from: keyword), keyword)
        }
    }

    func testExpansionStopsWhenCombinationLimitIsExceeded() {
        let keyword = (0..<9).map { "(A\($0)/B\($0))" }.joined(separator: "&")
        XCTAssertThrowsError(try ComicSearchExpressionParser.clauses(from: keyword)) { error in
            guard case ComicSearchExpressionError.tooManyClauses = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCompletionOperandKeepsSurroundingParentheses() {
        let keyword = "A & (B / (magical girl))"
        let range = ComicSearchExpressionTokenizer.currentOperandRange(in: keyword)
        XCTAssertEqual(String(keyword[range]), "magical girl")
        XCTAssertEqual(String(keyword[..<range.lowerBound]) + "full color" + keyword[range.upperBound...], "A & (B / (full color))")

        let unfinished = "A & ("
        XCTAssertTrue(ComicSearchExpressionTokenizer.currentOperandRange(in: unfinished).isEmpty)
    }
}

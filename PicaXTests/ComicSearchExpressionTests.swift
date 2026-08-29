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

    func testSlashCreatesIndependentSearchClauses() {
        let clauses = ComicSearchExpressionParser.clauses(from: "猫 娘 / 萝 莉")

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

    func testMixedOperatorsUseSlashBetweenAllTagClauses() {
        let clauses = ComicSearchExpressionParser.clauses(from: "猫娘&萝莉/御 姐")

        XCTAssertEqual(clauses.map(\.terms), [["猫娘", "萝莉"], ["御 姐"]])
        XCTAssertEqual(clauses.map(\.breakpointKey), ["猫娘&萝莉", "御 姐"])
    }

    func testEmptyOperandsAreIgnored() {
        XCTAssertEqual(
            ComicSearchExpressionParser.clauses(from: " / 猫娘 && / ").map(\.terms),
            [["猫娘"]]
        )
    }
}

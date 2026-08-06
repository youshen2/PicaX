import XCTest
@testable import PicaX

final class ComicSearchKeywordSequenceTests: XCTestCase {
    func testKeepsOriginalKeywordWhenSeparateSearchIsDisabled() {
        XCTAssertEqual(
            ComicSearchKeywordSequence.keywords(
                from: "  magical girl  ",
                searchesSeparately: false
            ),
            ["magical girl"]
        )
    }

    func testSplitsKeywordsInInputOrderWhenSeparateSearchIsEnabled() {
        XCTAssertEqual(
            ComicSearchKeywordSequence.keywords(
                from: "magical   girl\ttransformation",
                searchesSeparately: true
            ),
            ["magical", "girl", "transformation"]
        )
    }

    func testReturnsNoKeywordsForWhitespaceOnlyInput() {
        XCTAssertTrue(
            ComicSearchKeywordSequence.keywords(
                from: " \n\t ",
                searchesSeparately: true
            ).isEmpty
        )
    }
}

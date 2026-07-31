import XCTest
@testable import PicaX

@MainActor
final class NhentaiTagSuggestionServiceTests: XCTestCase {
    func testDetailTagReferenceUsesTranslatedTitleAndPreservesSearchQuery() throws {
        let tag = try XCTUnwrap(
            NhentaiTagSuggestionService.detailTagReference(
                forTagName: "granblue fantasy",
                group: "parody"
            )
        )

        XCTAssertEqual(tag.displayTitle, "碧蓝幻想")
        XCTAssertEqual(tag.query, "granblue fantasy")
        XCTAssertEqual(tag.platform, .nhentai)
    }

    func testDetailTagReferenceRejectsBlankName() {
        XCTAssertNil(
            NhentaiTagSuggestionService.detailTagReference(
                forTagName: "  \n ",
                group: "tag"
            )
        )
    }
}

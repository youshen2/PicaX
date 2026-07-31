import XCTest
@testable import PicaX

final class ComicSearchAdvancedOptionsTests: XCTestCase {
    func testAppliesIndependentLanguageFiltersToNhentaiAndEhentai() {
        let options = ComicSearchAdvancedOptions(
            nhentaiLanguage: .chinese,
            ehentaiLanguage: .english
        )

        XCTAssertEqual(options.keyword("fantasy", for: .nhentai), "fantasy language:chinese")
        XCTAssertEqual(options.keyword("fantasy", for: .eHentai), "fantasy language:english")
        XCTAssertEqual(options.keyword("fantasy", for: .picacg), "fantasy")
    }

    func testSelectedLanguageReplacesExistingLanguageFilter() {
        let options = ComicSearchAdvancedOptions(ehentaiLanguage: .chinese)

        XCTAssertEqual(
            options.keyword("artist:test LANGUAGE:japanese", for: .eHentai),
            "artist:test language:chinese"
        )
        XCTAssertEqual(
            options.keyword("language:japanese", for: .eHentai),
            "language:chinese"
        )
    }

    func testLanguageSelectionMarksEachSupportedPlatformAsCustomized() {
        let options = ComicSearchAdvancedOptions(ehentaiLanguage: .japanese)

        XCTAssertTrue(options.isCustomized(for: .eHentai))
        XCTAssertFalse(options.isCustomized(for: .nhentai))
    }
}

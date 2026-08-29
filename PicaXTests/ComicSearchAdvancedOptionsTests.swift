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

    func testSearchHistoryRoundTripsAdvancedOptions() throws {
        let options = ComicSearchAdvancedOptions(
            picacgSort: "ld",
            nhentaiSort: "popular-week",
            jmComicSort: "mv_m",
            nhentaiLanguage: .chinese,
            ehentaiLanguage: .english
        )
        let record = SearchHistoryRecord(
            keyword: "fantasy",
            target: .aggregate([.picacg, .nhentai, .eHentai]),
            advancedOptions: options,
            searchesKeywordsSeparately: true,
            breakpoint: ComicSearchBreakpoint(
                requests: [
                    ComicSearchBreakpoint.Request(keyword: "fantasy", platform: .picacg, nextPage: 3),
                    ComicSearchBreakpoint.Request(keyword: "fantasy", platform: .nhentai, nextPage: 2)
                ]
            ),
            searchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let decoded = try JSONDecoder().decode(
            SearchHistoryRecord.self,
            from: JSONEncoder().encode(record)
        )

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.advancedOptions, options)
        XCTAssertTrue(decoded.searchesKeywordsSeparately)
        XCTAssertTrue(decoded.breakpoint?.isAvailable == true)
    }

    func testLegacySearchHistoryWithoutAdvancedOptionsUsesDefaults() throws {
        let record = SearchHistoryRecord(
            keyword: "legacy",
            target: .platform(.nhentai),
            searchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = try JSONEncoder().encode(record)
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        payload.removeValue(forKey: "advancedOptions")
        payload.removeValue(forKey: "searchesKeywordsSeparately")
        payload.removeValue(forKey: "breakpoint")

        let decoded = try JSONDecoder().decode(
            SearchHistoryRecord.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.advancedOptions, ComicSearchAdvancedOptions())
        XCTAssertFalse(decoded.searchesKeywordsSeparately)
        XCTAssertNil(decoded.breakpoint)
    }
}

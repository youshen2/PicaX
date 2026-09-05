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
            keyword: "fantasy/cat",
            target: .aggregate([.picacg, .nhentai, .eHentai]),
            advancedOptions: options,
            breakpoint: ComicSearchBreakpoint(
                requests: [
                    ComicSearchBreakpoint.Request(keyword: "fantasy", platform: .picacg, nextPage: 3),
                    ComicSearchBreakpoint.Request(keyword: "cat", platform: .nhentai, nextPage: 2)
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
        XCTAssertTrue(decoded.breakpoint?.isAvailable == true)
        XCTAssertEqual(decoded.resumableBreakpoint, decoded.breakpoint)
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
        payload.removeValue(forKey: "breakpoint")

        let decoded = try JSONDecoder().decode(
            SearchHistoryRecord.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.advancedOptions, ComicSearchAdvancedOptions())
        XCTAssertNil(decoded.breakpoint)
    }

    func testHistoryIgnoresBreakpointsThatDoNotMatchExpression() {
        let record = SearchHistoryRecord(
            keyword: "magical girl",
            target: .platform(.nhentai),
            breakpoint: ComicSearchBreakpoint(
                requests: [
                    ComicSearchBreakpoint.Request(keyword: "magical", platform: .nhentai, nextPage: 2)
                ]
            ),
            searchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(record.resumableBreakpoint)
    }

    func testHistoryResumesExpandedParenthesizedClauses() {
        let requests = [
            ComicSearchBreakpoint.Request(keyword: "A&C", platform: .nhentai, nextPage: 3),
            ComicSearchBreakpoint.Request(keyword: "B&C", platform: .nhentai, nextPage: 5)
        ]
        let record = SearchHistoryRecord(
            keyword: "(A/B)&C",
            target: .platform(.nhentai),
            breakpoint: ComicSearchBreakpoint(requests: requests),
            searchedAt: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(record.resumableBreakpoint?.requests, requests)
    }
}

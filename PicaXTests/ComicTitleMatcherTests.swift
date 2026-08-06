import XCTest
@testable import PicaX

final class ComicTitleMatcherTests: XCTestCase {
    func testDefaultConfigurationIsEnabledAtNinetyFivePercent() {
        let configuration = ComicTitleMatchingConfiguration()

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.similarityThreshold, 95)
    }

    func testTitleNormalizationIgnoresWidthCaseSpacingAndPunctuation() {
        let lhs = item(
            id: "1",
            platform: .nhentai,
            title: "Ｔhé Comic: Name!",
            language: "English"
        )
        let rhs = item(
            id: "2",
            platform: .eHentai,
            title: "the comic name",
            language: "english"
        )

        XCTAssertTrue(ComicTitleMatcher.titlesMatch(lhs, rhs, configuration: .init()))
        XCTAssertEqual(ComicTitleMatcher.similarityPercent(lhs.title, rhs.title), 100, accuracy: 0.001)
    }

    func testSimilarityThresholdIncludesBoundaryAndRejectsLowerScore() {
        let lhs = item(id: "1", platform: .nhentai, title: "abcdefghijklmnopqrst")
        let rhs = item(id: "2", platform: .eHentai, title: "abcdefghijklmnopqrsx")

        XCTAssertTrue(
            ComicTitleMatcher.titlesMatch(
                lhs,
                rhs,
                configuration: .init(isEnabled: true, similarityThreshold: 95)
            )
        )
        XCTAssertFalse(
            ComicTitleMatcher.titlesMatch(
                lhs,
                rhs,
                configuration: .init(isEnabled: true, similarityThreshold: 96)
            )
        )
    }

    func testKnownDifferentLanguagesDoNotMatch() {
        let chinese = item(id: "1", platform: .nhentai, title: "Same Title", language: "chinese")
        let japanese = item(id: "2", platform: .eHentai, title: "Same Title", language: "japanese")
        let unknown = item(id: "3", platform: .hitomi, title: "Same Title")

        XCTAssertFalse(ComicTitleMatcher.titlesMatch(chinese, japanese, configuration: .init()))
        XCTAssertTrue(ComicTitleMatcher.titlesMatch(chinese, unknown, configuration: .init()))
    }

    func testMultilingualAliasCanMatchAStandaloneTranslatedTitle() {
        let translated = item(id: "1", platform: .picacg, title: "不知你我")
        let multilingual = item(
            id: "2",
            platform: .hitomi,
            title: "Temae o Shiranai | 不知你我",
            language: "chinese"
        )

        XCTAssertTrue(ComicTitleMatcher.titlesMatch(translated, multilingual, configuration: .init()))
    }

    func testBracketedMetadataIsRemovedBeforeMatchingAliases() {
        let nhentai = item(
            id: "1",
            platform: .nhentai,
            title: "[apart de Matteru (Odaneru apart)] Temae o Shiranai [Chinese]",
            language: "chinese"
        )
        let hitomi = item(
            id: "2",
            platform: .hitomi,
            title: "Temae o Shiranai | 不知你我",
            language: "chinese"
        )

        XCTAssertTrue(ComicTitleMatcher.titlesMatch(nhentai, hitomi, configuration: .init()))
    }

    func testSharedLongBracketedCreatorDoesNotMatchDifferentWorks() {
        let first = item(
            id: "1",
            platform: .nhentai,
            title: "[A Very Long Circle Name (Same Author)] First Work",
            language: "english"
        )
        let second = item(
            id: "2",
            platform: .eHentai,
            title: "[A Very Long Circle Name (Same Author)] Second Story",
            language: "english"
        )

        XCTAssertFalse(ComicTitleMatcher.titlesMatch(first, second, configuration: .init()))
    }

    func testKnownLanguageAliasCanBridgeTwoTitleVariants() {
        let translatedHistory = item(id: "1", platform: .picacg, title: "不知你我")
        let bilingualBridge = item(
            id: "2",
            platform: .hitomi,
            title: "Temae o Shiranai | 不知你我",
            language: "chinese"
        )
        let romanizedResult = item(
            id: "3",
            platform: .nhentai,
            title: "[apart de Matteru] Temae o Shiranai [Chinese]",
            language: "chinese"
        )
        var index = ComicTitleMatchIndex(items: [translatedHistory], configuration: .init())

        XCTAssertTrue(index.containsMatch(for: bilingualBridge, requiresDifferentPlatform: true))
        XCTAssertTrue(index.insertBridge(bilingualBridge))
        XCTAssertTrue(index.containsMatch(for: romanizedResult, requiresDifferentPlatform: true))
    }

    func testIndexCanRequireARecordFromAnotherPlatform() {
        let source = item(id: "1", platform: .nhentai, title: "Cross Platform Comic", language: "english")
        let index = ComicTitleMatchIndex(items: [source], configuration: .init())
        let samePlatform = item(id: "2", platform: .nhentai, title: "Cross Platform Comic", language: "english")
        let otherPlatform = item(id: "3", platform: .eHentai, title: "Cross Platform Comic", language: "english")
        let otherLanguage = item(id: "4", platform: .eHentai, title: "Cross Platform Comic", language: "japanese")

        XCTAssertFalse(index.containsMatch(for: samePlatform, requiresDifferentPlatform: true))
        XCTAssertTrue(index.containsMatch(for: otherPlatform, requiresDifferentPlatform: true))
        XCTAssertFalse(index.containsMatch(for: otherLanguage, requiresDifferentPlatform: true))
    }

    func testDisabledConfigurationNeverMatches() {
        let lhs = item(id: "1", platform: .nhentai, title: "Same Title")
        let rhs = item(id: "2", platform: .eHentai, title: "Same Title")

        XCTAssertFalse(
            ComicTitleMatcher.titlesMatch(
                lhs,
                rhs,
                configuration: .init(isEnabled: false, similarityThreshold: 95)
            )
        )
    }

    private func item(
        id: String,
        platform: ComicPlatform,
        title: String,
        language: String? = nil
    ) -> ComicListItem {
        ComicListItem(
            id: id,
            platform: platform,
            title: title,
            subtitle: "",
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil,
            language: language
        )
    }
}

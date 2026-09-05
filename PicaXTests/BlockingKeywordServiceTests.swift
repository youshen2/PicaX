import Foundation
import XCTest
@testable import PicaX

@MainActor
final class BlockingKeywordServiceTests: XCTestCase {
    func testTranslatedEhentaiAndNhentaiTagsUseOriginalQueryAsBlockingKeyword() {
        let suiteName = "BlockingKeywordServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = BlockingKeywordService(defaults: defaults)

        service.add(
            tag: ComicTagReference(
                title: "巨乳",
                query: "female:big breasts",
                platform: .eHentai,
                urlString: nil
            )
        )
        service.add(
            tag: ComicTagReference(
                title: "碧蓝幻想",
                query: "granblue fantasy",
                platform: .nhentai,
                urlString: nil
            )
        )

        XCTAssertEqual(
            service.commonKeywords,
            ["tag:female:big breasts", "tag:granblue fantasy"]
        )
    }

    func testEhentaiGalleryPreservesOriginalTagsForBlocking() throws {
        let html = """
        <a href="https://e-hentai.org/g/123/token/" class="glink">Sample</a>
        <div class="gt" title="female:big breasts">big breasts</div>
        <div class="gt" title="language:chinese">chinese</div>
        """
        let comic = try XCTUnwrap(ComicContentService().ehentaiGalleryItem(from: html, favoriteDate: nil))

        XCTAssertEqual(comic.tags, ["female:big breasts", "language:chinese"])
        assertBlocked(comic, keywords: ["tag:female:big breasts", "tag:big breasts", "tag:巨乳", "tag:female:巨乳", "tag:language:chinese"])
        XCTAssertNil(BlockingKeywordMatcher(keywords: ["tag:male:big breasts"]).blockedKeyword(for: comic))
        XCTAssertEqual(
            ComicListTagResolver(nhentaiCache: [:]).displayTagsByID(for: [comic])[comic.readingHistoryID]?.first,
            "巨乳"
        )
    }

    func testNhentaiBlockingResolvesTagIDsBeyondTheDisplayLimit() {
        let records = (1...7).map { id in
            StoredNhentaiTagName(id: id, group: "parody", name: id == 7 ? "granblue fantasy" : "sample \(id)")
        }
        let tags = ComicContentService().nhentaiListTags(from: ["tag_ids": Array(1...7)], tagRecords: records)
        let comic = item(platform: .nhentai, tags: tags)
        let resolver = ComicListTagResolver(nhentaiCache: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }))

        XCTAssertEqual(tags.count, 7)
        for keyword in ["tag:granblue fantasy", "tag:parody:granblue fantasy", "tag:碧蓝幻想", "碧蓝幻想"] {
            XCTAssertEqual(BlockingKeywordMatcher(keywords: [keyword]).blockedKeyword(for: comic, tagResolver: resolver), keyword)
        }
        XCTAssertNil(
            BlockingKeywordMatcher(keywords: ["tag:granblue fantasy"]).blockedKeyword(
                for: comic,
                tagResolver: ComicListTagResolver(nhentaiCache: [:])
            )
        )
    }

    func testNhentaiNamedTagsPreserveAllNamespaces() {
        let records = (1...7).map { id in
            StoredNhentaiTagName(id: id, group: id == 7 ? "language" : "tag", name: id == 7 ? "chinese" : "sample \(id)")
        }
        let tags = ComicContentService().nhentaiListTags(from: [:], tagRecords: records)
        let comic = item(platform: .nhentai, tags: tags)

        XCTAssertEqual(tags.count, 7)
        XCTAssertEqual(tags.last, "language:chinese")
        assertBlocked(comic, keywords: ["tag:language:chinese", "tag:chinese", "tag:汉语"])
    }

    func testQuotedEhentaiTagQueryMatchesWithoutLosingNamespace() {
        let comic = item(platform: .eHentai, tags: ["female:big breasts"])
        assertBlocked(comic, keywords: [#"tag:female:"big breasts$""#, #"tag:"big breasts""#, "tag:FEMALE:Big Breasts"])
        let quotedComic = item(platform: .eHentai, tags: [#"female:"big breasts$""#])
        assertBlocked(quotedComic, keywords: ["tag:female:big breasts", "tag:巨乳"])
        XCTAssertNil(BlockingKeywordMatcher(keywords: [#"tag:male:"big breasts$""#]).blockedKeyword(for: comic))
    }

    func testHitomiOriginalAndTranslatedTagsCanBeBlocked() {
        let comic = item(platform: .hitomi, tags: ["female:big breasts"])
        assertBlocked(comic, keywords: ["tag:female:big breasts", "tag:big breasts", "tag:big breasts ♀", "tag:巨乳"])
        let legacyComic = item(platform: .hitomi, tags: ["big breasts ♀"])
        assertBlocked(legacyComic, keywords: ["tag:big breasts", "tag:big breasts ♀", "tag:巨乳"])
    }

    func testHitomiSeriesListMatchesTheDetailParodyTag() {
        let tags = ComicContentService().hitomiBriefTags(
            #"<td class="series-list"><a href="/series/granblue%20fantasy-all.html">granblue fantasy</a></td>"#
        )
        let comic = item(platform: .hitomi, tags: tags.map(\.query))
        assertBlocked(comic, keywords: ["tag:parody:granblue fantasy", "tag:碧蓝幻想"])
        assertBlocked(item(platform: .hitomi, tags: ["tag:big breasts"]), keywords: ["tag:巨乳"])
    }

    func testHitomiTagUsesOriginalQueryAsBlockingKeyword() {
        let suiteName = "BlockingKeywordServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = BlockingKeywordService(defaults: defaults)
        service.add(tag: ComicTagReference(title: "big breasts ♀", query: "female:big breasts", platform: .hitomi, urlString: nil))
        let blocked = item(platform: .hitomi, tags: ["female:big breasts"])
        let visible = item(platform: .hitomi, tags: ["male:big breasts"])

        XCTAssertEqual(service.commonKeywords, ["tag:female:big breasts"])
        XCTAssertEqual(service.visibleItems(from: [blocked, visible]), [visible])
    }

    func testFieldScopesAndExactTagMatchingRemainUnchanged() {
        let comic = item(platform: .picacg, tags: ["sample tag"])
        assertBlocked(comic, keywords: ["title:sample", "uploader:author", "tag:sample tag", "sample tag"])
        for keyword in ["tag:sample", "title:author", "uploader:sample tag", "tag:author"] {
            XCTAssertNil(BlockingKeywordMatcher(keywords: [keyword]).blockedKeyword(for: comic))
        }
        XCTAssertNil(BlockingKeywordMatcher(keywords: []).blockedKeyword(for: comic))
    }

    func testFavoritesSearchStillMatchesTranslatedTags() async throws {
        let comic = item(platform: .eHentai, tags: ["parody:granblue fantasy"])
        let matches = try await ComicListBackgroundProcessing.filteredFavorites(from: [comic], keyword: "碧蓝")
        XCTAssertEqual(matches, [comic])
    }

    func testOfflineTagReferencesKeepDisplayTitleAndOriginalQuery() {
        let comic = item(platform: .eHentai, tags: ["female:big breasts"])
        let tags = ComicListTagResolver(nhentaiCache: [:]).tagReferences(for: comic)
        XCTAssertEqual(tags.first?.title, "巨乳")
        XCTAssertEqual(tags.first?.query, "female:big breasts")
    }

    private func assertBlocked(_ comic: ComicListItem, keywords: [String], file: StaticString = #filePath, line: UInt = #line) {
        for keyword in keywords {
            XCTAssertEqual(BlockingKeywordMatcher(keywords: [keyword]).blockedKeyword(for: comic), keyword, file: file, line: line)
        }
    }

    private func item(platform: ComicPlatform, tags: [String]) -> ComicListItem {
        ComicListItem(
            id: "sample",
            platform: platform,
            title: "Sample comic",
            subtitle: "Author",
            coverURLString: "",
            tags: tags,
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }
}

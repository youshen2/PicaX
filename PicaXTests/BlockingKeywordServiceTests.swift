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
}

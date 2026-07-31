import Foundation
import XCTest
@testable import PicaX

final class MarkdownImageTagContentTests: XCTestCase {
    func testParsesImageFollowedByTagTitle() {
        let content = MarkdownImageTagContent(
            "![](http://example.com/tag.png) 碧蓝幻想"
        )

        XCTAssertEqual(
            content.segments,
            [
                .image("http://example.com/tag.png"),
                .text("碧蓝幻想")
            ]
        )
        XCTAssertEqual(content.plainText, "碧蓝幻想")
        XCTAssertEqual(content.accessibilityLabel, "碧蓝幻想")
    }

    func testParsesCurrentGranblueFantasyTranslation() {
        let imageURL = "https://media.9game.cn/gamebase/ieu-eagle-docking-service/images/20220726/13/29/df5999e63d6a13b0fe2bfc5595c3c846.png?x-oss-process=image/resize,w_120,m_lfit"
        let content = MarkdownImageTagContent("![](\(imageURL)) 碧蓝幻想")

        XCTAssertEqual(content.segments, [.image(imageURL), .text("碧蓝幻想")])
        XCTAssertEqual(content.plainText, "碧蓝幻想")
    }

    func testPreservesSegmentOrderAroundImage() {
        let content = MarkdownImageTagContent(
            "前缀 ![图标](https://example.com/tag.png) 后缀"
        )

        XCTAssertEqual(
            content.segments,
            [
                .text("前缀"),
                .image("https://example.com/tag.png"),
                .text("后缀")
            ]
        )
        XCTAssertEqual(content.plainText, "前缀 后缀")
    }

    func testSupportsBalancedParenthesesInImageURL() {
        let content = MarkdownImageTagContent(
            "![](https://example.com/icon_(small).png?crop=(center)) 标签"
        )

        XCTAssertEqual(
            content.segments.first,
            .image("https://example.com/icon_(small).png?crop=(center)")
        )
        XCTAssertEqual(content.plainText, "标签")
    }

    func testResolvesProtocolRelativeImageURL() {
        let content = MarkdownImageTagContent("![](//example.com/tag.png) 标签")

        XCTAssertEqual(
            content.segments.first?.imageURL?.absoluteString,
            "https://example.com/tag.png"
        )
    }

    func testRejectsRelativeImageDestination() {
        let content = MarkdownImageTagContent("![图标](#) 标签")

        XCTAssertNil(content.segments.first?.imageURL)
        XCTAssertEqual(content.plainText, "标签")
    }

    func testPreservesPlainTagVerbatim() {
        let source = "  普通 **标签**  "
        let content = MarkdownImageTagContent(source)

        XCTAssertEqual(content.segments, [.text("普通 **标签**")])
        XCTAssertEqual(content.plainText, "普通 **标签**")
    }

    func testTagReferenceUsesTextAsDisplayTitle() {
        let tag = ComicTagReference(
            title: "![](https://example.com/tag.png) 碧蓝幻想",
            query: "碧蓝幻想",
            platform: .picacg,
            urlString: nil
        )

        XCTAssertEqual(tag.displayTitle, "碧蓝幻想")
    }
}

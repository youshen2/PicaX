import XCTest
@testable import PicaX

final class SettingsRouteTests: XCTestCase {
    func testRoutesHaveUniqueIdentifiers() {
        XCTAssertEqual(
            Set(SettingsRoute.allCases.map(\.id)).count,
            SettingsRoute.allCases.count
        )
    }

    func testKeywordSearchFindsDirectDestination() {
        let matches = SettingsRoute.allCases.filter { $0.matches("自动翻页") }

        XCTAssertEqual(matches, [.reader])
    }

    func testSearchSupportsMultipleTerms() {
        let matches = SettingsRoute.allCases.filter { $0.matches("搜索 历史") }

        XCTAssertEqual(matches, [.search])
    }

    func testEmptySearchKeepsEveryDirectDestination() {
        let matches = SettingsRoute.allCases.filter { $0.matches("   ") }

        XCTAssertEqual(matches, SettingsRoute.allCases)
    }
}

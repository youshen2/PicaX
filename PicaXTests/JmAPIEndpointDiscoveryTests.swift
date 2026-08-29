import XCTest
@testable import PicaX

@MainActor
final class JmAPIEndpointDiscoveryTests: XCTestCase {
    func testDomainPayloadKeepsEveryValidServerInOrder() throws {
        let payload = #"""
        {
            "Server": [
                "www.cdnhjk.net",
                "https://www.cdngwc.cc/",
                "www.cdngwc.net",
                "www.cdngwc.club",
                "www.cdnutc.me",
                "www.cdnhjk.net",
                ""
            ]
        }
        """#

        XCTAssertEqual(
            try ComicContentService.jmAPIBaseURLs(fromDomainPayload: payload),
            [
                "https://www.cdnhjk.net",
                "https://www.cdngwc.cc",
                "https://www.cdngwc.net",
                "https://www.cdngwc.club",
                "https://www.cdnutc.me"
            ]
        )
    }

    func testFallbackServersMatchLatestAPKConfiguration() {
        XCTAssertEqual(
            JmAPIEndpoint.fallbackBaseURLs,
            [
                "https://www.cdnhjk.net",
                "https://www.cdngwc.cc",
                "https://www.cdngwc.net",
                "https://www.cdngwc.club",
                "https://www.cdnutc.me"
            ]
        )
    }
}

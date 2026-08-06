import XCTest
@testable import PicaX

@MainActor
final class PicacgAuthenticationTests: XCTestCase {
    func testAuthenticatedRequestConvertsHTTP401ToExpiredLoginError() {
        let error = ComicContentService.picacgRequestError(
            ComicContentError.server("HTTP 401"),
            token: "stored-token"
        )

        XCTAssertEqual(error.localizedDescription, "PicACG 登录已过期，请重新登录。")
    }

    func testLoginRequestKeepsHTTP401WhenItHasNoToken() {
        let error = ComicContentService.picacgRequestError(
            ComicContentError.server("HTTP 401"),
            token: ""
        )

        XCTAssertEqual(error.localizedDescription, "HTTP 401")
    }

    func testPicacgDoesNotOfferWebLogin() {
        XCTAssertNil(ComicPlatform.picacg.loginWebsite)
        XCTAssertNotNil(ComicPlatform.nhentai.loginWebsite)
    }
}

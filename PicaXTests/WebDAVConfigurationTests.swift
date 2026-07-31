import XCTest
@testable import PicaX

final class WebDAVConfigurationTests: XCTestCase {
    func testRejectsNonHTTPSURL() {
        XCTAssertThrowsError(
            try WebDAVConfiguration(
                serverURL: "http://example.com/dav",
                username: "reader",
                password: "secret",
                remoteDirectory: "PicaX"
            )
        ) { error in
            guard case WebDAVError.invalidServerURL = error else {
                return XCTFail("Expected invalidServerURL, got \(error)")
            }
        }
    }

    func testRemovesEmbeddedCredentialsQueryAndFragment() throws {
        let configuration = try WebDAVConfiguration(
            serverURL: "https://embedded:secret@example.com/dav?token=value#fragment",
            username: " reader ",
            password: "secret",
            remoteDirectory: "/PicaX/../Backups/./"
        )

        let components = try XCTUnwrap(URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false))
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(configuration.username, "reader")
        XCTAssertEqual(configuration.remoteDirectory, "PicaX/Backups")
    }
}

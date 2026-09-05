import Foundation

nonisolated enum AppProxyConnectionTester {
    static func test(
        route: AppNetworkRoute,
        targetURL: URL
    ) async throws -> Int {
        guard case .proxy = route else {
            throw AppProxyError.configurationMissing
        }
        var request = URLRequest(
            url: targetURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "HEAD"
        let session = AppNetworkSessionFactory.shared.session(
            for: route,
            purpose: .probe
        )
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AppProxyError.invalidHTTPResponse(
                "服务器未返回 HTTP 响应"
            )
        }
        return response.statusCode
    }
}

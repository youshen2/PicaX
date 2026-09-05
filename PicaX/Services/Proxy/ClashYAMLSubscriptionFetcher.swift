import Foundation

nonisolated enum ClashYAMLSubscriptionFetcher {
    static func fetch(
        urlText: String,
        route: AppNetworkRoute
    ) async throws -> ClashYAMLProxyParser.ParseResult {
        let url = try validatedURL(urlText)
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "GET"
        request.setValue(
            "application/yaml, text/yaml, text/plain, "
                + "application/octet-stream;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let session = AppNetworkSessionFactory.shared.session(
            for: route,
            purpose: .subscription
        )
        let redirectDelegate = HTTPSOnlyRedirectDelegate()
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: redirectDelegate
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        if redirectDelegate.rejectedInsecureRedirect {
            throw FetchError.insecureRedirect
        }
        guard httpResponse.url?.scheme?.lowercased() == "https" else {
            throw FetchError.insecureRedirect
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FetchError.httpStatus(httpResponse.statusCode)
        }
        let expectedLength = httpResponse.expectedContentLength
        if expectedLength > ClashYAMLImportWorker.maximumDocumentSize {
            throw ClashYAMLProxyParser.ParseError.tooLarge
        }

        let data = try await collect(
            bytes,
            maximumSize: ClashYAMLImportWorker.maximumDocumentSize,
            expectedLength: expectedLength
        )
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw FetchError.notUTF8
        }
        return try await ClashYAMLImportWorker.parse(text: yaml)
    }

    private static func validatedURL(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty,
              value.utf8.count <= maximumURLSize,
              var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            throw FetchError.invalidURL
        }
        components.fragment = nil
        guard let url = components.url else {
            throw FetchError.invalidURL
        }
        return url
    }

    private static func collect(
        _ bytes: URLSession.AsyncBytes,
        maximumSize: Int,
        expectedLength: Int64
    ) async throws -> Data {
        var result = Data()
        if expectedLength > 0 {
            result.reserveCapacity(
                min(Int(expectedLength), maximumSize)
            )
        }
        var buffer = [UInt8]()
        buffer.reserveCapacity(bufferSize)

        for try await byte in bytes {
            guard result.count + buffer.count < maximumSize else {
                throw ClashYAMLProxyParser.ParseError.tooLarge
            }
            buffer.append(byte)
            if buffer.count == bufferSize {
                result.append(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        result.append(contentsOf: buffer)
        return result
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case insecureRedirect
        case invalidResponse
        case httpStatus(Int)
        case notUTF8

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "请输入有效的 HTTPS 订阅链接。"
            case .insecureRedirect:
                return "订阅服务器尝试重定向到非 HTTPS 地址，已拒绝下载。"
            case .invalidResponse:
                return "订阅服务器没有返回有效的 HTTP 响应。"
            case .httpStatus(let statusCode):
                return "订阅服务器返回 HTTP \(statusCode)。"
            case .notUTF8:
                return "订阅内容不是 UTF-8 YAML 文本。"
            }
        }
    }

    private static let maximumURLSize = 16 * 1_024
    private static let bufferSize = 32 * 1_024
}

private nonisolated final class HTTPSOnlyRedirectDelegate:
    NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var rejectedInsecureRedirect = false

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            rejectedInsecureRedirect = true
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

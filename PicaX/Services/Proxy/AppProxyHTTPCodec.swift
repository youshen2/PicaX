import Foundation

nonisolated struct AppProxyHTTPResponse {
    let statusCode: Int
    let version: String
    let headers: [String: String]
    let body: Data
}

nonisolated enum AppProxyHTTPCodec {
    static func encodedRequest(
        _ request: URLRequest,
        preservedBody: Data?,
        internalHeaderName: String
    ) throws -> Data {
        guard let url = request.url,
              let host = url.host,
              let scheme = url.scheme?.lowercased() else {
            throw AppProxyError.invalidHTTPResponse("请求地址缺少主机名")
        }
        if request.httpBodyStream != nil, preservedBody == nil {
            throw AppProxyError.unsupportedRequestBody
        }
        let method = (request.httpMethod ?? "GET").uppercased()
        guard isValidToken(method) else {
            throw AppProxyError.invalidHTTPResponse("HTTP 方法无效")
        }
        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        let path = components?.percentEncodedPath.isEmpty == false
            ? components?.percentEncodedPath ?? "/"
            : "/"
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        components = nil

        let port = url.port ?? (scheme == "http" ? 80 : 443)
        let isDefaultPort =
            (scheme == "http" && port == 80)
            || (scheme == "https" && port == 443)
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        let hostHeader = isDefaultPort
            ? formattedHost
            : "\(formattedHost):\(port)"

        let blockedHeaders = Set([
            "host",
            "content-length",
            "connection",
            "proxy-connection",
            "proxy-authorization",
            "transfer-encoding",
            "accept-encoding",
            "expect",
            internalHeaderName.lowercased()
        ])
        var headerLines = [String]()
        for (name, value) in (
            request.allHTTPHeaderFields ?? [:]
        ).sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            guard !blockedHeaders.contains(name.lowercased()) else {
                continue
            }
            guard isValidHeader(name: name, value: value) else {
                throw AppProxyError.invalidHTTPResponse("HTTP 请求头无效")
            }
            headerLines.append("\(name): \(value)")
        }
        headerLines.append("Host: \(hostHeader)")
        headerLines.append("Connection: close")
        headerLines.append("Accept-Encoding: identity")
        if let preservedBody {
            headerLines.append("Content-Length: \(preservedBody.count)")
        }

        var result = Data(
            (
                "\(method) \(path)\(query) HTTP/1.1\r\n"
                    + headerLines.joined(separator: "\r\n")
                    + "\r\n\r\n"
            ).utf8
        )
        if let preservedBody {
            result.append(preservedBody)
        }
        return result
    }

    static func readResponse(
        from channel: AppProxyHTTPChannel,
        requestMethod: String
    ) throws -> AppProxyHTTPResponse {
        let reader = AppProxyHTTPChannelReader(channel: channel)
        let headerData = try reader.readThrough(
            Data("\r\n\r\n".utf8),
            maximumLength: 64 * 1_024
        )
        guard let headerText = String(
            data: headerData,
            encoding: .isoLatin1
        ) else {
            throw AppProxyError.invalidHTTPResponse("响应头不是有效文本")
        }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw AppProxyError.invalidHTTPResponse("响应头为空")
        }
        let statusLine = lines.removeFirst()
        let statusParts = statusLine.split(
            separator: " ",
            maxSplits: 2,
            omittingEmptySubsequences: true
        )
        guard statusParts.count >= 2,
              statusParts[0].hasPrefix("HTTP/"),
              let statusCode = Int(statusParts[1]),
              (100...599).contains(statusCode) else {
            throw AppProxyError.invalidHTTPResponse("状态行无效")
        }

        var headers = [String: String]()
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                throw AppProxyError.invalidHTTPResponse("响应头字段无效")
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard isValidHeader(name: name, value: value) else {
                throw AppProxyError.invalidHTTPResponse("响应头字段无效")
            }
            if let existing = headers[name] {
                let separator = name == "set-cookie" ? "\n" : ", "
                headers[name] = existing + separator + value
            } else {
                headers[name] = value
            }
        }

        let method = requestMethod.uppercased()
        let hasNoBody = method == "HEAD"
            || (100...199).contains(statusCode)
            || statusCode == 204
            || statusCode == 304
        let body: Data
        if hasNoBody {
            body = Data()
        } else if headers["transfer-encoding"]?
            .lowercased()
            .contains("chunked") == true {
            body = try reader.readChunkedBody()
            headers["transfer-encoding"] = nil
            headers["content-length"] = String(body.count)
        } else if let contentLengthValue = headers["content-length"] {
            guard let contentLength = Int(contentLengthValue),
                  contentLength >= 0 else {
                throw AppProxyError.invalidHTTPResponse(
                    "Content-Length 无效"
                )
            }
            guard contentLength <= maximumBodyLength else {
                throw AppProxyError.responseTooLarge
            }
            body = try reader.readExactly(contentLength)
        } else {
            body = try reader.readToEnd(
                maximumLength: maximumBodyLength
            )
            headers["content-length"] = String(body.count)
        }
        headers["connection"] = nil
        headers["proxy-connection"] = nil

        return AppProxyHTTPResponse(
            statusCode: statusCode,
            version: String(statusParts[0]),
            headers: headers,
            body: body
        )
    }

    private static func isValidToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.unicodeScalars.allSatisfy {
                $0.value > 32 && $0.value < 127
                    && !"()<>@,;:\\\"/[]?={}"
                        .unicodeScalars
                        .contains($0)
            }
    }

    private static func isValidHeader(
        name: String,
        value: String
    ) -> Bool {
        isValidToken(name)
            && !value.contains("\r")
            && !value.contains("\n")
    }

    private static let maximumBodyLength = 128 * 1_024 * 1_024
}

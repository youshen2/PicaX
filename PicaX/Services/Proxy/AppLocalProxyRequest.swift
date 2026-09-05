import Foundation

nonisolated struct AppLocalProxyRequest {
    let destinationHost: String
    let destinationPort: UInt16
    let isConnect: Bool
    let forwardHeader: Data
    let proxyAuthorization: String?

    init(headerData: Data) throws {
        guard let headerText = String(
            data: headerData,
            encoding: .isoLatin1
        ) else {
            throw AppProxyError.invalidHTTPResponse(
                "本地代理请求头无效"
            )
        }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw AppProxyError.invalidHTTPResponse(
                "本地代理请求为空"
            )
        }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(
            separator: " ",
            maxSplits: 2,
            omittingEmptySubsequences: true
        )
        guard parts.count == 3 else {
            throw AppProxyError.invalidHTTPResponse(
                "本地代理请求行无效"
            )
        }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let version = String(parts[2])
        isConnect = method == "CONNECT"
        let headerFields = try Self.headers(from: lines)
        proxyAuthorization = headerFields["proxy-authorization"]

        if isConnect {
            let address = try Self.parseAuthority(target)
            destinationHost = address.host
            destinationPort = address.port
            forwardHeader = Data()
            return
        }

        let targetURL: URL?
        if let absoluteURL = URL(string: target),
           absoluteURL.scheme != nil {
            targetURL = absoluteURL
        } else {
            let hostValue = headerFields["host"]
            targetURL = hostValue.flatMap {
                URL(string: "http://\($0)\(target)")
            }
        }
        guard let targetURL,
              let host = targetURL.host else {
            throw AppProxyError.invalidHTTPResponse(
                "本地代理请求缺少目标主机"
            )
        }
        let scheme = targetURL.scheme?.lowercased() ?? "http"
        guard scheme == "http" else {
            throw AppProxyError.invalidHTTPResponse(
                "非 CONNECT 请求仅允许 HTTP 目标"
            )
        }
        let portValue = targetURL.port
            ?? 80
        guard let port = UInt16(exactly: portValue) else {
            throw AppProxyError.invalidPort
        }
        destinationHost = host
        destinationPort = port

        var components = URLComponents(
            url: targetURL,
            resolvingAgainstBaseURL: false
        )
        let path = components?.percentEncodedPath.isEmpty == false
            ? components?.percentEncodedPath ?? "/"
            : "/"
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        components = nil

        var outputLines = ["\(method) \(path)\(query) \(version)"]
        for line in lines where !line.isEmpty {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("proxy-authorization:")
                || lowercased.hasPrefix("proxy-connection:")
                || lowercased.hasPrefix("connection:") {
                continue
            }
            guard !line.contains("\r"), !line.contains("\n") else {
                throw AppProxyError.invalidHTTPResponse(
                    "本地代理请求头无效"
                )
            }
            outputLines.append(line)
        }
        outputLines.append("Connection: close")
        outputLines.append("")
        outputLines.append("")
        forwardHeader = Data(
            outputLines.joined(separator: "\r\n").utf8
        )
    }

    private static func headers(
        from lines: [String]
    ) throws -> [String: String] {
        var result = [String: String]()
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                throw AppProxyError.invalidHTTPResponse(
                    "本地代理请求头无效"
                )
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            result[name] = value
        }
        return result
    }

    private static func parseAuthority(
        _ value: String
    ) throws -> (host: String, port: UInt16) {
        if value.hasPrefix("["),
           let closingBracket = value.firstIndex(of: "]") {
            let host = String(
                value[value.index(after: value.startIndex)..<closingBracket]
            )
            let portStart = value.index(after: closingBracket)
            guard portStart < value.endIndex,
                  value[portStart] == ":",
                  let port = UInt16(
                      value[value.index(after: portStart)...]
                  ) else {
                throw AppProxyError.invalidPort
            }
            return (host, port)
        }
        guard let separator = value.lastIndex(of: ":"),
              let port = UInt16(value[value.index(after: separator)...]) else {
            throw AppProxyError.invalidPort
        }
        let host = String(value[..<separator])
        guard !host.isEmpty else {
            throw AppProxyError.invalidHost
        }
        return (host, port)
    }
}

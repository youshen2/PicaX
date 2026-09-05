import Foundation
import Yams

nonisolated enum ClashYAMLProxyParser {
    struct ParseResult: Sendable {
        let candidates: [AppBuiltInProxyCandidate]
        let skippedMessages: [String]
    }

    enum ParseError: LocalizedError {
        case tooLarge
        case invalidDocument(String)
        case proxiesMissing
        case noSupportedNodes([String])

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "YAML 文件超过 5 MB，已拒绝处理。"
            case .invalidDocument(let reason):
                return "Clash YAML 解析失败：\(reason)"
            case .proxiesMissing:
                return "YAML 中没有找到有效的 proxies 节点列表。"
            case .noSupportedNodes(let skippedMessages):
                let details = skippedMessages
                    .prefix(5)
                    .joined(separator: "；")
                guard !details.isEmpty else {
                    return "YAML 中没有可导入的节点，请检查协议与传输方式。"
                }
                let suffix = skippedMessages.count > 5
                    ? "；其余原因已省略"
                    : ""
                return "YAML 中没有可导入的节点。跳过原因："
                    + "\(details)\(suffix)。"
            }
        }
    }

    static func parse(_ yaml: String) throws -> ParseResult {
        guard yaml.utf8.count <= maximumDocumentSize else {
            throw ParseError.tooLarge
        }

        let document: Node?
        do {
            document = try Yams.compose(yaml: yaml)
        } catch {
            throw ParseError.invalidDocument(error.localizedDescription)
        }
        guard let document,
              document.mapping != nil,
              let proxySequence = document["proxies"]?.sequence else {
            throw ParseError.proxiesMissing
        }
        let rawNodes = Array(proxySequence)

        var candidates = [AppBuiltInProxyCandidate]()
        var skipped = [String]()
        var seenIdentities = Set<String>()

        for (index, rawNode) in rawNodes.prefix(maximumNodeCount).enumerated() {
            guard rawNode.mapping != nil else {
                skipped.append("第 \(index + 1) 个节点不是键值对象")
                continue
            }
            do {
                let candidate = try candidate(from: rawNode)
                if seenIdentities.insert(candidate.identity).inserted {
                    candidates.append(candidate)
                } else {
                    skipped.append("“\(candidate.name)”在文件中重复")
                }
            } catch {
                let name = optionalString("name", in: rawNode)
                    ?? "第 \(index + 1) 个节点"
                skipped.append("“\(name)”：\(error.localizedDescription)")
            }
        }
        if rawNodes.count > maximumNodeCount {
            skipped.append(
                "节点数量超过 \(maximumNodeCount)，其余节点未处理"
            )
        }
        return ParseResult(
            candidates: candidates,
            skippedMessages: skipped
        )
    }

    private static func candidate(
        from node: Node
    ) throws -> AppBuiltInProxyCandidate {
        let name = try requiredString("name", in: node)
        let type = try requiredString("type", in: node).lowercased()
        let server = try AppProxyConfigurationParser.normalizedHost(
            requiredString("server", in: node)
        )
        guard let rawPort = intValue(node["port"]),
              let port = UInt16(exactly: rawPort),
              port > 0 else {
            throw NodeError("端口无效")
        }
        try requireTCPTransport(node)

        let username = optionalSecret("username", in: node)
        let password = optionalSecret("password", in: node)
        let skipCertificateVerification = boolValue(
            node["skip-cert-verify"]
        ) ?? false

        switch type {
        case "http":
            guard !isEnabled(node["tls"]) else {
                throw NodeError("暂不支持启用 TLS 的 HTTP 代理节点")
            }
            try requirePairedCredentials(
                username: username,
                password: password
            )
            return makeCandidate(
                name: name,
                kind: .http,
                server: server,
                port: port,
                username: username,
                password: password
            )
        case "socks", "socks5":
            try requirePairedCredentials(
                username: username,
                password: password
            )
            return makeCandidate(
                name: name,
                kind: .socks5,
                server: server,
                port: port,
                username: username,
                password: password
            )
        case "ss", "shadowsocks":
            if let plugin = optionalString("plugin", in: node),
               !plugin.isEmpty {
                throw NodeError("暂不支持 Shadowsocks 插件 \(plugin)")
            }
            let cipher = try requiredString("cipher", in: node)
                .lowercased()
            guard AppShadowsocksCipher.named(cipher) != nil else {
                throw AppProxyError.unsupportedCipher(cipher)
            }
            let secret = AppBuiltInProxySecret(
                username: nil,
                password: try requiredSecret("password", in: node),
                uuid: nil,
                alterID: nil,
                cipher: cipher,
                sni: nil
            )
            return AppBuiltInProxyCandidate(
                name: name,
                kind: .shadowsocks,
                server: server,
                port: port,
                secret: secret,
                skipCertificateVerification: false
            )
        case "vmess":
            guard !isEnabled(node["tls"]) else {
                throw NodeError("当前 VMess 仅支持 TCP，不支持 TLS 传输")
            }
            let rawUUID = try requiredString("uuid", in: node)
            guard let uuid = UUID(uuidString: rawUUID) else {
                throw AppProxyError.invalidUUID
            }
            let alterID = intValue(node["alterId"])
                ?? intValue(node["alter-id"])
                ?? 0
            guard alterID == 0 else {
                throw NodeError("当前仅支持 alterId=0 的 VMess AEAD")
            }
            let secret = AppBuiltInProxySecret(
                username: nil,
                password: nil,
                uuid: uuid.uuidString,
                alterID: alterID,
                cipher: optionalString("cipher", in: node),
                sni: optionalString("servername", in: node)
                    ?? optionalString("sni", in: node)
            )
            return AppBuiltInProxyCandidate(
                name: name,
                kind: .vmess,
                server: server,
                port: port,
                secret: secret,
                skipCertificateVerification: false
            )
        case "trojan":
            let secret = AppBuiltInProxySecret(
                username: nil,
                password: try requiredSecret("password", in: node),
                uuid: nil,
                alterID: nil,
                cipher: nil,
                sni: optionalString("sni", in: node)
                    ?? optionalString("servername", in: node)
            )
            return AppBuiltInProxyCandidate(
                name: name,
                kind: .trojan,
                server: server,
                port: port,
                secret: secret,
                skipCertificateVerification:
                    skipCertificateVerification
            )
        default:
            throw AppProxyError.unsupportedBuiltInProtocol(type)
        }
    }

    private static func makeCandidate(
        name: String,
        kind: AppBuiltInProxyKind,
        server: String,
        port: UInt16,
        username: String?,
        password: String?
    ) -> AppBuiltInProxyCandidate {
        AppBuiltInProxyCandidate(
            name: name,
            kind: kind,
            server: server,
            port: port,
            secret: AppBuiltInProxySecret(
                username: username,
                password: password,
                uuid: nil,
                alterID: nil,
                cipher: nil,
                sni: nil
            ),
            skipCertificateVerification: false
        )
    }

    private static func requireTCPTransport(
        _ node: Node
    ) throws {
        let network = (
            optionalString("network", in: node)
                ?? optionalString("transport", in: node)
                ?? "tcp"
        ).lowercased()
        guard network == "tcp" else {
            throw AppProxyError.unsupportedBuiltInProtocol(network)
        }
    }

    private static func requirePairedCredentials(
        username: String?,
        password: String?
    ) throws {
        let hasUsername = !(username ?? "").isEmpty
        let hasPassword = !(password ?? "").isEmpty
        guard hasUsername == hasPassword else {
            throw AppProxyError.incompleteCredentials
        }
    }

    private static func requiredString(
        _ key: String,
        in node: Node
    ) throws -> String {
        guard let value = optionalString(key, in: node) else {
            throw NodeError("缺少 \(key)")
        }
        return value
    }

    private static func optionalString(
        _ key: String,
        in node: Node
    ) -> String? {
        guard let value = node[key]?.scalar?.string
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Credentials are opaque protocol data. Do not trim or coerce their YAML
    /// scalar spelling: both leading zeroes and quoted whitespace can be part
    /// of a valid username or password.
    private static func optionalSecret(
        _ key: String,
        in node: Node
    ) -> String? {
        guard let value = node[key]?.scalar?.string,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func requiredSecret(
        _ key: String,
        in node: Node
    ) throws -> String {
        guard let value = optionalSecret(key, in: node) else {
            throw NodeError("缺少 \(key)")
        }
        return value
    }

    private static func intValue(_ value: Node?) -> Int? {
        guard let rawValue = value?.scalar?.string else { return nil }
        return Int(
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func boolValue(_ value: Node?) -> Bool? {
        guard let rawValue = value?.scalar?.string else { return nil }
        switch rawValue.lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            return nil
        }
    }

    private static func isEnabled(_ value: Node?) -> Bool {
        boolValue(value) ?? false
    }

    private struct NodeError: LocalizedError {
        let reason: String

        init(_ reason: String) {
            self.reason = reason
        }

        var errorDescription: String? { reason }
    }

    private static let maximumDocumentSize = 5 * 1_024 * 1_024
    private static let maximumNodeCount = 1_000
}

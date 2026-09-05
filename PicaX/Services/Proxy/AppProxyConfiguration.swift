import Foundation
import Security

nonisolated enum AppProxyProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case https
    case socks5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .http:
            return "HTTP"
        case .https:
            return "HTTPS"
        case .socks5:
            return "SOCKS5"
        }
    }

    var defaultPort: Int {
        switch self {
        case .http:
            return 8080
        case .https:
            return 443
        case .socks5:
            return 1080
        }
    }
}

nonisolated struct AppProxyConfiguration: Codable, Hashable, Sendable {
    let type: AppProxyProtocol
    let host: String
    let port: UInt16
    let requiresAuthentication: Bool

    var displayAddress: String {
        "\(host):\(port)"
    }
}

nonisolated struct AppProxyCredentials: Codable, Hashable, Sendable {
    let username: String
    let password: String

    static let empty = AppProxyCredentials(username: "", password: "")

    var isEmpty: Bool {
        username.isEmpty && password.isEmpty
    }

    var isComplete: Bool {
        !username.isEmpty && !password.isEmpty
    }
}

nonisolated enum AppProxyRoute: Hashable, Sendable {
    case proxyServer(
        configuration: AppProxyConfiguration,
        credentials: AppProxyCredentials,
        revision: Int
    )
    case builtIn(
        profile: AppBuiltInProxyProfile,
        secret: AppBuiltInProxySecret,
        revision: Int
    )

    var cacheIdentity: String {
        switch self {
        case .proxyServer(let configuration, _, let revision):
            return [
                "server",
                String(revision),
                configuration.type.rawValue,
                configuration.host,
                String(configuration.port)
            ].joined(separator: "|")
        case .builtIn(let profile, _, let revision):
            return [
                "built-in",
                String(revision),
                profile.id.uuidString,
                profile.kind.rawValue,
                profile.server,
                String(profile.port)
            ].joined(separator: "|")
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .proxyServer(let configuration, _, _):
            return "\(configuration.type.displayName) 代理服务器“"
                + "\(configuration.displayAddress)”"
        case .builtIn(let profile, _, _):
            return "\(profile.kind.displayName) 节点“\(profile.name)”"
        }
    }
}

nonisolated enum AppNetworkRoute: Hashable, Sendable {
    case direct
    case proxy(AppProxyRoute)

    var cacheIdentity: String {
        switch self {
        case .direct:
            return "direct"
        case .proxy(let route):
            return "proxy|\(route.cacheIdentity)"
        }
    }
}

nonisolated enum AppProxyError: LocalizedError {
    case configurationMissing
    case builtInProfileMissing
    case builtInSecretUnavailable
    case invalidHost
    case invalidPort
    case incompleteCredentials
    case credentialsUnavailable
    case unsupportedBuiltInProtocol(String)
    case unsupportedCipher(String)
    case invalidUUID
    case secureRandomFailed(OSStatus)
    case unsupportedRequestBody
    case connectionTimedOut
    case connectionFailed(String)
    case connectionClosed
    case tunnelClosedBeforeTLS(String)
    case proxyRejected(String)
    case invalidProxyResponse
    case socksAuthenticationRejected
    case socksConnectionRejected(UInt8)
    case tlsHandshakeFailed(String)
    case tlsIOFailed(String)
    case invalidHTTPResponse(String)
    case responseTooLarge
    case localBridgeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "已选择代理服务器，但配置缺失；为避免直连，请重新保存配置。"
        case .builtInProfileMissing:
            return "已选择内置代理，但没有可用节点；为避免直连，请重新选择节点。"
        case .builtInSecretUnavailable:
            return "内置代理节点的密钥无法从钥匙串读取；为避免直连，连接已中断。"
        case .invalidHost:
            return "请输入有效的代理服务器主机名或 IP 地址。"
        case .invalidPort:
            return "代理端口必须在 1 到 65535 之间。"
        case .incompleteCredentials:
            return "用户名和密码需要同时填写，或同时留空。"
        case .credentialsUnavailable:
            return "代理凭据无法从钥匙串读取；为避免直连，连接已中断。"
        case .unsupportedBuiltInProtocol(let value):
            return "暂不支持此内置代理协议或传输方式：\(value)。"
        case .unsupportedCipher(let value):
            return "暂不支持 Shadowsocks 加密方式：\(value)。"
        case .invalidUUID:
            return "VMess 节点 UUID 无效。"
        case .secureRandomFailed(let status):
            return "生成代理会话随机数失败（OSStatus \(status)）。"
        case .unsupportedRequestBody:
            return "此请求使用了暂不支持的流式请求体，已阻止直连。"
        case .connectionTimedOut:
            return "连接代理服务器超时。"
        case .connectionFailed(let reason):
            return "代理连接失败：\(reason)"
        case .connectionClosed:
            return "代理连接已关闭。"
        case .tunnelClosedBeforeTLS(let proxy):
            return "\(proxy)在目标 TLS 握手前关闭了隧道；"
                + "通常是节点凭据、加密方式或 YAML 传输参数不匹配，"
                + "也可能是代理服务器拒绝了该目标。"
        case .proxyRejected(let reason):
            return "代理服务器拒绝了连接：\(reason)"
        case .invalidProxyResponse:
            return "代理服务器返回了无法识别的握手响应。"
        case .socksAuthenticationRejected:
            return "SOCKS5 用户名或密码不正确。"
        case .socksConnectionRejected(let code):
            return "SOCKS5 服务器拒绝连接（代码 \(code)）。"
        case .tlsHandshakeFailed(let reason):
            return "代理隧道内 TLS 握手失败：\(reason)"
        case .tlsIOFailed(let reason):
            return "代理隧道内 TLS 读写失败：\(reason)"
        case .invalidHTTPResponse(let reason):
            return "代理响应解析失败：\(reason)"
        case .localBridgeUnavailable(let message):
            return "本地代理无法启动：\(message)"
        case .responseTooLarge:
            return "代理返回的数据超过安全大小限制。"

        }
    }
}

nonisolated struct AppProxyTransportError: LocalizedError, CustomNSError {
    static let errorDomain = "work.picax.app-proxy"

    let message: String

    init(_ error: Error) {
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.isEmpty {
            message = description
        } else {
            message = (error as NSError).localizedDescription
        }
    }

    var errorDescription: String? { message }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: message]
    }
}

nonisolated enum AppProxyConfigurationParser {
    static func validated(
        type: AppProxyProtocol,
        host rawHost: String,
        port rawPort: String,
        username rawUsername: String,
        password rawPassword: String
    ) throws -> (AppProxyConfiguration, AppProxyCredentials) {
        let host = try normalizedHost(rawHost)
        guard let portValue = Int(
            rawPort.trimmingCharacters(in: .whitespacesAndNewlines)
        ), (1...65_535).contains(portValue),
        let port = UInt16(exactly: portValue) else {
            throw AppProxyError.invalidPort
        }

        let username = rawUsername.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let password = rawPassword
        guard username.isEmpty == password.isEmpty else {
            throw AppProxyError.incompleteCredentials
        }

        let credentials = AppProxyCredentials(
            username: username,
            password: password
        )
        let configuration = AppProxyConfiguration(
            type: type,
            host: host,
            port: port,
            requiresAuthentication: !credentials.isEmpty
        )
        return (configuration, credentials)
    }

    static func parseShareLink(
        _ rawValue: String
    ) throws -> (AppProxyConfiguration, AppProxyCredentials) {
        let value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let type = shareLinkType(for: scheme),
              let host = components.host,
              !host.isEmpty else {
            throw AppProxyError.invalidHost
        }
        guard components.path.isEmpty || components.path == "/",
              components.query == nil else {
            throw AppProxyError.invalidHost
        }

        let username = components.user ?? ""
        let password = components.password ?? ""
        components.fragment = nil

        return try validated(
            type: type,
            host: host,
            port: String(components.port ?? type.defaultPort),
            username: username,
            password: password
        )
    }

    private static func shareLinkType(
        for scheme: String
    ) -> AppProxyProtocol? {
        switch scheme {
        case "http":
            return .http
        case "https":
            return .https
        case "socks", "socks5", "socks5h":
            return .socks5
        default:
            return nil
        }
    }

    static func normalizedHost(_ rawValue: String) throws -> String {
        var value = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if value.hasPrefix("["), value.hasSuffix("]") {
            value.removeFirst()
            value.removeLast()
        }
        let forbidden = CharacterSet(
            charactersIn: "/?#@"
        ).union(.controlCharacters)
        guard !value.isEmpty,
              !value.contains("://"),
              value.rangeOfCharacter(from: forbidden) == nil,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw AppProxyError.invalidHost
        }
        return value
    }
}

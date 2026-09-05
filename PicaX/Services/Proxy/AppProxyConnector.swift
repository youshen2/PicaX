import Foundation
import Network
import Security

nonisolated enum AppProxyConnector {
    static func openTunnel(
        route: AppProxyRoute,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        switch route {
        case .proxyServer(
            let configuration,
            let credentials,
            _
        ):
            return try await openServerTunnel(
                configuration: configuration,
                credentials: credentials,
                destinationHost: destinationHost,
                destinationPort: destinationPort
            )
        case .builtIn(let profile, let secret, _):
            switch profile.kind {
            case .http:
                return try await openServerTunnel(
                    configuration: AppProxyConfiguration(
                        type: .http,
                        host: profile.server,
                        port: profile.port,
                        requiresAuthentication:
                            !secret.serverCredentials.isEmpty
                    ),
                    credentials: secret.serverCredentials,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            case .socks5:
                return try await openServerTunnel(
                    configuration: AppProxyConfiguration(
                        type: .socks5,
                        host: profile.server,
                        port: profile.port,
                        requiresAuthentication:
                            !secret.serverCredentials.isEmpty
                    ),
                    credentials: secret.serverCredentials,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            case .shadowsocks:
                return try await AppShadowsocksClient.openTunnel(
                    profile: profile,
                    secret: secret,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            case .vmess:
                return try await AppVMessClient.openTunnel(
                    profile: profile,
                    secret: secret,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            case .trojan:
                return try await AppTrojanClient.openTunnel(
                    profile: profile,
                    secret: secret,
                    destinationHost: destinationHost,
                    destinationPort: destinationPort
                )
            }
        }
    }

    private static func openServerTunnel(
        configuration: AppProxyConfiguration,
        credentials: AppProxyCredentials,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        switch configuration.type {
        case .http, .https:
            return try await openHTTPConnectTunnel(
                configuration: configuration,
                credentials: credentials,
                destinationHost: destinationHost,
                destinationPort: destinationPort
            )
        case .socks5:
            return try await openSOCKS5Tunnel(
                configuration: configuration,
                credentials: credentials,
                destinationHost: destinationHost,
                destinationPort: destinationPort
            )
        }
    }

    private static func openHTTPConnectTunnel(
        configuration: AppProxyConfiguration,
        credentials: AppProxyCredentials,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        let connection = try makeConnection(for: configuration)
        let tunnel = NWConnectionAppProxyTunnel(connection: connection)
        do {
            try await connection.startForAppProxy()
            let authority = authority(
                host: destinationHost,
                port: destinationPort
            )
            var request = [
                "CONNECT \(authority) HTTP/1.1",
                "Host: \(authority)",
                "Proxy-Connection: keep-alive"
            ]
            if configuration.requiresAuthentication {
                let credentials = Data(
                    "\(credentials.username):\(credentials.password)"
                        .utf8
                ).base64EncodedString()
                request.append(
                    "Proxy-Authorization: Basic \(credentials)"
                )
            }
            request.append("")
            request.append("")
            try await tunnel.send(Data(request.joined(separator: "\r\n").utf8))

            let responseData = try await tunnel.readThrough(
                Data("\r\n\r\n".utf8),
                maximumLength: 32 * 1_024
            )
            guard let response = String(
                data: responseData,
                encoding: .isoLatin1
            ), let statusLine = response.components(
                separatedBy: "\r\n"
            ).first else {
                throw AppProxyError.invalidProxyResponse
            }
            let fields = statusLine.split(
                separator: " ",
                maxSplits: 2,
                omittingEmptySubsequences: true
            )
            guard fields.count >= 2,
                  let statusCode = Int(fields[1]) else {
                throw AppProxyError.invalidProxyResponse
            }
            guard (200...299).contains(statusCode) else {
                let reason = fields.count == 3
                    ? String(fields[2])
                    : "HTTP \(statusCode)"
                throw AppProxyError.proxyRejected(reason)
            }
            return tunnel
        } catch {
            tunnel.close()
            throw error
        }
    }

    private static func openSOCKS5Tunnel(
        configuration: AppProxyConfiguration,
        credentials: AppProxyCredentials,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        let connection = try makeConnection(for: configuration)
        let tunnel = NWConnectionAppProxyTunnel(connection: connection)
        do {
            try await connection.startForAppProxy()
            let useAuthentication =
                configuration.requiresAuthentication
            let methods: [UInt8] = useAuthentication
                ? [0x05, 0x02, 0x00, 0x02]
                : [0x05, 0x01, 0x00]
            try await tunnel.send(Data(methods))

            let selection = try await tunnel.readExactly(2)
            guard selection[selection.startIndex] == 0x05 else {
                throw AppProxyError.invalidProxyResponse
            }
            let selectedMethod = selection[selection.startIndex + 1]
            if selectedMethod == 0x02 {
                try await authenticateSOCKS5(
                    tunnel: tunnel,
                    credentials: credentials
                )
            } else if selectedMethod != 0x00 {
                throw AppProxyError.proxyRejected(
                    "SOCKS5 不支持当前认证方式"
                )
            }

            var connectRequest: [UInt8] = [0x05, 0x01, 0x00]
            connectRequest.append(
                contentsOf: try socksAddress(
                    host: destinationHost,
                    port: destinationPort
                )
            )
            try await tunnel.send(Data(connectRequest))

            let reply = try await tunnel.readExactly(4)
            guard reply[reply.startIndex] == 0x05 else {
                throw AppProxyError.invalidProxyResponse
            }
            let resultCode = reply[reply.startIndex + 1]
            guard resultCode == 0x00 else {
                throw AppProxyError.socksConnectionRejected(resultCode)
            }
            try await drainSOCKS5BoundAddress(
                tunnel: tunnel,
                type: reply[reply.startIndex + 3]
            )
            return tunnel
        } catch {
            tunnel.close()
            throw error
        }
    }

    private static func authenticateSOCKS5(
        tunnel: NWConnectionAppProxyTunnel,
        credentials: AppProxyCredentials
    ) async throws {
        let username = Array(credentials.username.utf8)
        let password = Array(credentials.password.utf8)
        guard (1...255).contains(username.count),
              (1...255).contains(password.count) else {
            throw AppProxyError.incompleteCredentials
        }
        var request: [UInt8] = [0x01, UInt8(username.count)]
        request.append(contentsOf: username)
        request.append(UInt8(password.count))
        request.append(contentsOf: password)
        try await tunnel.send(Data(request))
        let response = try await tunnel.readExactly(2)
        guard response[response.startIndex] == 0x01,
              response[response.startIndex + 1] == 0x00 else {
            throw AppProxyError.socksAuthenticationRejected
        }
    }

    private static func drainSOCKS5BoundAddress(
        tunnel: NWConnectionAppProxyTunnel,
        type: UInt8
    ) async throws {
        switch type {
        case 0x01:
            _ = try await tunnel.readExactly(6)
        case 0x03:
            let length = try await tunnel.readExactly(1)
            _ = try await tunnel.readExactly(
                Int(length[length.startIndex]) + 2
            )
        case 0x04:
            _ = try await tunnel.readExactly(18)
        default:
            throw AppProxyError.invalidProxyResponse
        }
    }

    private static func socksAddress(
        host: String,
        port: UInt16
    ) throws -> [UInt8] {
        var result = [UInt8]()
        if let address = IPv4Address(host) {
            result.append(0x01)
            result.append(contentsOf: address.rawValue)
        } else if let address = IPv6Address(host) {
            result.append(0x04)
            result.append(contentsOf: address.rawValue)
        } else {
            let bytes = Array(host.utf8)
            guard !bytes.isEmpty, bytes.count <= 255 else {
                throw AppProxyError.invalidHost
            }
            result.append(0x03)
            result.append(UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(UInt8(port >> 8))
        result.append(UInt8(port & 0xff))
        return result
    }

    private static func makeConnection(
        for configuration: AppProxyConfiguration
    ) throws -> NWConnection {
        guard let port = NWEndpoint.Port(
            rawValue: configuration.port
        ) else {
            throw AppProxyError.invalidPort
        }
        let endpointHost = NWEndpoint.Host(configuration.host)
        switch configuration.type {
        case .http, .socks5:
            return NWConnection(
                host: endpointHost,
                port: port,
                using: .tcp
            )
        case .https:
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(
                tlsOptions.securityProtocolOptions,
                configuration.host
            )
            let parameters = NWParameters(
                tls: tlsOptions,
                tcp: NWProtocolTCP.Options()
            )
            return NWConnection(
                host: endpointHost,
                port: port,
                using: parameters
            )
        }
    }

    private static func authority(host: String, port: UInt16) -> String {
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return "\(formattedHost):\(port)"
    }
}

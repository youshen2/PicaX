import Foundation
import Network
import Security

nonisolated enum AppTrojanClient {
    static func openTunnel(
        profile: AppBuiltInProxyProfile,
        secret: AppBuiltInProxySecret,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        guard let password = secret.password, !password.isEmpty else {
            throw AppProxyError.builtInSecretUnavailable
        }
        guard let port = NWEndpoint.Port(rawValue: profile.port) else {
            throw AppProxyError.invalidPort
        }

        let tls = NWProtocolTLS.Options()
        let securityOptions = tls.securityProtocolOptions
        sec_protocol_options_set_tls_server_name(
            securityOptions,
            secret.sni ?? profile.server
        )
        if profile.skipCertificateVerification {
            sec_protocol_options_set_verify_block(
                securityOptions,
                { _, _, completion in completion(true) },
                .global(qos: .userInitiated)
            )
        }
        let parameters = NWParameters(
            tls: tls,
            tcp: NWProtocolTCP.Options()
        )
        let connection = NWConnection(
            host: NWEndpoint.Host(profile.server),
            port: port,
            using: parameters
        )
        let tunnel = NWConnectionAppProxyTunnel(connection: connection)
        do {
            try await connection.startForAppProxy()
            var handshake = Data(
                AppProxyCrypto.sha224Hex(Data(password.utf8)).utf8
            )
            handshake.append(contentsOf: [0x0d, 0x0a, 0x01])
            handshake.append(
                try AppProxyAddressCodec.socks(
                    host: destinationHost,
                    port: destinationPort
                )
            )
            handshake.append(contentsOf: [0x0d, 0x0a])
            try await tunnel.send(handshake)
            return tunnel
        } catch {
            tunnel.close()
            throw error
        }
    }
}

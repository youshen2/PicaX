import Foundation
import Network

extension AppLocalProxyLease {
    @available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
    func networkConfiguration() throws -> Network.ProxyConfiguration {
        guard let components = URLComponents(url: proxyURL, resolvingAgainstBaseURL: false),
              let host = components.host,
              let portValue = components.port,
              let port = NWEndpoint.Port(rawValue: UInt16(portValue)),
              let username = components.user,
              let password = components.password else {
            throw AppProxyError.localBridgeUnavailable("本地监听地址无效")
        }
        var configuration = Network.ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .init(host), port: port))
        configuration.allowFailover = false
        configuration.applyCredential(username: username, password: password)
        return configuration
    }
}

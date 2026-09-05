import Foundation
import Network

nonisolated enum AppNetworkPurpose: Hashable {
    case api
    case image
    case probe
    case subscription
}

nonisolated final class AppProxyRouteRegistry: @unchecked Sendable {
    static let shared = AppProxyRouteRegistry()
    static let headerName = "X-PicaX-Proxy-Route"

    func register(_ route: AppProxyRoute) -> String {
        let token = UUID().uuidString
        lock.lock()
        entries[token] = route
        lock.unlock()
        return token
    }

    func route(for token: String) -> AppProxyRoute? {
        lock.lock()
        defer { lock.unlock() }
        return entries[token]
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private let lock = NSLock()
    private var entries = [String: AppProxyRoute]()
}

nonisolated final class AppNetworkSessionFactory: @unchecked Sendable {
    static let shared = AppNetworkSessionFactory()

    func session(
        for route: AppNetworkRoute,
        purpose: AppNetworkPurpose
    ) -> URLSession {
        let key = SessionKey(route: route, purpose: purpose)
        lock.lock()
        defer { lock.unlock() }
        if let session = sessions[key] {
            return session
        }

        let configuration = makeConfiguration(
            for: route,
            purpose: purpose
        )
        let session = URLSession(configuration: configuration)
        sessions[key] = session
        return session
    }

    func reset() {
        lock.lock()
        let existingSessions = Array(sessions.values)
        sessions.removeAll()
        AppProxyRouteRegistry.shared.removeAll()
        lock.unlock()
        existingSessions.forEach { $0.invalidateAndCancel() }
    }

    func retireSessions(for route: AppNetworkRoute) {
        lock.lock()
        let keys = sessions.keys.filter { $0.route == route }
        let retiredSessions = keys.compactMap {
            sessions.removeValue(forKey: $0)
        }
        lock.unlock()
        retiredSessions.forEach { $0.finishTasksAndInvalidate() }
    }

    private func makeConfiguration(
        for route: AppNetworkRoute,
        purpose: AppNetworkPurpose
    ) -> URLSessionConfiguration {
        let configuration: URLSessionConfiguration
        switch purpose {
        case .api:
            configuration = .default
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.httpMaximumConnectionsPerHost = 6
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
        case .image:
            configuration = .ephemeral
            configuration.requestCachePolicy =
                .reloadIgnoringLocalCacheData
            configuration.httpMaximumConnectionsPerHost = 6
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 60
            configuration.urlCache = nil
        case .probe, .subscription:
            configuration = .ephemeral
            configuration.requestCachePolicy =
                .reloadIgnoringLocalCacheData
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.urlCache = nil
        }
        if purpose == .subscription {
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
        }
        configuration.waitsForConnectivity = false

        guard case .proxy(let proxyRoute) = route else {
            return configuration
        }

        let token = AppProxyRouteRegistry.shared.register(proxyRoute)
        configuration.protocolClasses = [
            AppProxyURLProtocol.self
        ] + (configuration.protocolClasses ?? []).filter {
            $0 != AppProxyURLProtocol.self
        }
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers[AppProxyRouteRegistry.headerName] = token
        configuration.httpAdditionalHeaders = headers
        installDirectConnectionBlocker(on: configuration)
        return configuration
    }

    private func installDirectConnectionBlocker(
        on configuration: URLSessionConfiguration
    ) {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            var blocker = Network.ProxyConfiguration(
                socksv5Proxy: .hostPort(
                    host: "127.0.0.1",
                    port: .any
                )
            )
            blocker.allowFailover = false
            configuration.proxyConfigurations = [blocker]
        } else {
            configuration.connectionProxyDictionary = [
                "HTTPEnable": true,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": 1,
                "HTTPSEnable": true,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": 1,
                "SOCKSEnable": true,
                "SOCKSProxy": "127.0.0.1",
                "SOCKSPort": 1
            ]
        }
    }

    private struct SessionKey: Hashable {
        let route: AppNetworkRoute
        let purpose: AppNetworkPurpose
    }

    private let lock = NSLock()
    private var sessions = [SessionKey: URLSession]()
}

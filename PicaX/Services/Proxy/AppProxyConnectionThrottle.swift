import Foundation

/// Limits concurrent URLProtocol tunnels to the same configured proxy.
/// `acquire` is only called from AppProxyURLProtocol's dedicated worker
/// thread, so waiting here never blocks Swift's cooperative executor.
nonisolated final class AppProxyConnectionThrottle: @unchecked Sendable {
    static let shared = AppProxyConnectionThrottle()

    func acquire(route: AppProxyRoute) {
        semaphore(for: identity(of: route)).wait()
    }

    func release(route: AppProxyRoute) {
        semaphore(for: identity(of: route)).signal()
    }

    private func semaphore(
        for identity: Identity
    ) -> DispatchSemaphore {
        lock.lock()
        defer { lock.unlock() }
        if let existing = semaphores[identity] {
            return existing
        }
        let semaphore = DispatchSemaphore(
            value: Self.maximumConcurrentConnections
        )
        semaphores[identity] = semaphore
        return semaphore
    }

    private func identity(of route: AppProxyRoute) -> Identity {
        switch route {
        case .proxyServer(let configuration, _, _):
            return .proxyServer(
                type: configuration.type,
                host: configuration.host.lowercased(),
                port: configuration.port
            )
        case .builtIn(let profile, _, _):
            return .builtIn(profile.id)
        }
    }

    private enum Identity: Hashable {
        case proxyServer(
            type: AppProxyProtocol,
            host: String,
            port: UInt16
        )
        case builtIn(UUID)
    }

    private static let maximumConcurrentConnections = 2
    private let lock = NSLock()
    private var semaphores = [Identity: DispatchSemaphore]()
}

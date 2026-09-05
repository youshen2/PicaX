import Foundation

nonisolated final class AppProxyNetwork: @unchecked Sendable {
    static let shared = AppProxyNetwork()
    private let lock = NSLock()
    private var route: Result<AppNetworkRoute, Error>?

    func currentRoute() throws -> AppNetworkRoute {
        lock.lock()
        defer { lock.unlock() }
        if case .success(let route) = route { return route }
        // A locked keychain can become available again after the device unlocks.
        let loaded = try AppProxySettingsStorage.Snapshot().route()
        route = .success(loaded)
        return loaded
    }

    func updateRoute(_ route: Result<AppNetworkRoute, Error>, resetSessions: Bool) {
        lock.lock()
        let previousRoute = try? self.route?.get()
        self.route = route
        lock.unlock()
        if resetSessions {
            AppNetworkSessionFactory.shared.reset()
        } else if let previousRoute {
            AppNetworkSessionFactory.shared.retireSessions(for: previousRoute)
        }
    }

    func session(purpose: AppNetworkPurpose = .api) throws -> URLSession {
        AppNetworkSessionFactory.shared.session(for: try currentRoute(), purpose: purpose)
    }

    func data(for request: URLRequest, purpose: AppNetworkPurpose = .api) async throws -> (Data, URLResponse) {
        var attemptedProfiles = Set<UUID>()
        while true {
            try Task.checkCancellation()
            let route = try currentRoute()
            let session = AppNetworkSessionFactory.shared.session(for: route, purpose: purpose)
            let result = try await session.data(for: request)
            guard ["GET", "HEAD"].contains((request.httpMethod ?? "GET").uppercased()),
                  (result.1 as? HTTPURLResponse)?.statusCode == 403,
                  case .proxy(.builtIn(let profile, _, _)) = route else { return result }
            attemptedProfiles.insert(profile.id)
            let didChange = await AppProxySettings.shared.selectNextBuiltInProxyAfterForbidden(
                failedProfileID: profile.id, excluding: attemptedProfiles
            )
            guard didChange else { return result }
        }
    }
}

import Foundation

nonisolated enum AppProxySettingsStorage {
    enum Key {
        static let appProxyConfiguration = "settings.network.proxy.configuration"
        static let appProxyCredentials = "network.proxy.credentials"
        static let appNetworkRoutingMode = "settings.network.proxy.routingMode"
        static let appBuiltInProxyProfiles = "settings.network.proxy.profiles"
        static let selectedBuiltInProxyID = "settings.network.proxy.selectedID"
        static let automaticallySelectBuiltInProxy = "settings.network.proxy.automaticallySelect"
        static let connectionCheckURL = "settings.network.proxy.connectionCheckURL"
    }

    struct Snapshot {
        let mode: AppNetworkRoutingMode
        let configuration: AppProxyConfiguration?
        let profiles: [AppBuiltInProxyProfile]
        let selectedID: UUID?

        init(defaults: UserDefaults = .standard) {
            migrateLegacySettings(defaults: defaults)
            mode = defaults.string(forKey: Key.appNetworkRoutingMode)
                .flatMap(AppNetworkRoutingMode.init(rawValue:)) ?? .direct
            configuration = defaults.data(forKey: Key.appProxyConfiguration)
                .flatMap { try? JSONDecoder().decode(AppProxyConfiguration.self, from: $0) }
            profiles = AppBuiltInProxyProfileStore.decodeProfiles(defaults.data(forKey: Key.appBuiltInProxyProfiles))
            selectedID = defaults.string(forKey: Key.selectedBuiltInProxyID).flatMap(UUID.init(uuidString:))
        }

        func route() throws -> AppNetworkRoute {
            switch mode {
            case .direct:
                return .direct
            case .proxyServer:
                guard let configuration else { throw AppProxyError.configurationMissing }
                let credentials = try AppProxyCredentialStore.load(
                    AppProxyCredentials.self, for: Key.appProxyCredentials
                ) ?? .empty
                if configuration.requiresAuthentication, !credentials.isComplete {
                    throw AppProxyError.credentialsUnavailable
                }
                return .proxy(.proxyServer(configuration: configuration, credentials: credentials, revision: 0))
            case .builtInProxy:
                guard let profile = profiles.first(where: { $0.id == selectedID }) else {
                    throw AppProxyError.builtInProfileMissing
                }
                return .proxy(.builtIn(
                    profile: profile,
                    secret: try AppBuiltInProxyProfileStore.secret(for: profile),
                    revision: 0
                ))
            }
        }
    }

    private static func migrateLegacySettings(defaults: UserDefaults) {
        guard defaults.object(forKey: Key.appNetworkRoutingMode) == nil else { return }
        let host = (defaults.string(forKey: "settings.network.proxyHost") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedPort = defaults.object(forKey: "settings.network.proxyPort") as? Int ?? 7890
        if !host.isEmpty {
            let configuration = AppProxyConfiguration(
                type: .http,
                host: host,
                port: UInt16(min(max(storedPort, 1), 65535)),
                requiresAuthentication: false
            )
            defaults.set(try? JSONEncoder().encode(configuration), forKey: Key.appProxyConfiguration)
        }
        let mode: AppNetworkRoutingMode = defaults.bool(forKey: "settings.network.useProxy") ? .proxyServer : .direct
        defaults.set(mode.rawValue, forKey: Key.appNetworkRoutingMode)
        for key in ["settings.network.useProxy", "settings.network.proxyHost", "settings.network.proxyPort"] {
            defaults.removeObject(forKey: key)
        }
    }
}

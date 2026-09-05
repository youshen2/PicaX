import Foundation

extension AppProxySettings {
    func applyAppProxyConfiguration(
        type: AppProxyProtocol,
        host: String,
        port: String,
        username: String,
        password: String
    ) throws {
        let (configuration, credentials) =
            try AppProxyConfigurationParser.validated(
                type: type,
                host: host,
                port: port,
                username: username,
                password: password
            )
        try AppProxyCredentialStore.save(
            credentials, for: AppProxySettingsStorage.Key.appProxyCredentials
        )

        let wasUsingProxyServer =
            appNetworkRoutingMode == .proxyServer
        appProxyConfiguration = configuration
        defaults.set(
            try JSONEncoder().encode(configuration),
            forKey: AppProxySettingsStorage.Key.appProxyConfiguration
        )
        if wasUsingProxyServer {
            appProxyDidChange()
        } else {
            activateRoutingMode(.proxyServer)
        }
    }

    func disableAppProxy() {
        activateRoutingMode(.direct)
    }

    func setNetworkRoutingMode(
        _ mode: AppNetworkRoutingMode
    ) throws {
        switch mode {
        case .direct:
            break
        case .proxyServer:
            guard appProxyConfiguration != nil else {
                throw AppProxyError.configurationMissing
            }
        case .builtInProxy:
            guard let profile = selectedBuiltInProxyProfile else {
                throw AppProxyError.builtInProfileMissing
            }
            _ = try AppBuiltInProxyProfileStore.secret(for: profile)
        }
        activateRoutingMode(mode)
    }

    func appProxyCredentials() -> AppProxyCredentials {
        (try? AppProxyCredentialStore.load(
            AppProxyCredentials.self, for: AppProxySettingsStorage.Key.appProxyCredentials
        )) ?? .empty
    }

    func appNetworkRoute() throws -> AppNetworkRoute {
        switch appNetworkRoutingMode {
        case .direct:
            return .direct
        case .proxyServer:
            return try networkRouteForProxyServer()
        case .builtInProxy:
            guard let profile = selectedBuiltInProxyProfile else {
                throw AppProxyError.builtInProfileMissing
            }
            return .proxy(
                .builtIn(
                    profile: profile,
                    secret: try AppBuiltInProxyProfileStore.secret(
                        for: profile
                    ),
                    revision: appProxyRevision
                )
            )
        }
    }

    func networkRouteForProxyServer() throws -> AppNetworkRoute {
        guard let configuration = appProxyConfiguration else {
            throw AppProxyError.configurationMissing
        }
        let credentials = appProxyCredentials()
        if configuration.requiresAuthentication,
           !credentials.isComplete {
            throw AppProxyError.credentialsUnavailable
        }
        return .proxy(
            .proxyServer(
                configuration: configuration,
                credentials: credentials,
                revision: appProxyRevision
            )
        )
    }

    func networkRoute(
        forBuiltInProxyProfileID id: UUID
    ) throws -> AppNetworkRoute {
        guard let profile = appBuiltInProxyProfiles.first(where: {
            $0.id == id
        }) else {
            throw AppProxyError.builtInProfileMissing
        }
        return .proxy(
            .builtIn(
                profile: profile,
                secret: try AppBuiltInProxyProfileStore.secret(
                    for: profile
                ),
                revision: appProxyRevision
            )
        )
    }
}

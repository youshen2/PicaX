import Combine
import Foundation

@MainActor
final class AppProxySettings: ObservableObject {
    static let shared = AppProxySettings()

    @Published var appNetworkRoutingMode: AppNetworkRoutingMode
    @Published var appProxyConfiguration: AppProxyConfiguration?
    @Published var appBuiltInProxyProfiles: [AppBuiltInProxyProfile]
    @Published var selectedBuiltInProxyID: UUID?
    @Published var appProxyRevision = 0
    @Published var automaticallySelectBuiltInProxy: Bool {
        didSet { defaults.set(automaticallySelectBuiltInProxy, forKey: AppProxySettingsStorage.Key.automaticallySelectBuiltInProxy) }
    }
    @Published var connectionCheckURLText: String {
        didSet { defaults.set(connectionCheckURLText, forKey: AppProxySettingsStorage.Key.connectionCheckURL) }
    }

    let defaults: UserDefaults

    var appProxyEnabled: Bool { appNetworkRoutingMode != .direct }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = AppProxySettingsStorage.Snapshot(defaults: defaults)
        appNetworkRoutingMode = snapshot.mode
        appProxyConfiguration = snapshot.configuration
        appBuiltInProxyProfiles = snapshot.profiles
        selectedBuiltInProxyID = snapshot.selectedID
        automaticallySelectBuiltInProxy = defaults.object(forKey: AppProxySettingsStorage.Key.automaticallySelectBuiltInProxy) as? Bool ?? true
        connectionCheckURLText = defaults.string(forKey: AppProxySettingsStorage.Key.connectionCheckURL) ?? "https://www.apple.com/"
    }

    func connectionCheckURL() throws -> URL {
        guard let url = URL(string: connectionCheckURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else {
            throw AppProxyError.invalidHTTPResponse("请输入有效的 HTTPS 连通性检查地址。")
        }
        return url
    }

    func appProxyDidChange(resetSessions: Bool = true) {
        appProxyRevision &+= 1
        AppProxyNetwork.shared.updateRoute(Result { try appNetworkRoute() }, resetSessions: resetSessions)
    }

    func activateRoutingMode(_ mode: AppNetworkRoutingMode) {
        guard mode != appNetworkRoutingMode else { return }
        appNetworkRoutingMode = mode
        defaults.set(mode.rawValue, forKey: AppProxySettingsStorage.Key.appNetworkRoutingMode)
        appProxyDidChange()
    }

    func persistSelectedBuiltInProxyID() {
        defaults.set(selectedBuiltInProxyID?.uuidString, forKey: AppProxySettingsStorage.Key.selectedBuiltInProxyID)
    }
}

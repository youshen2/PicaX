import Foundation

enum AppNetworkSettings {
    private enum Key {
        nonisolated static let imageQuality = "settings.network.imageQuality"
        nonisolated static let retryCount = "settings.network.retryCount"
    }

    private nonisolated static var defaults: UserDefaults {
        .standard
    }

    nonisolated static var retryAttempts: Int {
        let retryCount = defaults.object(forKey: Key.retryCount) == nil ? 2 : defaults.integer(forKey: Key.retryCount)
        return min(max(retryCount, 0), 5) + 1
    }

    nonisolated static var picacgImageQuality: String {
        switch defaults.string(forKey: Key.imageQuality) ?? "均衡" {
        case "省流":
            return "low"
        case "高清":
            return "high"
        case "原图":
            return "original"
        default:
            return "middle"
        }
    }

    nonisolated static func makeSession() throws -> URLSession {
        try AppProxyNetwork.shared.session()
    }
}

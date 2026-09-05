import Foundation
import Network

nonisolated enum AppProxyLoopback {
    static func isPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            return false
        }
        switch host {
        case .ipv4(let address):
            return address.isLoopback
        case .ipv6(let address):
            return address.isLoopback
        case .name(let name, _):
            return name.caseInsensitiveCompare("localhost") == .orderedSame
        @unknown default:
            return false
        }
    }
}

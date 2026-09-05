import Foundation
import Network

nonisolated enum AppProxyAddressCodec {
    static func socks(
        host: String,
        port: UInt16
    ) throws -> Data {
        var data = Data()
        if let address = IPv4Address(host) {
            data.append(0x01)
            data.append(address.rawValue)
        } else if let address = IPv6Address(host) {
            data.append(0x04)
            data.append(address.rawValue)
        } else {
            let bytes = Data(host.utf8)
            guard !bytes.isEmpty, bytes.count <= 255 else {
                throw AppProxyError.invalidHost
            }
            data.append(0x03)
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        data.append(UInt8(port >> 8))
        data.append(UInt8(port & 0xff))
        return data
    }

    static func vmess(host: String) throws -> Data {
        var data = Data()
        if let address = IPv4Address(host) {
            data.append(0x01)
            data.append(address.rawValue)
        } else if let address = IPv6Address(host) {
            data.append(0x03)
            data.append(address.rawValue)
        } else {
            let bytes = Data(host.utf8)
            guard !bytes.isEmpty, bytes.count <= 255 else {
                throw AppProxyError.invalidHost
            }
            data.append(0x02)
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        return data
    }
}

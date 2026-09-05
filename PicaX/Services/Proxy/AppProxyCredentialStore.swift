import Foundation

nonisolated enum AppProxyCredentialStore {
    private static let service = "moye.PicaX.networkProxy"

    static func save<Value: Encodable>(_ value: Value, for key: String) throws {
        try SecureCodableStore.save(value, service: service, account: key)
    }

    static func load<Value: Decodable>(_ type: Value.Type, for key: String) throws -> Value? {
        try SecureCodableStore.load(type, service: service, account: key)
    }

    static func remove(_ key: String) {
        try? SecureCodableStore.delete(service: service, account: key)
    }
}

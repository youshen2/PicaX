import Foundation
import Security

enum SecureCodableStoreError: LocalizedError {
    case unexpectedData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "安全存储返回了无效数据"
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "安全存储错误（\(status)）"
        }
    }
}

enum SecureCodableStore {
    nonisolated static func save<Value: Encodable>(
        _ value: Value,
        service: String,
        account: String
    ) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(service: service, account: account)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecureCodableStoreError.keychain(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0] = $1 }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureCodableStoreError.keychain(addStatus)
        }
    }

    nonisolated static func load<Value: Decodable>(
        _ type: Value.Type,
        service: String,
        account: String
    ) throws -> Value? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureCodableStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw SecureCodableStoreError.unexpectedData
        }
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated static func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureCodableStoreError.keychain(status)
        }
    }

    private nonisolated static func baseQuery(
        service: String,
        account: String
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

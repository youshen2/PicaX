import CryptoSwift
import Foundation

enum WatchAESECBError: LocalizedError {
    case invalidKeyLength(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength(let length):
            "AES 密钥长度无效：\(length)"
        }
    }
}

struct WatchAESECBService {
    private let key: [UInt8]
    private let padding: Padding

    init(key: Data, usesPKCS7Padding: Bool = true) throws {
        guard [16, 24, 32].contains(key.count) else {
            throw WatchAESECBError.invalidKeyLength(key.count)
        }
        self.key = Array(key)
        self.padding = usesPKCS7Padding ? .pkcs7 : .noPadding
    }

    func decrypt(_ data: Data) throws -> Data {
        let aes = try AES(key: key, blockMode: ECB(), padding: padding)
        return Data(try aes.decrypt(Array(data)))
    }
}

import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum AppProxyCrypto {
    static func randomBytes(count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                count,
                buffer.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw AppProxyError.secureRandomFailed(status)
        }
        return data
    }

    static func sha224Hex(_ data: Data) -> String {
        var digest = [UInt8](
            repeating: 0,
            count: Int(CC_SHA224_DIGEST_LENGTH)
        )
        data.withUnsafeBytes { buffer in
            _ = CC_SHA224(
                buffer.baseAddress,
                CC_LONG(data.count),
                &digest
            )
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ UInt32.max
    }

    static func fnv1a32(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0x811c9dc5)) {
            ($0 ^ UInt32($1)) &* 0x01000193
        }
    }

    static func aes128ECBEncrypt(
        block: Data,
        key: Data
    ) throws -> Data {
        guard block.count == kCCBlockSizeAES128,
              key.count == kCCKeySizeAES128 else {
            throw AppProxyError.connectionFailed(
                "VMess AES-ECB 参数长度无效"
            )
        }
        var output = Data(count: kCCBlockSizeAES128)
        var bytesWritten = 0
        let outputLength = kCCBlockSizeAES128
        let status = output.withUnsafeMutableBytes { outputBuffer in
            block.withUnsafeBytes { blockBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        blockBuffer.baseAddress,
                        block.count,
                        outputBuffer.baseAddress,
                        outputLength,
                        &bytesWritten
                    )
                }
            }
        }
        guard status == kCCSuccess,
              bytesWritten == kCCBlockSizeAES128 else {
            throw AppProxyError.connectionFailed(
                "VMess AES-ECB 计算失败（\(status)）"
            )
        }
        return output
    }

    private static let crc32Table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)
        for _ in 0..<8 {
            current = current & 1 == 1
                ? 0xedb88320 ^ (current >> 1)
                : current >> 1
        }
        return current
    }
}

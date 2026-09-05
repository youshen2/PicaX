import CryptoKit
import Foundation

nonisolated enum AppShadowsocksCipher: String, CaseIterable {
    case aes128GCM = "aes-128-gcm"
    case aes256GCM = "aes-256-gcm"
    case chacha20IETFPoly1305 = "chacha20-ietf-poly1305"
    case chacha20Poly1305 = "chacha20-poly1305"

    static func named(_ rawValue: String) -> AppShadowsocksCipher? {
        AppShadowsocksCipher(rawValue: rawValue.lowercased())
    }

    var keyLength: Int {
        switch self {
        case .aes128GCM:
            return 16
        case .aes256GCM, .chacha20IETFPoly1305, .chacha20Poly1305:
            return 32
        }
    }

    var saltLength: Int { keyLength }
    var tagLength: Int { 16 }

    func seal(
        _ plaintext: Data,
        using key: SymmetricKey,
        counter: UInt64
    ) throws -> Data {
        let nonceData = nonce(counter)
        switch self {
        case .aes128GCM, .aes256GCM:
            let box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: AES.GCM.Nonce(data: nonceData)
            )
            return box.ciphertext + box.tag
        case .chacha20IETFPoly1305, .chacha20Poly1305:
            let box = try ChaChaPoly.seal(
                plaintext,
                using: key,
                nonce: ChaChaPoly.Nonce(data: nonceData)
            )
            return box.ciphertext + box.tag
        }
    }

    func open(
        _ encrypted: Data,
        using key: SymmetricKey,
        counter: UInt64
    ) throws -> Data {
        guard encrypted.count >= tagLength else {
            throw AppProxyError.invalidProxyResponse
        }
        let ciphertext = Data(encrypted.dropLast(tagLength))
        let tag = Data(encrypted.suffix(tagLength))
        let nonceData = nonce(counter)
        switch self {
        case .aes128GCM, .aes256GCM:
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key)
        case .chacha20IETFPoly1305, .chacha20Poly1305:
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            return try ChaChaPoly.open(box, using: key)
        }
    }

    private func nonce(_ counter: UInt64) -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        for index in 0..<8 {
            bytes[index] = UInt8(
                (counter >> UInt64(index * 8)) & 0xff
            )
        }
        return Data(bytes)
    }
}

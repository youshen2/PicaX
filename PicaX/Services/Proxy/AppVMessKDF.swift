import CryptoKit
import Foundation

nonisolated enum AppVMessKDFLabel {
    static let root = Data("VMess AEAD KDF".utf8)
    static let authID = Data("AES Auth ID Encryption".utf8)
    static let requestLengthKey = Data(
        "VMess Header AEAD Key_Length".utf8
    )
    static let requestLengthNonce = Data(
        "VMess Header AEAD Nonce_Length".utf8
    )
    static let requestPayloadKey = Data(
        "VMess Header AEAD Key".utf8
    )
    static let requestPayloadNonce = Data(
        "VMess Header AEAD Nonce".utf8
    )
    static let responseLengthKey = Data(
        "AEAD Resp Header Len Key".utf8
    )
    static let responseLengthNonce = Data(
        "AEAD Resp Header Len IV".utf8
    )
    static let responsePayloadKey = Data(
        "AEAD Resp Header Key".utf8
    )
    static let responsePayloadNonce = Data(
        "AEAD Resp Header IV".utf8
    )
}

nonisolated enum AppVMessKDF {
    static func derive(
        key: Data,
        path: [Data],
        length: Int
    ) -> Data {
        var hash: AppVMessHash = AppVMessRecursiveHMAC.make(
            key: AppVMessKDFLabel.root,
            base: AppVMessSHA256()
        )
        for component in path {
            hash = AppVMessRecursiveHMAC.make(
                key: component,
                base: hash
            )
        }
        hash.update(key)
        return Data(hash.digest().prefix(length))
    }
}

private nonisolated protocol AppVMessHash: AnyObject {
    func update(_ data: Data)
    func digest() -> Data
    func copyHash() -> AppVMessHash
}

private nonisolated final class AppVMessSHA256: AppVMessHash {
    func update(_ data: Data) {
        buffer.append(data)
    }

    func digest() -> Data {
        Data(SHA256.hash(data: buffer))
    }

    func copyHash() -> AppVMessHash {
        let copy = AppVMessSHA256()
        copy.buffer = buffer
        return copy
    }

    private var buffer = Data()
}

private nonisolated final class AppVMessRecursiveHMAC: AppVMessHash {
    static func make(
        key: Data,
        base: AppVMessHash
    ) -> AppVMessRecursiveHMAC {
        precondition(key.count <= blockSize)
        var paddedKey = key
        paddedKey.append(
            Data(repeating: 0, count: blockSize - paddedKey.count)
        )
        var innerPad = Data(count: blockSize)
        var outerPad = Data(count: blockSize)
        for index in 0..<blockSize {
            innerPad[index] = paddedKey[index] ^ 0x36
            outerPad[index] = paddedKey[index] ^ 0x5c
        }
        let inner = base.copyHash()
        inner.update(innerPad)
        return AppVMessRecursiveHMAC(
            inner: inner,
            outer: base,
            outerPad: outerPad
        )
    }

    func update(_ data: Data) {
        inner.update(data)
    }

    func digest() -> Data {
        let innerDigest = Data(inner.digest().prefix(32))
        let outerCopy = outer.copyHash()
        outerCopy.update(outerPad)
        outerCopy.update(innerDigest)
        return outerCopy.digest()
    }

    func copyHash() -> AppVMessHash {
        AppVMessRecursiveHMAC(
            inner: inner.copyHash(),
            outer: outer.copyHash(),
            outerPad: outerPad
        )
    }

    private init(
        inner: AppVMessHash,
        outer: AppVMessHash,
        outerPad: Data
    ) {
        self.inner = inner
        self.outer = outer
        self.outerPad = outerPad
    }

    private let inner: AppVMessHash
    private let outer: AppVMessHash
    private let outerPad: Data
    private static let blockSize = 64
}

import CryptoKit
import Foundation
import Network

nonisolated enum AppShadowsocksClient {
    static func openTunnel(
        profile: AppBuiltInProxyProfile,
        secret: AppBuiltInProxySecret,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        guard let password = secret.password, !password.isEmpty,
              let cipherName = secret.cipher,
              let cipher = AppShadowsocksCipher.named(cipherName) else {
            if let cipherName = secret.cipher {
                throw AppProxyError.unsupportedCipher(cipherName)
            }
            throw AppProxyError.builtInSecretUnavailable
        }
        guard let port = NWEndpoint.Port(rawValue: profile.port) else {
            throw AppProxyError.invalidPort
        }
        let masterKey = deriveMasterKey(
            password: password,
            length: cipher.keyLength
        )
        let connection = NWConnection(
            host: NWEndpoint.Host(profile.server),
            port: port,
            using: .tcp
        )
        let rawTunnel = NWConnectionAppProxyTunnel(connection: connection)
        do {
            try await connection.startForAppProxy()
            let tunnel = AppShadowsocksTunnel(
                rawTunnel: rawTunnel,
                cipher: cipher,
                masterKey: masterKey
            )
            try await tunnel.performHandshake(
                destinationHost: destinationHost,
                destinationPort: destinationPort
            )
            return tunnel
        } catch {
            rawTunnel.close()
            throw error
        }
    }

    private static func deriveMasterKey(
        password: String,
        length: Int
    ) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var keyData = Data()
        var previousDigest = Data()
        while keyData.count < length {
            let digest = Data(
                Insecure.MD5.hash(
                    data: previousDigest + passwordData
                )
            )
            keyData.append(digest)
            previousDigest = digest
        }
        return SymmetricKey(data: keyData.prefix(length))
    }
}

private actor AppShadowsocksTunnel: AppProxyByteTunnel {
    init(
        rawTunnel: NWConnectionAppProxyTunnel,
        cipher: AppShadowsocksCipher,
        masterKey: SymmetricKey
    ) {
        self.rawTunnel = rawTunnel
        self.cipher = cipher
        self.masterKey = masterKey
    }

    func performHandshake(
        destinationHost: String,
        destinationPort: UInt16
    ) async throws {
        let salt = try AppProxyCrypto.randomBytes(
            count: cipher.saltLength
        )
        transmitKey = deriveSubkey(salt: salt)
        let destination = try AppProxyAddressCodec.socks(
            host: destinationHost,
            port: destinationPort
        )
        try await rawTunnel.send(
            salt + encryptedFrame(destination)
        )
    }

    func send(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let end = min(offset + maximumPayloadLength, data.count)
            let payload = data.subdata(in: offset..<end)
            try await rawTunnel.send(encryptedFrame(payload))
            offset = end
        }
    }

    func receive() async throws -> Data {
        if receiveKey == nil {
            let salt = try await rawTunnel.readExactly(
                cipher.saltLength
            )
            receiveKey = deriveSubkey(salt: salt)
        }
        guard let key = receiveKey else {
            throw AppProxyError.invalidProxyResponse
        }
        let encryptedLength = try await rawTunnel.readExactly(
            2 + cipher.tagLength
        )
        let lengthData = try cipher.open(
            encryptedLength,
            using: key,
            counter: receiveCounter
        )
        receiveCounter &+= 1
        guard lengthData.count == 2 else {
            throw AppProxyError.invalidProxyResponse
        }
        let length = Int(lengthData[0]) << 8 | Int(lengthData[1])
        guard (1...maximumPayloadLength).contains(length) else {
            throw AppProxyError.invalidProxyResponse
        }
        let encryptedPayload = try await rawTunnel.readExactly(
            length + cipher.tagLength
        )
        let payload = try cipher.open(
            encryptedPayload,
            using: key,
            counter: receiveCounter
        )
        receiveCounter &+= 1
        return payload
    }

    nonisolated func close() {
        rawTunnel.close()
    }

    private func encryptedFrame(_ payload: Data) throws -> Data {
        guard let key = transmitKey else {
            throw AppProxyError.invalidProxyResponse
        }
        var length = Data(count: 2)
        length[0] = UInt8((payload.count >> 8) & 0xff)
        length[1] = UInt8(payload.count & 0xff)
        let encryptedLength = try cipher.seal(
            length,
            using: key,
            counter: transmitCounter
        )
        transmitCounter &+= 1
        let encryptedPayload = try cipher.seal(
            payload,
            using: key,
            counter: transmitCounter
        )
        transmitCounter &+= 1
        return encryptedLength + encryptedPayload
    }

    private func deriveSubkey(salt: Data) -> SymmetricKey {
        HKDF<Insecure.SHA1>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: Data("ss-subkey".utf8),
            outputByteCount: cipher.keyLength
        )
    }

    nonisolated private let rawTunnel: NWConnectionAppProxyTunnel
    private let cipher: AppShadowsocksCipher
    private let masterKey: SymmetricKey
    private var transmitKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var transmitCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0
    private let maximumPayloadLength = 0x3fff
}

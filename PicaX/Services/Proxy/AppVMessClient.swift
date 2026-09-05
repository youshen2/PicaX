import CryptoKit
import Foundation
import Network

nonisolated enum AppVMessClient {
    static func openTunnel(
        profile: AppBuiltInProxyProfile,
        secret: AppBuiltInProxySecret,
        destinationHost: String,
        destinationPort: UInt16
    ) async throws -> AppProxyByteTunnel {
        guard let uuidText = secret.uuid,
              let uuid = UUID(uuidString: uuidText) else {
            throw AppProxyError.invalidUUID
        }
        guard (secret.alterID ?? 0) == 0 else {
            throw AppProxyError.unsupportedBuiltInProtocol(
                "VMess alterId \(secret.alterID ?? 0)"
            )
        }
        guard let port = NWEndpoint.Port(rawValue: profile.port) else {
            throw AppProxyError.invalidPort
        }

        let commandKey = Data(
            Insecure.MD5.hash(
                data: uuid.networkBytes
                    + Data(
                        "c48619fe-8f02-49e0-b9e9-edf763e17e21"
                            .utf8
                    )
            )
        )
        let authID = try makeAuthID(commandKey: commandKey)
        let bodyIV = try AppProxyCrypto.randomBytes(count: 16)
        let bodyKey = try AppProxyCrypto.randomBytes(count: 16)
        let responseMarker = try AppProxyCrypto.randomBytes(count: 1)[0]
        let header = try makeInstructionHeader(
            bodyIV: bodyIV,
            bodyKey: bodyKey,
            responseMarker: responseMarker,
            destinationHost: destinationHost,
            destinationPort: destinationPort
        )
        let request = try makeEncryptedHeader(
            commandKey: commandKey,
            authID: authID,
            header: header
        )

        let connection = NWConnection(
            host: NWEndpoint.Host(profile.server),
            port: port,
            using: .tcp
        )
        let rawTunnel = NWConnectionAppProxyTunnel(connection: connection)
        do {
            try await connection.startForAppProxy()
            try await rawTunnel.send(request)
            let responseMaterial = responseMaterial(
                bodyKey: bodyKey,
                bodyIV: bodyIV
            )
            try await validateResponseHeader(
                rawTunnel: rawTunnel,
                responseKey: responseMaterial.key,
                responseIV: responseMaterial.iv,
                expectedMarker: responseMarker
            )
            return AppVMessTunnel(
                rawTunnel: rawTunnel,
                requestKey: SymmetricKey(data: bodyKey),
                requestIV: bodyIV,
                responseKey: SymmetricKey(
                    data: responseMaterial.key
                ),
                responseIV: responseMaterial.iv
            )
        } catch {
            rawTunnel.close()
            throw error
        }
    }

    private static func makeAuthID(
        commandKey: Data
    ) throws -> Data {
        let timestamp = UInt64(Date().timeIntervalSince1970)
        var plaintext = Data(count: 8)
        for index in 0..<8 {
            plaintext[index] = UInt8(
                (timestamp >> UInt64((7 - index) * 8)) & 0xff
            )
        }
        plaintext.append(
            try AppProxyCrypto.randomBytes(count: 4)
        )
        let checksum = AppProxyCrypto.crc32(plaintext)
        appendBigEndian(checksum, to: &plaintext)
        let encryptionKey = AppVMessKDF.derive(
            key: commandKey,
            path: [AppVMessKDFLabel.authID],
            length: 16
        )
        return try AppProxyCrypto.aes128ECBEncrypt(
            block: plaintext,
            key: encryptionKey
        )
    }

    private static func makeInstructionHeader(
        bodyIV: Data,
        bodyKey: Data,
        responseMarker: UInt8,
        destinationHost: String,
        destinationPort: UInt16
    ) throws -> Data {
        var header = Data([0x01])
        header.append(bodyIV)
        header.append(bodyKey)
        header.append(responseMarker)
        header.append(0x01)
        header.append(0x03)
        header.append(0x00)
        header.append(0x01)
        header.append(UInt8(destinationPort >> 8))
        header.append(UInt8(destinationPort & 0xff))
        header.append(
            try AppProxyAddressCodec.vmess(host: destinationHost)
        )
        appendBigEndian(
            AppProxyCrypto.fnv1a32(header),
            to: &header
        )
        return header
    }

    private static func makeEncryptedHeader(
        commandKey: Data,
        authID: Data,
        header: Data
    ) throws -> Data {
        let nonce = try AppProxyCrypto.randomBytes(count: 8)
        var headerLength = Data([
            UInt8((header.count >> 8) & 0xff),
            UInt8(header.count & 0xff)
        ])
        headerLength = try seal(
            headerLength,
            key: AppVMessKDF.derive(
                key: commandKey,
                path: [
                    AppVMessKDFLabel.requestLengthKey,
                    authID,
                    nonce
                ],
                length: 16
            ),
            nonce: AppVMessKDF.derive(
                key: commandKey,
                path: [
                    AppVMessKDFLabel.requestLengthNonce,
                    authID,
                    nonce
                ],
                length: 12
            ),
            associatedData: authID
        )
        let encryptedHeader = try seal(
            header,
            key: AppVMessKDF.derive(
                key: commandKey,
                path: [
                    AppVMessKDFLabel.requestPayloadKey,
                    authID,
                    nonce
                ],
                length: 16
            ),
            nonce: AppVMessKDF.derive(
                key: commandKey,
                path: [
                    AppVMessKDFLabel.requestPayloadNonce,
                    authID,
                    nonce
                ],
                length: 12
            ),
            associatedData: authID
        )
        return authID + headerLength + nonce + encryptedHeader
    }

    private static func responseMaterial(
        bodyKey: Data,
        bodyIV: Data
    ) -> (key: Data, iv: Data) {
        (
            Data(SHA256.hash(data: bodyKey).prefix(16)),
            Data(SHA256.hash(data: bodyIV).prefix(16))
        )
    }

    private static func validateResponseHeader(
        rawTunnel: NWConnectionAppProxyTunnel,
        responseKey: Data,
        responseIV: Data,
        expectedMarker: UInt8
    ) async throws {
        let encryptedLength = try await rawTunnel.readExactly(18)
        let lengthData = try open(
            encryptedLength,
            key: AppVMessKDF.derive(
                key: responseKey,
                path: [AppVMessKDFLabel.responseLengthKey],
                length: 16
            ),
            nonce: AppVMessKDF.derive(
                key: responseIV,
                path: [AppVMessKDFLabel.responseLengthNonce],
                length: 12
            )
        )
        guard lengthData.count == 2 else {
            throw AppProxyError.invalidProxyResponse
        }
        let length = Int(lengthData[0]) << 8 | Int(lengthData[1])
        guard (4...1_024).contains(length) else {
            throw AppProxyError.invalidProxyResponse
        }
        let encryptedHeader = try await rawTunnel.readExactly(
            length + 16
        )
        let header = try open(
            encryptedHeader,
            key: AppVMessKDF.derive(
                key: responseKey,
                path: [AppVMessKDFLabel.responsePayloadKey],
                length: 16
            ),
            nonce: AppVMessKDF.derive(
                key: responseIV,
                path: [AppVMessKDFLabel.responsePayloadNonce],
                length: 12
            )
        )
        guard header.first == expectedMarker else {
            throw AppProxyError.invalidProxyResponse
        }
    }

    private static func seal(
        _ plaintext: Data,
        key: Data,
        nonce: Data,
        associatedData: Data = Data()
    ) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: AES.GCM.Nonce(data: nonce),
            authenticating: associatedData
        )
        return box.ciphertext + box.tag
    }

    private static func open(
        _ encrypted: Data,
        key: Data,
        nonce: Data
    ) throws -> Data {
        guard encrypted.count >= 16 else {
            throw AppProxyError.invalidProxyResponse
        }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: Data(encrypted.dropLast(16)),
            tag: Data(encrypted.suffix(16))
        )
        return try AES.GCM.open(
            box,
            using: SymmetricKey(data: key)
        )
    }

    private static func appendBigEndian(
        _ value: UInt32,
        to data: inout Data
    ) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}

private actor AppVMessTunnel: AppProxyByteTunnel {
    init(
        rawTunnel: NWConnectionAppProxyTunnel,
        requestKey: SymmetricKey,
        requestIV: Data,
        responseKey: SymmetricKey,
        responseIV: Data
    ) {
        self.rawTunnel = rawTunnel
        self.requestKey = requestKey
        requestIVPrefix = Data(
            requestIV.dropFirst(2).prefix(10)
        )
        self.responseKey = responseKey
        responseIVPrefix = Data(
            responseIV.dropFirst(2).prefix(10)
        )
    }

    func send(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let end = min(offset + maximumPayloadLength, data.count)
            let payload = data.subdata(in: offset..<end)
            let nonce = try nextNonce(
                counter: &requestCounter,
                prefix: requestIVPrefix
            )
            let box = try AES.GCM.seal(
                payload,
                using: requestKey,
                nonce: AES.GCM.Nonce(data: nonce)
            )
            let payloadLength = box.ciphertext.count + box.tag.count
            var frame = Data([
                UInt8((payloadLength >> 8) & 0xff),
                UInt8(payloadLength & 0xff)
            ])
            frame.append(box.ciphertext)
            frame.append(box.tag)
            try await rawTunnel.send(frame)
            offset = end
        }
    }

    func receive() async throws -> Data {
        let lengthData = try await rawTunnel.readExactly(2)
        let length = Int(lengthData[0]) << 8 | Int(lengthData[1])
        guard (17...(maximumPayloadLength + 16)).contains(length) else {
            throw AppProxyError.invalidProxyResponse
        }
        let encrypted = try await rawTunnel.readExactly(length)
        let nonce = try nextNonce(
            counter: &responseCounter,
            prefix: responseIVPrefix
        )
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: Data(encrypted.dropLast(16)),
            tag: Data(encrypted.suffix(16))
        )
        return try AES.GCM.open(box, using: responseKey)
    }

    nonisolated func close() {
        rawTunnel.close()
    }

    private func nextNonce(
        counter: inout UInt16,
        prefix: Data
    ) throws -> Data {
        guard counter < UInt16.max else {
            throw AppProxyError.connectionFailed(
                "VMess 会话已达到安全数据上限"
            )
        }
        var nonce = Data([
            UInt8(counter >> 8),
            UInt8(counter & 0xff)
        ])
        nonce.append(prefix)
        counter += 1
        return nonce
    }

    nonisolated private let rawTunnel: NWConnectionAppProxyTunnel
    private let requestKey: SymmetricKey
    private let requestIVPrefix: Data
    private let responseKey: SymmetricKey
    private let responseIVPrefix: Data
    private var requestCounter: UInt16 = 0
    private var responseCounter: UInt16 = 0
    private let maximumPayloadLength = 0x3fff
}

private nonisolated extension UUID {
    var networkBytes: Data {
        let bytes = uuid
        return Data([
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ])
    }
}

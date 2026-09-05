import Foundation

nonisolated final class AppProxyHTTPChannelReader {
    init(channel: AppProxyHTTPChannel) {
        self.channel = channel
    }

    func readThrough(
        _ delimiter: Data,
        maximumLength: Int
    ) throws -> Data {
        while true {
            if let range = buffer.range(of: delimiter) {
                let end = range.upperBound
                let result = Data(buffer[..<end])
                buffer.removeSubrange(..<end)
                return result
            }
            guard buffer.count < maximumLength else {
                throw AppProxyError.invalidHTTPResponse(
                    "响应头超过大小限制"
                )
            }
            let chunk = try channel.read()
            guard !chunk.isEmpty else {
                throw AppProxyError.connectionClosed
            }
            buffer.append(chunk)
        }
    }

    func readExactly(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count < count {
            let chunk = try channel.read()
            guard !chunk.isEmpty else {
                throw AppProxyError.connectionClosed
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    func readChunkedBody() throws -> Data {
        var result = Data()
        while true {
            let sizeLineData = try readThrough(
                Data("\r\n".utf8),
                maximumLength: 8 * 1_024
            )
            guard var sizeLine = String(
                data: sizeLineData.dropLast(2),
                encoding: .ascii
            ) else {
                throw AppProxyError.invalidHTTPResponse(
                    "分块响应长度无效"
                )
            }
            if let extensionIndex = sizeLine.firstIndex(of: ";") {
                sizeLine = String(sizeLine[..<extensionIndex])
            }
            guard let chunkSize = Int(
                sizeLine.trimmingCharacters(in: .whitespaces),
                radix: 16
            ), chunkSize >= 0 else {
                throw AppProxyError.invalidHTTPResponse(
                    "分块响应长度无效"
                )
            }
            if chunkSize == 0 {
                while true {
                    let trailer = try readThrough(
                        Data("\r\n".utf8),
                        maximumLength: 16 * 1_024
                    )
                    if trailer == Data("\r\n".utf8) {
                        return result
                    }
                }
            }
            guard result.count <= 128 * 1_024 * 1_024 - chunkSize else {
                throw AppProxyError.responseTooLarge
            }
            result.append(try readExactly(chunkSize))
            guard try readExactly(2) == Data("\r\n".utf8) else {
                throw AppProxyError.invalidHTTPResponse(
                    "分块响应分隔符无效"
                )
            }
        }
    }

    func readToEnd(maximumLength: Int) throws -> Data {
        var result = buffer
        buffer.removeAll(keepingCapacity: true)
        while true {
            let chunk = try channel.read()
            if chunk.isEmpty {
                return result
            }
            guard result.count <= maximumLength - chunk.count else {
                throw AppProxyError.responseTooLarge
            }
            result.append(chunk)
        }
    }

    private let channel: AppProxyHTTPChannel
    private var buffer = Data()
}

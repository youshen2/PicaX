import Foundation

nonisolated protocol AppProxyHTTPChannel: AnyObject {
    func write(_ data: Data) throws
    func read() throws -> Data
    func close()
}

private nonisolated final class HTTPAsyncResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func take() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = result
        result = nil
        return value
    }
}

nonisolated final class AppProxyPlainHTTPChannel: AppProxyHTTPChannel, Sendable {
    init(tunnel: AppProxyByteTunnel) {
        self.tunnel = tunnel
    }

    func write(_ data: Data) throws {
        try bridge {
            try await self.tunnel.send(data)
        }
    }

    func read() throws -> Data {
        try bridge {
            try await self.tunnel.receive()
        }
    }

    func close() {
        tunnel.close()
    }

    private func bridge<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = HTTPAsyncResultBox<T>()
        Task {
            do {
                resultBox.store(.success(try await operation()))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = resultBox.take() else {
            throw AppProxyError.connectionClosed
        }
        return try result.get()
    }

    private let tunnel: AppProxyByteTunnel
}

nonisolated final class AppProxySecureHTTPChannel: AppProxyHTTPChannel {
    init(tls: AppProxyTLS) {
        self.tls = tls
    }

    func write(_ data: Data) throws {
        try tls.write(data)
    }

    func read() throws -> Data {
        try tls.read()
    }

    func close() {
        tls.close()
    }

    private let tls: AppProxyTLS
}

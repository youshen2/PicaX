import Foundation

nonisolated final class AppProxyTLS {
    init(
        tunnel: AppProxyByteTunnel,
        hostname: String,
        proxyDescription: String
    ) {
        bridge = AppProxyTLSBridge(
            remoteTunnel: tunnel,
            hostname: hostname,
            proxyDescription: proxyDescription
        )
    }

    func handshake() throws {
        guard secureTunnel == nil else { return }
        secureTunnel = try blocking { [bridge] in
            try await bridge.start()
        }
    }

    func write(_ data: Data) throws {
        guard let secureTunnel else {
            throw AppProxyError.connectionClosed
        }
        do {
            try blocking {
                try await secureTunnel.send(data)
            }
        } catch {
            if let remoteFailure = bridge.remoteFailure {
                throw remoteFailure
            }
            if error is AppProxyError {
                throw error
            }
            throw AppProxyError.tlsIOFailed(
                error.localizedDescription
            )
        }
    }

    func read() throws -> Data {
        guard let secureTunnel else {
            throw AppProxyError.connectionClosed
        }
        do {
            let data = try blocking {
                try await secureTunnel.receive()
            }
            if data.isEmpty, let remoteFailure = bridge.remoteFailure {
                throw remoteFailure
            }
            return data
        } catch {
            if let remoteFailure = bridge.remoteFailure {
                throw remoteFailure
            }
            if error is AppProxyError {
                throw error
            }
            throw AppProxyError.tlsIOFailed(
                error.localizedDescription
            )
        }
    }

    func close() {
        bridge.close()
    }

    deinit {
        close()
    }

    private func blocking<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = AppProxyTLSResultBox<T>()
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

    private let bridge: AppProxyTLSBridge
    private var secureTunnel: NWConnectionAppProxyTunnel?
}

private nonisolated final class AppProxyTLSResultBox<Value: Sendable>: @unchecked Sendable {
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
        let result = self.result
        self.result = nil
        return result
    }
}

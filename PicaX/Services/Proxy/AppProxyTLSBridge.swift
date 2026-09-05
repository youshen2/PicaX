import Foundation
import Network
import Security

/// Feeds the system TLS stack through an already-established proxy tunnel.
/// The TLS connection can only reach a one-shot loopback listener; the
/// listener relays its encrypted bytes to `remoteTunnel`.
nonisolated final class AppProxyTLSBridge: @unchecked Sendable {
    init(
        remoteTunnel: AppProxyByteTunnel,
        hostname: String,
        proxyDescription: String
    ) {
        self.remoteTunnel = remoteTunnel
        self.hostname = hostname
        self.proxyDescription = proxyDescription
    }

    func start() async throws -> NWConnectionAppProxyTunnel {
        let listener = try makeListener()
        let listenerState = AppProxyTLSListenerState()
        install(listener: listener)

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                guard let port = listener?.port else {
                    listenerState.resolve(
                        .failure(
                            AppProxyError.tlsHandshakeFailed(
                                "无法取得本地 TLS 桥接端口"
                            )
                        )
                    )
                    return
                }
                listenerState.resolve(.success(port))
            case .failed(let error):
                self?.close()
                listenerState.resolve(
                    .failure(
                        AppProxyError.tlsHandshakeFailed(
                            "本地 TLS 桥接启动失败："
                                + error.localizedDescription
                        )
                    )
                )
            case .cancelled:
                listenerState.resolve(.failure(CancellationError()))
            default:
                break
            }
        }
        listener.start(queue: queue)

        let port: NWEndpoint.Port
        do {
            port = try await withTaskCancellationHandler {
                try await listenerState.value()
            } onCancel: {
                listener.cancel()
                listenerState.resolve(.failure(CancellationError()))
            }
        } catch {
            close()
            throw error
        }

        let secureConnection = makeSecureConnection(port: port)
        let secureTunnel = NWConnectionAppProxyTunnel(
            connection: secureConnection
        )
        install(
            secureConnection: secureConnection
        )

        do {
            try await secureConnection.startForAppProxy()
            markTLSReady()
            return secureTunnel
        } catch {
            let failure = remoteFailure
            close()
            if let failure {
                throw failure
            }
            throw AppProxyError.tlsHandshakeFailed(
                error.localizedDescription
            )
        }
    }

    func close() {
        let resources: Resources
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        resources = Resources(
            listener: listener,
            localConnection: localConnection,
            secureConnection: secureConnection,
            upstreamTask: upstreamTask,
            downstreamTask: downstreamTask
        )
        listener = nil
        localConnection = nil
        secureConnection = nil
        upstreamTask = nil
        downstreamTask = nil
        lock.unlock()

        resources.listener?.cancel()
        resources.localConnection?.cancel()
        resources.secureConnection?.cancel()
        resources.upstreamTask?.cancel()
        resources.downstreamTask?.cancel()
        remoteTunnel.close()
    }

    var remoteFailure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedRemoteFailure
    }

    private func makeListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: .any
        )
        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionLimit = 1
        return listener
    }

    private func makeSecureConnection(
        port: NWEndpoint.Port
    ) -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            hostname
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )
        sec_protocol_options_add_tls_application_protocol(
            tlsOptions.securityProtocolOptions,
            "http/1.1"
        )
        let parameters = NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )
        parameters.includePeerToPeer = false
        return NWConnection(
            host: "127.0.0.1",
            port: port,
            using: parameters
        )
    }

    private func accept(_ connection: NWConnection) {
        guard AppProxyLoopback.isPeer(connection.endpoint) else {
            connection.cancel()
            return
        }

        let listener: NWListener?
        lock.lock()
        guard !isFinished, localConnection == nil else {
            lock.unlock()
            connection.cancel()
            return
        }
        localConnection = connection
        listener = self.listener
        self.listener = nil
        lock.unlock()
        listener?.cancel()

        Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            do {
                try await connection.startForAppProxy()
                self.beginRelaying(
                    localTunnel: NWConnectionAppProxyTunnel(
                        connection: connection
                    )
                )
            } catch {
                self.close()
            }
        }
    }

    private func beginRelaying(
        localTunnel: NWConnectionAppProxyTunnel
    ) {
        let upstream = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let data: Data
                do {
                    data = try await localTunnel.receive()
                } catch {
                    self.close()
                    return
                }
                guard !data.isEmpty else {
                    self.close()
                    return
                }
                do {
                    try await self.remoteTunnel.send(data)
                } catch {
                    self.failRemote(error)
                    return
                }
            }
        }

        let downstream = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let data: Data
                do {
                    data = try await self.remoteTunnel.receive()
                } catch {
                    self.failRemote(
                        self.contextualRemoteError(error)
                    )
                    return
                }
                guard !data.isEmpty else {
                    if !self.isTLSReady {
                        self.recordRemoteFailure(
                            AppProxyError.tunnelClosedBeforeTLS(
                                self.proxyDescription
                            )
                        )
                    }
                    // Preserve already-forwarded TLS records before EOF.
                    // Cancelling both local connections here can truncate the
                    // final HTTP response buffered by Network.framework.
                    try? await localTunnel.finishSending()
                    return
                }
                do {
                    try await localTunnel.send(data)
                } catch {
                    self.close()
                    return
                }
            }
        }

        lock.lock()
        if isFinished {
            lock.unlock()
            upstream.cancel()
            downstream.cancel()
            localTunnel.close()
            return
        }
        upstreamTask = upstream
        downstreamTask = downstream
        lock.unlock()
    }

    private func failRemote(_ error: Error) {
        recordRemoteFailure(error)
        close()
    }

    private func contextualRemoteError(_ error: Error) -> Error {
        guard !isTLSReady,
              let proxyError = error as? AppProxyError,
              case .connectionClosed = proxyError else {
            return error
        }
        return AppProxyError.tunnelClosedBeforeTLS(proxyDescription)
    }

    private func recordRemoteFailure(_ error: Error) {
        lock.lock()
        if storedRemoteFailure == nil {
            storedRemoteFailure = error
        }
        lock.unlock()
    }

    private var isTLSReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tlsReady
    }

    private func markTLSReady() {
        lock.lock()
        tlsReady = true
        lock.unlock()
    }

    private func install(listener: NWListener) {
        lock.lock()
        self.listener = listener
        lock.unlock()
    }

    private func install(
        secureConnection: NWConnection
    ) {
        lock.lock()
        self.secureConnection = secureConnection
        let shouldClose = isFinished
        lock.unlock()
        if shouldClose {
            secureConnection.cancel()
        }
    }

    private struct Resources {
        let listener: NWListener?
        let localConnection: NWConnection?
        let secureConnection: NWConnection?
        let upstreamTask: Task<Void, Never>?
        let downstreamTask: Task<Void, Never>?
    }

    private let remoteTunnel: AppProxyByteTunnel
    private let hostname: String
    private let proxyDescription: String
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "work.picax.app-proxy.tls-bridge",
        qos: .userInitiated
    )
    private var listener: NWListener?
    private var localConnection: NWConnection?
    private var secureConnection: NWConnection?
    private var upstreamTask: Task<Void, Never>?
    private var downstreamTask: Task<Void, Never>?
    private var storedRemoteFailure: Error?
    private var tlsReady = false
    private var isFinished = false
}

private nonisolated final class AppProxyTLSListenerState: @unchecked Sendable {
    func value() async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                self.result = nil
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resolve(_ result: Result<NWEndpoint.Port, Error>) {
        let continuation:
            CheckedContinuation<NWEndpoint.Port, Error>?
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            self.result = result
        }
        lock.unlock()
        continuation?.resume(with: result)
    }

    private let lock = NSLock()
    private var continuation:
        CheckedContinuation<NWEndpoint.Port, Error>?
    private var result: Result<NWEndpoint.Port, Error>?
    private var isResolved = false
}

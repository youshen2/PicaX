import Foundation
import Network

private nonisolated final class LocalBridgeStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var result: Result<URL, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<URL, Error>) {
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

    func resolve(_ result: Result<URL, Error>) {
        let continuation: CheckedContinuation<URL, Error>?
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
}

nonisolated final class AppLocalProxyBridge: @unchecked Sendable {
    func start(route: AppProxyRoute) async throws -> URL {
        stop()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: .any
        )
        let listener = try NWListener(using: parameters, on: .any)
        let generation = UUID()
        let startState = LocalBridgeStartState()
        let localUsername = "picax"
        let localPassword = UUID().uuidString
        let expectedAuthorization = "Basic " + Data(
            "\(localUsername):\(localPassword)".utf8
        ).base64EncodedString()

        install(listener: listener, generation: generation)

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(
                connection,
                route: route,
                generation: generation,
                expectedAuthorization: expectedAuthorization
            )
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                guard let listener,
                      let port = listener.port else {
                    startState.resolve(
                        .failure(
                            AppProxyError.localBridgeUnavailable(
                                "未能取得本地监听端口"
                            )
                        )
                    )
                    return
                }
                var components = URLComponents()
                components.scheme = "http"
                components.user = localUsername
                components.password = localPassword
                components.host = "127.0.0.1"
                components.port = Int(port.rawValue)
                guard let url = components.url else {
                    startState.resolve(
                        .failure(
                            AppProxyError.localBridgeUnavailable(
                                "本地监听地址无效"
                            )
                        )
                    )
                    return
                }
                startState.resolve(.success(url))
            case .failed(let error):
                self?.clearListener(generation: generation)
                startState.resolve(
                    .failure(
                        AppProxyError.localBridgeUnavailable(
                            error.localizedDescription
                        )
                    )
                )
            case .cancelled:
                startState.resolve(
                    .failure(CancellationError())
                )
            default:
                break
            }
        }
        listener.start(queue: queue)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startState.install(continuation)
            }
        } onCancel: {
            listener.cancel()
            startState.resolve(.failure(CancellationError()))
        }
    }

    func stop() {
        lock.lock()
        let listener = self.listener
        self.listener = nil
        listenerGeneration = nil
        let relays = Array(activeRelays.values)
        activeRelays.removeAll()
        lock.unlock()
        listener?.cancel()
        relays.forEach { $0.close() }
    }

    private func accept(
        _ connection: NWConnection,
        route: AppProxyRoute,
        generation: UUID,
        expectedAuthorization: String
    ) {
        guard AppProxyLoopback.isPeer(connection.endpoint) else {
            connection.cancel()
            return
        }
        lock.lock()
        guard listenerGeneration == generation,
              activeRelays.count < Self.maximumRelayCount else {
            lock.unlock()
            connection.cancel()
            return
        }
        let id = UUID()
        let relay = AppLocalProxyRelay(
            id: id,
            connection: connection,
            route: route,
            expectedAuthorization: expectedAuthorization
        ) { [weak self] id in
            self?.removeRelay(id)
        }
        activeRelays[id] = relay
        lock.unlock()
        relay.start()
    }

    private func install(listener: NWListener, generation: UUID) {
        lock.lock()
        self.listener = listener
        listenerGeneration = generation
        lock.unlock()
    }

    private func removeRelay(_ id: UUID) {
        lock.lock()
        activeRelays[id] = nil
        lock.unlock()
    }

    private func clearListener(generation: UUID) {
        lock.lock()
        if listenerGeneration == generation {
            listener = nil
            listenerGeneration = nil
        }
        lock.unlock()
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "work.picax.app-proxy.local-listener",
        qos: .userInitiated
    )
    private var listener: NWListener?
    private var listenerGeneration: UUID?
    private var activeRelays = [UUID: AppLocalProxyRelay]()
    private static let maximumRelayCount = 16
}

nonisolated final class AppLocalProxyLease: @unchecked Sendable {
    static func start(route: AppProxyRoute) async throws
        -> AppLocalProxyLease {
        let bridge = AppLocalProxyBridge()
        let proxyURL = try await bridge.start(route: route)
        return AppLocalProxyLease(
            proxyURL: proxyURL,
            bridge: bridge
        )
    }

    let proxyURL: URL

    func invalidate() {
        lock.lock()
        let bridge = self.bridge
        self.bridge = nil
        lock.unlock()
        bridge?.stop()
    }

    deinit {
        invalidate()
    }

    private init(
        proxyURL: URL,
        bridge: AppLocalProxyBridge
    ) {
        self.proxyURL = proxyURL
        self.bridge = bridge
    }

    private let lock = NSLock()
    private var bridge: AppLocalProxyBridge?
}

import Foundation
import Network

nonisolated final class AppLocalProxyRelay: @unchecked Sendable {
    init(
        id: UUID,
        connection: NWConnection,
        route: AppProxyRoute,
        expectedAuthorization: String,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        localTunnel = NWConnectionAppProxyTunnel(connection: connection)
        self.connection = connection
        self.route = route
        self.expectedAuthorization = expectedAuthorization
        self.onClose = onClose
    }

    func start() {
        Task { [weak self] in
            await self?.handle()
        }
    }

    func close() {
        finish()
    }

    private func handle() async {
        do {
            try await connection.startForAppProxy()
            let headerData = try await localTunnel.readThrough(
                Data("\r\n\r\n".utf8),
                maximumLength: 64 * 1_024
            )
            let request = try AppLocalProxyRequest(headerData: headerData)
            guard request.proxyAuthorization == expectedAuthorization else {
                try? await localTunnel.send(
                    Data(
                        (
                            "HTTP/1.1 407 Proxy Authentication Required\r\n"
                                + "Proxy-Authenticate: Basic realm=\"PicaX\"\r\n"
                                + "Connection: close\r\n"
                                + "Content-Length: 0\r\n\r\n"
                        ).utf8
                    )
                )
                finish()
                return
            }
            let remoteTunnel = try await AppProxyConnector.openTunnel(
                route: route,
                destinationHost: request.destinationHost,
                destinationPort: request.destinationPort
            )
            setRemoteTunnel(remoteTunnel)

            if request.isConnect {
                try await localTunnel.send(
                    Data(
                        "HTTP/1.1 200 Connection Established\r\n\r\n"
                            .utf8
                    )
                )
            } else {
                try await remoteTunnel.send(request.forwardHeader)
            }
            beginRelaying(to: remoteTunnel)
        } catch {
            try? await localTunnel.send(
                Data(
                    (
                        "HTTP/1.1 502 Bad Gateway\r\n"
                            + "Connection: close\r\n"
                            + "Content-Length: 0\r\n\r\n"
                    ).utf8
                )
            )
            finish()
        }
    }

    private func beginRelaying(to remoteTunnel: AppProxyByteTunnel) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isFinished else { return }
        upstreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                while true {
                    let data = try await localTunnel.receive()
                    guard !data.isEmpty else { break }
                    try await remoteTunnel.send(data)
                }
            } catch {}
            finish()
        }
        downstreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                while true {
                    let data = try await remoteTunnel.receive()
                    guard !data.isEmpty else { break }
                    try await localTunnel.send(data)
                }
            } catch {}
            finish()
        }
    }

    private func setRemoteTunnel(_ tunnel: AppProxyByteTunnel) {
        stateLock.lock()
        remoteTunnel = tunnel
        let shouldClose = isFinished
        stateLock.unlock()
        if shouldClose {
            tunnel.close()
        }
    }

    private func finish() {
        let remoteTunnel: AppProxyByteTunnel?
        stateLock.lock()
        guard !isFinished else {
            stateLock.unlock()
            return
        }
        isFinished = true
        remoteTunnel = self.remoteTunnel
        self.remoteTunnel = nil
        let upstreamTask = self.upstreamTask
        let downstreamTask = self.downstreamTask
        self.upstreamTask = nil
        self.downstreamTask = nil
        stateLock.unlock()

        localTunnel.close()
        remoteTunnel?.close()
        upstreamTask?.cancel()
        downstreamTask?.cancel()
        onClose(id)
    }

    private let id: UUID
    private let localTunnel: NWConnectionAppProxyTunnel
    private let connection: NWConnection
    private let route: AppProxyRoute
    private let expectedAuthorization: String
    private let onClose: (UUID) -> Void
    private let stateLock = NSLock()
    private var remoteTunnel: AppProxyByteTunnel?
    private var upstreamTask: Task<Void, Never>?
    private var downstreamTask: Task<Void, Never>?
    private var isFinished = false
}

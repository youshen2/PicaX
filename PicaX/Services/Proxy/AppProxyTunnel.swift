import Foundation
import Network

nonisolated protocol AppProxyByteTunnel: AnyObject, Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

private nonisolated final class ConnectionContinuationState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        let continuation: CheckedContinuation<Value, Error>?
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()
        continuation?.resume(with: result)
        return true
    }
}

nonisolated extension NWConnection {
    func startForAppProxy(timeout: TimeInterval = 15) async throws {
        let state = ConnectionContinuationState<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                stateUpdateHandler = { [weak self] connectionState in
                    switch connectionState {
                    case .ready:
                        self?.stateUpdateHandler = nil
                        state.resolve(.success(()))
                    case .failed(let error):
                        self?.stateUpdateHandler = nil
                        state.resolve(
                            .failure(
                                AppProxyError.connectionFailed(
                                    error.localizedDescription
                                )
                            )
                        )
                    case .cancelled:
                        self?.stateUpdateHandler = nil
                        state.resolve(.failure(AppProxyError.connectionClosed))
                    default:
                        break
                    }
                }
                start(queue: Self.appProxyQueue)
                Self.appProxyQueue.asyncAfter(
                    deadline: .now() + timeout
                ) { [weak self] in
                    if state.resolve(
                        .failure(AppProxyError.connectionTimedOut)
                    ) {
                        self?.cancel()
                    }
                }
            }
        } onCancel: {
            if state.resolve(.failure(CancellationError())) {
                self.cancel()
            }
        }
    }

    func sendForAppProxy(
        _ data: Data,
        timeout: TimeInterval = 20
    ) async throws {
        guard !data.isEmpty else { return }
        let state = ConnectionContinuationState<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                send(
                    content: data,
                    completion: .contentProcessed { error in
                        if let error {
                            state.resolve(
                                .failure(
                                    AppProxyError.connectionFailed(
                                        error.localizedDescription
                                    )
                                )
                            )
                        } else {
                            state.resolve(.success(()))
                        }
                    }
                )
                Self.appProxyQueue.asyncAfter(
                    deadline: .now() + timeout
                ) { [weak self] in
                    if state.resolve(
                        .failure(AppProxyError.connectionTimedOut)
                    ) {
                        self?.cancel()
                    }
                }
            }
        } onCancel: {
            if state.resolve(.failure(CancellationError())) {
                self.cancel()
            }
        }
    }

    func receiveForAppProxy(
        maximumLength: Int = 64 * 1_024,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        let state = ConnectionContinuationState<Data>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                receive(
                    minimumIncompleteLength: 1,
                    maximumLength: maximumLength
                ) { data, _, isComplete, error in
                    if let error {
                        state.resolve(
                            .failure(
                                AppProxyError.connectionFailed(
                                    error.localizedDescription
                                )
                            )
                        )
                    } else if let data, !data.isEmpty {
                        state.resolve(.success(data))
                    } else if isComplete {
                        state.resolve(.success(Data()))
                    } else {
                        state.resolve(.failure(AppProxyError.connectionClosed))
                    }
                }
                Self.appProxyQueue.asyncAfter(
                    deadline: .now() + timeout
                ) { [weak self] in
                    if state.resolve(
                        .failure(AppProxyError.connectionTimedOut)
                    ) {
                        self?.cancel()
                    }
                }
            }
        } onCancel: {
            if state.resolve(.failure(CancellationError())) {
                self.cancel()
            }
        }
    }

    func finishSendingForAppProxy(
        timeout: TimeInterval = 20
    ) async throws {
        let state = ConnectionContinuationState<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                send(
                    content: nil,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if let error {
                            state.resolve(
                                .failure(
                                    AppProxyError.connectionFailed(
                                        error.localizedDescription
                                    )
                                )
                            )
                        } else {
                            state.resolve(.success(()))
                        }
                    }
                )
                Self.appProxyQueue.asyncAfter(
                    deadline: .now() + timeout
                ) { [weak self] in
                    if state.resolve(
                        .failure(AppProxyError.connectionTimedOut)
                    ) {
                        self?.cancel()
                    }
                }
            }
        } onCancel: {
            if state.resolve(.failure(CancellationError())) {
                self.cancel()
            }
        }
    }

    private static let appProxyQueue = DispatchQueue(
        label: "work.picax.app-proxy.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )
}

nonisolated final class NWConnectionAppProxyTunnel:
    AppProxyByteTunnel, @unchecked Sendable {
    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ data: Data) async throws {
        try await connection.sendForAppProxy(data)
    }

    func receive() async throws -> Data {
        if let data = takePendingData() {
            return data
        }
        return try await connection.receiveForAppProxy()
    }

    func finishSending() async throws {
        try await connection.finishSendingForAppProxy()
    }

    func readExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let chunk = try await receive()
            guard !chunk.isEmpty else {
                throw AppProxyError.connectionClosed
            }
            let needed = count - result.count
            if chunk.count <= needed {
                result.append(chunk)
            } else {
                result.append(chunk.prefix(needed))
                prependPending(Data(chunk.dropFirst(needed)))
            }
        }
        return result
    }

    func readThrough(
        _ delimiter: Data,
        maximumLength: Int
    ) async throws -> Data {
        var result = Data()
        while true {
            if let range = result.range(of: delimiter) {
                let end = range.upperBound
                let remainder = Data(result[end...])
                if !remainder.isEmpty {
                    prependPending(remainder)
                }
                return Data(result[..<end])
            }
            guard result.count < maximumLength else {
                throw AppProxyError.invalidProxyResponse
            }
            let chunk = try await receive()
            guard !chunk.isEmpty else {
                throw AppProxyError.connectionClosed
            }
            result.append(chunk)
        }
    }

    func close() {
        connection.cancel()
    }

    private func prependPending(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingLock.lock()
        if pendingData.isEmpty {
            pendingData = data
        } else {
            pendingData = data + pendingData
        }
        pendingLock.unlock()
    }

    private func takePendingData() -> Data? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        guard !pendingData.isEmpty else { return nil }
        let data = pendingData
        pendingData.removeAll(keepingCapacity: true)
        return data
    }

    private let connection: NWConnection
    private let pendingLock = NSLock()
    private var pendingData = Data()
}

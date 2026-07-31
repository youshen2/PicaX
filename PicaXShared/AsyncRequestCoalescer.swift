import Foundation

actor AsyncRequestCoalescer<Value: Sendable> {
    private struct PendingRequest {
        let id: UUID
        let task: Task<Value, Error>
        var waiterIDs: Set<UUID>
    }

    private struct RegisteredRequest {
        let id: UUID
        let task: Task<Value, Error>
    }

    private var pendingRequests: [String: PendingRequest] = [:]

    func value(
        for key: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()

        let waiterID = UUID()
        let request = register(
            key: key,
            waiterID: waiterID,
            operation: operation
        )

        return try await withTaskCancellationHandler {
            defer {
                releaseWaiter(
                    key: key,
                    requestID: request.id,
                    waiterID: waiterID
                )
            }
            let value = try await request.task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    key: key,
                    requestID: request.id,
                    waiterID: waiterID
                )
            }
        }
    }

    private func register(
        key: String,
        waiterID: UUID,
        operation: @escaping @Sendable () async throws -> Value
    ) -> RegisteredRequest {
        if var pending = pendingRequests[key] {
            pending.waiterIDs.insert(waiterID)
            pendingRequests[key] = pending
            return RegisteredRequest(id: pending.id, task: pending.task)
        }

        let requestID = UUID()
        let task = Task(priority: .userInitiated) {
            try await operation()
        }
        pendingRequests[key] = PendingRequest(
            id: requestID,
            task: task,
            waiterIDs: [waiterID]
        )
        return RegisteredRequest(id: requestID, task: task)
    }

    private func cancelWaiter(
        key: String,
        requestID: UUID,
        waiterID: UUID
    ) {
        guard var pending = pendingRequests[key],
              pending.id == requestID,
              pending.waiterIDs.remove(waiterID) != nil else {
            return
        }
        guard pending.waiterIDs.isEmpty else {
            pendingRequests[key] = pending
            return
        }
        pending.task.cancel()
        pendingRequests[key] = nil
    }

    private func releaseWaiter(
        key: String,
        requestID: UUID,
        waiterID: UUID
    ) {
        guard var pending = pendingRequests[key],
              pending.id == requestID,
              pending.waiterIDs.remove(waiterID) != nil else {
            return
        }
        pendingRequests[key] = pending.waiterIDs.isEmpty ? nil : pending
    }
}

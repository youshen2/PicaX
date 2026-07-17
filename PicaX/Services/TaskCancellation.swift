import Foundation

extension Error {
    nonisolated var isTaskCancellation: Bool {
        if self is CancellationError {
            return true
        }

        let error = self as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

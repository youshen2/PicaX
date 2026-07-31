import XCTest
@testable import PicaX

final class AsyncRequestCoalescerTests: XCTestCase {
    func testCancellingOneWaiterKeepsSharedRequestAlive() async throws {
        let coalescer = AsyncRequestCoalescer<Data>()
        let probe = CoalescerProbe()

        let first = Task {
            try await coalescer.value(for: "cover") {
                try await probe.load()
            }
        }
        let second = Task {
            try await coalescer.value(for: "cover") {
                try await probe.load()
            }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        first.cancel()

        do {
            _ = try await first.value
            XCTFail("The cancelled waiter should not receive the shared value.")
        } catch is CancellationError {
            // Expected.
        }

        let secondValue = try await second.value
        let startCount = await probe.startCount
        XCTAssertEqual(secondValue, Data("shared".utf8))
        XCTAssertEqual(startCount, 1)
    }
}

private actor CoalescerProbe {
    private(set) var startCount = 0

    func load() async throws -> Data {
        startCount += 1
        try await Task.sleep(nanoseconds: 120_000_000)
        return Data("shared".utf8)
    }
}

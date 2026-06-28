import Foundation

struct WatchAccountSnapshot: Codable, Equatable {
    var updatedAt: Date
    var localAccount: WatchLocalAccount?
    var localAccountCount: Int
    var platformAccounts: [WatchPlatformAccount]

    var hasSyncedAccounts: Bool {
        localAccount != nil || localAccountCount > 0 || !platformAccounts.isEmpty
    }

    static var empty: WatchAccountSnapshot {
        WatchAccountSnapshot(
            updatedAt: .distantPast,
            localAccount: nil,
            localAccountCount: 0,
            platformAccounts: []
        )
    }
}

struct WatchLocalAccount: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var email: String
    var lastLoginAt: Date?
}

struct WatchPlatformAccount: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var displayName: String
    var credentialState: String
    var loggedInAt: Date
}

enum WatchAccountSyncEnvelope {
    static let messageKindKey = "picax.message.kind"
    static let snapshotDataKey = "picax.accountSnapshot.data"
    static let accountSnapshotKind = "accountSnapshot"
    static let requestSnapshotKind = "requestAccountSnapshot"

    static var requestMessage: [String: Any] {
        [messageKindKey: requestSnapshotKind]
    }

    static func message(for snapshot: WatchAccountSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return [messageKindKey: accountSnapshotKind]
        }
        return [
            messageKindKey: accountSnapshotKind,
            snapshotDataKey: data
        ]
    }

    static func snapshot(from message: [String: Any]) -> WatchAccountSnapshot? {
        guard let data = message[snapshotDataKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchAccountSnapshot.self, from: data)
    }

    static func isSnapshotRequest(_ message: [String: Any]) -> Bool {
        message[messageKindKey] as? String == requestSnapshotKind
    }
}

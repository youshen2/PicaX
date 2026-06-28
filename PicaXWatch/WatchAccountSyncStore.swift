import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchAccountSyncStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchAccountSnapshot
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable = false
    @Published private(set) var lastErrorMessage: String?

    private static let defaultsKey = "picax.watch.accountSnapshot"

    override init() {
        snapshot = Self.loadSnapshot()
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        activationState = session.activationState
        isReachable = session.isReachable

        if session.activationState == .notActivated {
            session.activate()
        } else {
            apply(message: session.receivedApplicationContext)
            requestRefresh()
        }
    }

    func requestRefresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let request = WatchAccountSyncEnvelope.requestMessage

        if session.isReachable {
            session.sendMessage(request) { [weak self] reply in
                Task { @MainActor in
                    self?.apply(message: reply)
                }
            } errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        } else {
            lastErrorMessage = "iPhone 暂不可达，稍后会自动接收同步。"
        }
    }

    private func apply(message: [String: Any]) {
        guard let snapshot = WatchAccountSyncEnvelope.snapshot(from: message) else { return }
        self.snapshot = snapshot
        lastErrorMessage = nil
        persist(snapshot)
    }

    private func persist(_ snapshot: WatchAccountSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadSnapshot() -> WatchAccountSnapshot {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(WatchAccountSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

extension WatchAccountSyncStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = session.isReachable
            self.lastErrorMessage = error?.localizedDescription
            self.apply(message: session.receivedApplicationContext)
            self.requestRefresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                self.requestRefresh()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(message: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message: message)
        }
    }
}

extension WatchAccountSyncStore {
    static var preview: WatchAccountSyncStore {
        let store = WatchAccountSyncStore()
        store.snapshot = WatchAccountSnapshot(
            updatedAt: Date(),
            localAccount: WatchLocalAccount(
                id: UUID(),
                displayName: "PicaX 用户",
                email: "demo@example.com",
                lastLoginAt: Date()
            ),
            localAccountCount: 1,
            platformAccounts: [
                WatchPlatformAccount(
                    id: "picacg",
                    title: "PicACG",
                    displayName: "Demo",
                    credentialState: "已保存",
                    loggedInAt: Date()
                )
            ]
        )
        return store
    }
}

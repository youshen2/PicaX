#if os(iOS)
import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchAccountSyncService: NSObject, ObservableObject {
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var lastErrorMessage: String?

    private var latestSnapshot = WatchAccountSnapshot.empty

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        } else {
            activationState = session.activationState
        }
    }

    func sync(accountService: AccountService, platformAccountService: PlatformAccountService) {
        sync(snapshot: WatchAccountSnapshot(accountService: accountService, platformAccountService: platformAccountService))
    }

    func sync(snapshot: WatchAccountSnapshot) {
        latestSnapshot = snapshot
        activate()
        sendLatestSnapshot()
    }

    private func sendLatestSnapshot() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let message = WatchAccountSyncEnvelope.message(for: latestSnapshot)

        do {
            try session.updateApplicationContext(message)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension PhoneWatchAccountSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.lastErrorMessage = error?.localizedDescription
            self.sendLatestSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard WatchAccountSyncEnvelope.isSnapshotRequest(message) else { return }
        Task { @MainActor in
            self.sendLatestSnapshot()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard WatchAccountSyncEnvelope.isSnapshotRequest(message) else {
            replyHandler([:])
            return
        }

        Task { @MainActor in
            let reply = WatchAccountSyncEnvelope.message(for: self.latestSnapshot)
            replyHandler(reply)
            self.sendLatestSnapshot()
        }
    }
}

private extension WatchAccountSnapshot {
    init(accountService: AccountService, platformAccountService: PlatformAccountService) {
        let currentAccount = accountService.currentAccount.map {
            WatchLocalAccount(
                id: $0.id,
                displayName: $0.displayName,
                email: $0.email,
                lastLoginAt: $0.lastLoginAt
            )
        }

        let platformAccounts = ComicPlatform.allCases.compactMap { platform -> WatchPlatformAccount? in
            guard let account = platformAccountService.account(for: platform) else { return nil }
            return WatchPlatformAccount(
                id: platform.id,
                title: platform.title,
                displayName: account.displayName,
                credentialState: account.credential.summaryText,
                loggedInAt: account.loggedInAt
            )
        }

        self.init(
            updatedAt: Date(),
            localAccount: currentAccount,
            localAccountCount: accountService.accounts.count,
            platformAccounts: platformAccounts
        )
    }
}
#endif

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

    func sync(platformAccountService: PlatformAccountService, syncsLocalFavorites: Bool) {
        sync(snapshot: WatchAccountSnapshot(
            platformAccountService: platformAccountService,
            syncsLocalFavorites: syncsLocalFavorites
        ))
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
        Task { @MainActor in
            if WatchAccountSyncEnvelope.isSnapshotRequest(message) {
                self.sendLatestSnapshot()
            } else if WatchAccountSyncEnvelope.isLocalFavoritesSync(message) {
                self.mergeLocalFavorites(from: message)
                self.sendLatestSnapshot()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if WatchAccountSyncEnvelope.isSnapshotRequest(message) {
                let reply = WatchAccountSyncEnvelope.message(for: self.latestSnapshot)
                replyHandler(reply)
                self.sendLatestSnapshot()
            } else if WatchAccountSyncEnvelope.isLocalFavoritesSync(message) {
                self.mergeLocalFavorites(from: message)
                let reply = WatchAccountSyncEnvelope.message(for: self.latestSnapshot)
                replyHandler(reply)
                self.sendLatestSnapshot()
            } else {
                replyHandler([:])
            }
        }
    }

    private func mergeLocalFavorites(from message: [String: Any]) {
        guard WatchConnectivitySettings.syncsLocalFavorites() else {
            latestSnapshot.localFavorites = []
            latestSnapshot.updatedAt = Date()
            return
        }
        guard let incoming = WatchAccountSyncEnvelope.localFavorites(from: message) else { return }
        let deletions = WatchAccountSyncEnvelope.localFavoriteDeletions(from: message)
        var deletionMap: [String: Date] = [:]
        for deletion in deletions {
            if let old = deletionMap[deletion.syncID] {
                deletionMap[deletion.syncID] = max(old, deletion.deletedAt)
            } else {
                deletionMap[deletion.syncID] = deletion.deletedAt
            }
        }

        let existing = PicaXSQLiteStore.loadLocalFavorites(folderID: "default")
        let incomingFavorites = incoming.compactMap(StoredLocalFavorite.init)
        var merged: [String: StoredLocalFavorite] = [:]

        for favorite in existing + incomingFavorites {
            if let deletedAt = deletionMap[favorite.syncID],
               deletedAt >= (favorite.favoriteDate ?? .distantPast) {
                merged.removeValue(forKey: favorite.syncID)
                continue
            }
            if let old = merged[favorite.syncID] {
                merged[favorite.syncID] = favorite.isNewer(than: old) ? favorite : old
            } else {
                merged[favorite.syncID] = favorite
            }
        }

        PicaXSQLiteStore.replaceLocalFavorites(Array(merged.values), folderID: "default")
        latestSnapshot.localFavorites = PicaXSQLiteStore.loadLocalFavorites(folderID: "default").map(WatchLocalFavoriteItem.init)
        latestSnapshot.updatedAt = Date()
    }
}

private extension WatchAccountSnapshot {
    init(platformAccountService: PlatformAccountService, syncsLocalFavorites: Bool) {
        let localFavorites = syncsLocalFavorites ? PicaXSQLiteStore.loadLocalFavorites(folderID: "default").map(WatchLocalFavoriteItem.init) : []
        let platformAccounts = ComicPlatform.allCases.compactMap { platform -> WatchPlatformAccount? in
            guard let account = platformAccountService.account(for: platform) else { return nil }
            return WatchPlatformAccount(
                id: platform.id,
                platformID: platform.id,
                title: platform.title,
                username: account.username,
                displayName: account.displayName,
                credentialState: account.credential.summaryText,
                credential: WatchPlatformCredential(account.credential),
                loggedInAt: account.loggedInAt
            )
        }
        self.init(updatedAt: Date(), platformAccounts: platformAccounts, localFavorites: localFavorites)
    }
}

private extension WatchPlatformCredential {
    nonisolated init(_ credential: PlatformCredential) {
        self.init(
            token: credential.token,
            refreshToken: credential.refreshToken,
            tokenType: credential.tokenType,
            password: credential.password,
            cookies: credential.cookies.map(WatchStoredHTTPCookie.init),
            userAgent: credential.userAgent,
            baseURL: credential.baseURL,
            source: credential.source.rawValue,
            profile: credential.profile.map(WatchPlatformAccountProfile.init)
        )
    }
}

private extension WatchStoredHTTPCookie {
    nonisolated init(_ cookie: StoredHTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure
        )
    }
}

private extension WatchPlatformAccountProfile {
    nonisolated init(_ profile: PlatformAccountProfile) {
        self.init(email: profile.email, username: profile.username, nickname: profile.nickname)
    }
}

private extension WatchLocalFavoriteItem {
    init(_ favorite: StoredLocalFavorite) {
        self.init(
            id: favorite.id,
            platformID: favorite.platform.id,
            title: favorite.title,
            subtitle: favorite.subtitle,
            coverURLString: favorite.coverURLString,
            tags: favorite.tags,
            pageCount: favorite.pageCount,
            likesCount: favorite.likesCount,
            favoriteDate: favorite.favoriteDate
        )
    }
}

private extension StoredLocalFavorite {
    var syncID: String {
        "\(platform.id)-\(id)"
    }

    init?(_ favorite: WatchLocalFavoriteItem) {
        guard let platform = ComicPlatform(rawValue: favorite.platformID) else { return nil }
        self.init(
            item: ComicListItem(
                id: favorite.id,
                platform: platform,
                title: favorite.title,
                subtitle: favorite.subtitle,
                coverURLString: favorite.coverURLString,
                tags: favorite.tags,
                pageCount: favorite.pageCount,
                likesCount: favorite.likesCount,
                favoriteDate: favorite.favoriteDate
            ),
            favoriteDate: favorite.favoriteDate
        )
    }

    func isNewer(than other: StoredLocalFavorite) -> Bool {
        (favoriteDate ?? .distantPast) >= (other.favoriteDate ?? .distantPast)
    }
}
#endif

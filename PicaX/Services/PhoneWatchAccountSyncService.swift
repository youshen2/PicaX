#if os(iOS)
import Combine
import Foundation
import WatchConnectivity

nonisolated private final class WatchConnectivityReply: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func send(_ message: [String: Any]) {
        handler(message)
    }
}

@MainActor
final class PhoneWatchAccountSyncService: NSObject, ObservableObject {
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var lastErrorMessage: String?

    private var latestSnapshot = WatchAccountSnapshot.empty
    private var syncTask: Task<Void, Never>?
    private let syncStateStore = PhoneWatchSyncStateStore()

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

    func sync(
        platformAccountService: PlatformAccountService,
        syncsLocalFavorites: Bool,
        syncsReadLater: Bool,
        syncsReadingHistory: Bool
    ) {
        let accounts = platformAccountService.accounts
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                let snapshot = try await Task.detached(priority: .utility) {
                    try WatchAccountSnapshot(
                        accounts: accounts,
                        syncsLocalFavorites: syncsLocalFavorites,
                        syncsReadLater: syncsReadLater,
                        syncsReadingHistory: syncsReadingHistory
                    )
                }.value
                try Task.checkCancellation()
                self?.sync(snapshot: snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func sync(snapshot: WatchAccountSnapshot) {
        latestSnapshot = reconciled(snapshot)
        activate()
        sendLatestSnapshot()
    }

    private func sendLatestSnapshot() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard canSendSnapshot(to: session) else { return }

        let message = WatchAccountSyncEnvelope.message(for: latestSnapshot)

        do {
            try session.updateApplicationContext(message)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func canSendSnapshot(to session: WCSession) -> Bool {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return false
        }
        return true
    }
}

extension PhoneWatchAccountSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let errorMessage = error?.localizedDescription
        Task { @MainActor in
            self.activationState = activationState
            self.lastErrorMessage = errorMessage
            self.sendLatestSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let message = WatchAccountSyncEnvelope.receivedMessage(from: message)
        Task { @MainActor in
            if WatchAccountSyncEnvelope.isSnapshotRequest(message) {
                self.sendLatestSnapshot()
            } else if WatchAccountSyncEnvelope.isLocalFavoritesSync(message) {
                self.mergeLocalFavorites(from: message)
                self.sendLatestSnapshot()
            } else if WatchAccountSyncEnvelope.isReadLaterSync(message) {
                self.mergeReadLater(from: message)
                self.sendLatestSnapshot()
            } else if WatchAccountSyncEnvelope.isReadingHistorySync(message) {
                self.mergeReadingHistory(from: message)
                self.sendLatestSnapshot()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let message = WatchAccountSyncEnvelope.receivedMessage(from: message)
        let reply = WatchConnectivityReply(replyHandler)
        Task { @MainActor in
            if WatchAccountSyncEnvelope.isSnapshotRequest(message) {
                reply.send(WatchAccountSyncEnvelope.message(for: self.latestSnapshot))
            } else if WatchAccountSyncEnvelope.isLocalFavoritesSync(message) {
                self.mergeLocalFavorites(from: message)
                reply.send(WatchAccountSyncEnvelope.message(for: self.latestSnapshot))
            } else if WatchAccountSyncEnvelope.isReadLaterSync(message) {
                self.mergeReadLater(from: message)
                reply.send(WatchAccountSyncEnvelope.message(for: self.latestSnapshot))
            } else if WatchAccountSyncEnvelope.isReadingHistorySync(message) {
                self.mergeReadingHistory(from: message)
                reply.send(WatchAccountSyncEnvelope.message(for: self.latestSnapshot))
            } else {
                reply.send([:])
            }
        }
    }

    private func mergeLocalFavorites(from message: WatchAccountSyncMessage) {
        guard WatchConnectivitySettings.syncsLocalFavorites() else {
            latestSnapshot.localFavorites = []
            latestSnapshot.localFavoriteDeletions = []
            latestSnapshot.updatedAt = Date()
            return
        }
        guard let incoming = WatchAccountSyncEnvelope.localFavorites(from: message) else { return }
        do {
            let current = try PicaXSQLiteStore.loadLocalFavoritesOrThrow(folderID: "default")
                .map(WatchLocalFavoriteItem.init)
            let result = syncStateStore.reconcileLocalFavorites(
                current: current,
                incoming: incoming,
                incomingDeletions: WatchAccountSyncEnvelope.localFavoriteDeletions(from: message)
            )
            try PicaXSQLiteStore.replaceLocalFavoritesOrThrow(
                result.items.compactMap(StoredLocalFavorite.init),
                folderID: "default"
            )
            syncStateStore.commitLocalFavorites(result)
            latestSnapshot.localFavorites = result.items
            latestSnapshot.localFavoriteDeletions = result.deletions
            latestSnapshot.updatedAt = Date()
            lastErrorMessage = nil
            NotificationCenter.default.post(name: .picaxLocalFavoritesDidChange, object: nil)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func mergeReadLater(from message: WatchAccountSyncMessage) {
        guard WatchConnectivitySettings.syncsReadLater() else {
            latestSnapshot.readLater = []
            latestSnapshot.readLaterDeletions = []
            latestSnapshot.updatedAt = Date()
            return
        }
        guard let incoming = WatchAccountSyncEnvelope.readLater(from: message) else { return }
        do {
            let current = try PicaXSQLiteStore.loadReadLaterOrThrow().map(WatchReadLaterItem.init)
            let result = syncStateStore.reconcileReadLater(
                current: current,
                incoming: incoming,
                incomingDeletions: WatchAccountSyncEnvelope.readLaterDeletions(from: message)
            )
            try PicaXSQLiteStore.replaceReadLaterOrThrow(
                result.items.compactMap(ReadLaterRecord.init)
            )
            syncStateStore.commitReadLater(result)
            latestSnapshot.readLater = result.items
            latestSnapshot.readLaterDeletions = result.deletions
            latestSnapshot.updatedAt = Date()
            lastErrorMessage = nil
            NotificationCenter.default.post(name: .picaxReadLaterDidChange, object: nil)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func mergeReadingHistory(from message: WatchAccountSyncMessage) {
        guard WatchConnectivitySettings.syncsReadingHistory() else {
            latestSnapshot.readingHistory = []
            latestSnapshot.readingHistoryDeletions = []
            latestSnapshot.updatedAt = Date()
            return
        }
        guard let incoming = WatchAccountSyncEnvelope.readingHistory(from: message) else {
            return
        }
        do {
            let current = try PicaXSQLiteStore.loadReadingHistoryOrThrow()
                .map(WatchReadingHistoryRecord.init)
            let result = syncStateStore.reconcileReadingHistory(
                current: current,
                incoming: incoming,
                incomingDeletions: WatchAccountSyncEnvelope.readingHistoryDeletions(from: message)
            )
            try PicaXSQLiteStore.replaceReadingHistoryOrThrow(
                result.items.compactMap(ReadingHistoryRecord.init)
            )
            syncStateStore.commitReadingHistory(result)
            latestSnapshot.readingHistory = result.items
            latestSnapshot.readingHistoryDeletions = result.deletions
            latestSnapshot.updatedAt = Date()
            lastErrorMessage = nil
            NotificationCenter.default.post(name: .picaxReadingHistoryDidChange, object: nil)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func reconciled(_ snapshot: WatchAccountSnapshot) -> WatchAccountSnapshot {
        var snapshot = snapshot
        if WatchConnectivitySettings.syncsLocalFavorites() {
            let result = syncStateStore.reconcileLocalFavorites(current: snapshot.localFavorites)
            syncStateStore.commitLocalFavorites(result)
            snapshot.localFavorites = result.items
            snapshot.localFavoriteDeletions = result.deletions
        } else {
            snapshot.localFavorites = []
            snapshot.localFavoriteDeletions = []
        }
        if WatchConnectivitySettings.syncsReadLater() {
            let result = syncStateStore.reconcileReadLater(current: snapshot.readLater)
            syncStateStore.commitReadLater(result)
            snapshot.readLater = result.items
            snapshot.readLaterDeletions = result.deletions
        } else {
            snapshot.readLater = []
            snapshot.readLaterDeletions = []
        }
        if WatchConnectivitySettings.syncsReadingHistory() {
            let result = syncStateStore.reconcileReadingHistory(current: snapshot.readingHistory)
            syncStateStore.commitReadingHistory(result)
            snapshot.readingHistory = result.items
            snapshot.readingHistoryDeletions = result.deletions
        } else {
            snapshot.readingHistory = []
            snapshot.readingHistoryDeletions = []
        }
        snapshot.updatedAt = Date()
        return snapshot
    }
}

private extension WatchAccountSnapshot {
    nonisolated init(
        accounts: [ComicPlatform: PlatformAccount],
        syncsLocalFavorites: Bool,
        syncsReadLater: Bool,
        syncsReadingHistory: Bool
    ) throws {
        let localFavorites = syncsLocalFavorites
            ? try PicaXSQLiteStore.loadLocalFavoritesOrThrow(folderID: "default")
                .map(WatchLocalFavoriteItem.init)
            : []
        let readLater = syncsReadLater
            ? try PicaXSQLiteStore.loadReadLaterOrThrow().map(WatchReadLaterItem.init)
            : []
        let readingHistory = syncsReadingHistory
            ? try PicaXSQLiteStore.loadReadingHistoryOrThrow().map(WatchReadingHistoryRecord.init)
            : []
        let platformAccounts = ComicPlatform.allCases.compactMap { platform -> WatchPlatformAccount? in
            guard let account = accounts[platform] else { return nil }
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
        self.init(
            updatedAt: Date(),
            platformAccounts: platformAccounts,
            localFavorites: localFavorites,
            readLater: readLater,
            readingHistory: readingHistory
        )
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
    nonisolated init(_ favorite: StoredLocalFavorite) {
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

}

private extension WatchReadLaterItem {
    nonisolated init(_ record: ReadLaterRecord) {
        self.init(
            id: record.item.id,
            platformID: record.item.platform.id,
            title: record.item.title,
            subtitle: record.item.subtitle,
            coverURLString: record.item.coverURLString,
            tags: record.item.tags,
            pageCount: record.item.pageCount,
            likesCount: record.item.likesCount,
            addedAt: record.addedAt
        )
    }
}

private extension ReadLaterRecord {
    init?(_ item: WatchReadLaterItem) {
        guard let platform = ComicPlatform(rawValue: item.platformID) else { return nil }
        self.init(
            item: ComicListItem(
                id: item.id,
                platform: platform,
                title: item.title,
                subtitle: item.subtitle,
                coverURLString: item.coverURLString,
                tags: item.tags,
                pageCount: item.pageCount,
                likesCount: item.likesCount,
                favoriteDate: nil
            ),
            addedAt: item.addedAt
        )
    }

}

private extension WatchReadingHistoryRecord {
    nonisolated init(_ record: ReadingHistoryRecord) {
        let progress = record.progress
        self.init(
            comicID: record.item.id,
            platformID: record.item.platform.id,
            title: record.item.title,
            subtitle: record.item.subtitle,
            coverURLString: record.item.coverURLString,
            tags: record.item.tags,
            pageCount: record.item.pageCount,
            favoriteDate: record.item.favoriteDate,
            viewedAt: record.viewedAt,
            progress: WatchReadingProgress(
                chapterIndex: progress?.chapterIndex ?? 0,
                pageIndex: progress?.pageIndex ?? 0,
                totalPages: progress?.totalPages ?? record.item.pageCount ?? 0,
                totalChapters: progress?.totalChapters ?? 1
            )
        )
    }
}

private extension ReadingHistoryRecord {
    init?(_ record: WatchReadingHistoryRecord) {
        guard let platform = ComicPlatform(rawValue: record.platformID) else { return nil }
        let reachedChapterEnd = record.progress.totalPages > 0
            && record.progress.pageIndex >= record.progress.totalPages - 1
        let reachedBookEnd = reachedChapterEnd
            && record.progress.chapterIndex >= max(record.progress.totalChapters - 1, 0)
        self.init(
            item: ComicListItem(
                id: record.comicID,
                platform: platform,
                title: record.title,
                subtitle: record.subtitle,
                coverURLString: record.coverURLString ?? "",
                tags: record.tags,
                pageCount: record.pageCount,
                likesCount: nil,
                favoriteDate: record.favoriteDate
            ),
            viewedAt: record.viewedAt,
            progress: ReadingProgress(
                status: reachedBookEnd ? .finished : .reading,
                chapterIndex: max(record.progress.chapterIndex, 0),
                pageIndex: max(record.progress.pageIndex, 0),
                totalPages: max(record.progress.totalPages, 0),
                totalChapters: max(record.progress.totalChapters, 1),
                readChapterIndexes: reachedChapterEnd ? [max(record.progress.chapterIndex, 0)] : [],
                updatedAt: record.viewedAt
            )
        )
    }
}
#endif

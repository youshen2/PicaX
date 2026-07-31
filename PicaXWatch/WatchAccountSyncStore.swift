import Combine
import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class WatchAccountSyncStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchAccountSnapshot
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable = false
    @Published private(set) var lastErrorMessage: String?

    private static let defaultsKey = "picax.watch.accountSnapshot"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PicaXWatch",
        category: "AccountSync"
    )
    private let localFavoritesStore = WatchLocalFavoritesStore()
    private let readLaterStore = WatchReadLaterStore()
    private let readingHistoryStore = WatchReadingHistoryStore()
    private var readingHistorySyncTask: Task<Void, Never>?

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
            apply(
                message: WatchAccountSyncEnvelope.receivedMessage(
                    from: session.receivedApplicationContext
                )
            )
            requestRefresh()
        }
    }

    func requestRefresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let request = WatchAccountSyncEnvelope.requestMessage

        if session.isReachable {
            session.sendMessage(request) { [weak self] reply in
                let message = WatchAccountSyncEnvelope.receivedMessage(from: reply)
                Task { @MainActor in
                    self?.apply(message: message)
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

    func addLocalFavorite(_ item: WatchComicItem) {
        let favorites = localFavoritesStore.add(item)
        snapshot.localFavorites = favorites
        snapshot.localFavoriteDeletions = localFavoritesStore.loadDeletions()
        persist(snapshot)
        syncLocalFavorites(favorites)
    }

    func removeLocalFavorite(_ item: WatchComicItem) {
        let favorites = localFavoritesStore.remove(item)
        snapshot.localFavorites = favorites
        snapshot.localFavoriteDeletions = localFavoritesStore.loadDeletions()
        persist(snapshot)
        syncLocalFavorites(favorites)
    }

    func isLocalFavorite(_ item: WatchComicItem) -> Bool {
        localFavoritesStore.contains(item)
    }

    func addReadLater(_ item: WatchComicItem) {
        let records = readLaterStore.add(item)
        snapshot.readLater = records
        snapshot.readLaterDeletions = readLaterStore.loadDeletions()
        persist(snapshot)
        syncReadLater(records)
    }

    func removeReadLater(_ item: WatchComicItem) {
        let records = readLaterStore.remove(item)
        snapshot.readLater = records
        snapshot.readLaterDeletions = readLaterStore.loadDeletions()
        persist(snapshot)
        syncReadLater(records)
    }

    func isReadLater(_ item: WatchComicItem) -> Bool {
        readLaterStore.contains(item)
    }

    func syncReadingHistory(_ records: [WatchReadingHistoryRecord]? = nil) {
        readingHistorySyncTask?.cancel()
        readingHistorySyncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.sendReadingHistory(records)
        }
    }

    private func sendReadingHistory(_ records: [WatchReadingHistoryRecord]?) {
        guard WCSession.isSupported() else { return }
        let message = WatchAccountSyncEnvelope.message(
            forReadingHistory: records ?? readingHistoryStore.load(),
            deletions: readingHistoryStore.loadDeletions()
        )
        let session = WCSession.default
        guard session.isReachable else {
            lastErrorMessage = "iPhone 暂不可达，阅读记录会在下次同步时合并。"
            return
        }
        session.sendMessage(message) { [weak self] reply in
            let message = WatchAccountSyncEnvelope.receivedMessage(from: reply)
            Task { @MainActor in
                self?.apply(message: message)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func syncLocalFavorites(_ favorites: [WatchLocalFavoriteItem]? = nil) {
        guard WCSession.isSupported() else { return }
        let localFavorites = favorites ?? localFavoritesStore.load()
        let message = WatchAccountSyncEnvelope.message(
            forLocalFavorites: localFavorites,
            deletions: localFavoritesStore.loadDeletions()
        )
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                let message = WatchAccountSyncEnvelope.receivedMessage(from: reply)
                Task { @MainActor in
                    self?.apply(message: message)
                }
            } errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        } else {
            lastErrorMessage = "iPhone 暂不可达，本地收藏会在下次同步时合并。"
        }
    }

    func syncReadLater(_ records: [WatchReadLaterItem]? = nil) {
        guard WCSession.isSupported() else { return }
        let readLater = records ?? readLaterStore.load()
        let message = WatchAccountSyncEnvelope.message(
            forReadLater: readLater,
            deletions: readLaterStore.loadDeletions()
        )
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                let message = WatchAccountSyncEnvelope.receivedMessage(from: reply)
                Task { @MainActor in
                    self?.apply(message: message)
                }
            } errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        } else {
            lastErrorMessage = "iPhone 暂不可达，稍后再读会在下次同步时合并。"
        }
    }

    private func apply(message: WatchAccountSyncMessage) {
        guard let snapshot = WatchAccountSyncEnvelope.snapshot(from: message) else { return }
        var mergedSnapshot = snapshot
        mergedSnapshot.localFavorites = localFavoritesStore.merge(
            snapshot.localFavorites,
            deletions: snapshot.localFavoriteDeletions
        )
        mergedSnapshot.localFavoriteDeletions = localFavoritesStore.loadDeletions()
        mergedSnapshot.readLater = readLaterStore.merge(
            snapshot.readLater,
            deletions: snapshot.readLaterDeletions
        )
        mergedSnapshot.readLaterDeletions = readLaterStore.loadDeletions()
        mergedSnapshot.readingHistory = readingHistoryStore.merge(
            snapshot.readingHistory,
            deletions: snapshot.readingHistoryDeletions
        )
        mergedSnapshot.readingHistoryDeletions = readingHistoryStore.loadDeletions()
        self.snapshot = mergedSnapshot
        lastErrorMessage = nil
        persist(mergedSnapshot)
    }

    private func persist(_ snapshot: WatchAccountSnapshot) {
        do {
            let securedSnapshot = try WatchPlatformCredentialVault.secure(snapshot)
            let data = try JSONEncoder().encode(securedSnapshot)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            lastErrorMessage = error.localizedDescription
            Self.logger.error("Persisting account snapshot failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func loadSnapshot() -> WatchAccountSnapshot {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return .empty
        }
        do {
            let persistedSnapshot = try JSONDecoder().decode(WatchAccountSnapshot.self, from: data)
            var loadedSnapshot = try WatchPlatformCredentialVault.hydrate(persistedSnapshot)
            let localFavoritesStore = WatchLocalFavoritesStore()
            loadedSnapshot.localFavoriteDeletions = localFavoritesStore.mergeDeletions(
                persistedSnapshot.localFavoriteDeletions
            )
            loadedSnapshot.localFavorites = localFavoritesStore.merge(
                persistedSnapshot.localFavorites,
                deletions: loadedSnapshot.localFavoriteDeletions
            )
            let readLaterStore = WatchReadLaterStore()
            loadedSnapshot.readLaterDeletions = readLaterStore.mergeDeletions(
                persistedSnapshot.readLaterDeletions
            )
            loadedSnapshot.readLater = readLaterStore.merge(
                persistedSnapshot.readLater,
                deletions: loadedSnapshot.readLaterDeletions
            )
            let readingHistoryStore = WatchReadingHistoryStore()
            loadedSnapshot.readingHistoryDeletions = readingHistoryStore.mergeDeletions(
                persistedSnapshot.readingHistoryDeletions
            )
            loadedSnapshot.readingHistory = readingHistoryStore.merge(
                persistedSnapshot.readingHistory,
                deletions: loadedSnapshot.readingHistoryDeletions
            )
            if persistedSnapshot.platformAccounts.contains(where: \.credential.hasSensitiveData) {
                let secured = try WatchPlatformCredentialVault.secure(loadedSnapshot)
                UserDefaults.standard.set(try JSONEncoder().encode(secured), forKey: defaultsKey)
            }
            return loadedSnapshot
        } catch {
            logger.error("Loading account snapshot failed: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }
}

extension WatchAccountSyncStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let isReachable = session.isReachable
        let errorMessage = error?.localizedDescription
        let message = WatchAccountSyncEnvelope.receivedMessage(
            from: session.receivedApplicationContext
        )
        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = isReachable
            self.lastErrorMessage = errorMessage
            self.apply(message: message)
            self.requestRefresh()
            self.syncLocalFavorites()
            self.syncReadLater()
            self.syncReadingHistory()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.isReachable = isReachable
            if isReachable {
                self.requestRefresh()
                self.syncLocalFavorites()
                self.syncReadLater()
                self.syncReadingHistory()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let message = WatchAccountSyncEnvelope.receivedMessage(from: applicationContext)
        Task { @MainActor in
            self.apply(message: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let message = WatchAccountSyncEnvelope.receivedMessage(from: message)
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
            platformAccounts: [
                WatchPlatformAccount(
                    id: "picacg",
                    platformID: "picacg",
                    title: "PicACG",
                    username: "demo@example.com",
                    displayName: "Demo",
                    credentialState: "已保存",
                    credential: WatchPlatformCredential(
                        token: "preview-token",
                        refreshToken: nil,
                        tokenType: nil,
                        password: nil,
                        cookies: [],
                        userAgent: nil,
                        baseURL: "https://picaapi.picacomic.com",
                        source: "api",
                        profile: WatchPlatformAccountProfile(email: "demo@example.com", username: "demo", nickname: "Demo")
                    ),
                    loggedInAt: Date()
                )
            ],
            localFavorites: [
                WatchLocalFavoriteItem(
                    id: "preview-favorite",
                    platformID: "picacg",
                    title: "本地收藏示例",
                    subtitle: "保存在当前手表",
                    coverURLString: "",
                    tags: ["Preview"],
                    pageCount: nil,
                    likesCount: nil,
                    favoriteDate: Date()
                )
            ],
            readLater: [
                WatchReadLaterItem(
                    id: "preview-read-later",
                    platformID: "picacg",
                    title: "稍后再读示例",
                    subtitle: "从 iPhone 同步",
                    coverURLString: "",
                    tags: ["Preview"],
                    pageCount: nil,
                    likesCount: nil,
                    addedAt: Date()
                )
            ]
        )
        return store
    }
}

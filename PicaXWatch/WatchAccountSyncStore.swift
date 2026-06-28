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
    private let localFavoritesStore = WatchLocalFavoritesStore()

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

    func addLocalFavorite(_ item: WatchComicItem) {
        let favorites = localFavoritesStore.add(item)
        snapshot.localFavorites = favorites
        persist(snapshot)
        syncLocalFavorites(favorites)
    }

    func removeLocalFavorite(_ item: WatchComicItem) {
        let favorites = localFavoritesStore.remove(item)
        snapshot.localFavorites = favorites
        persist(snapshot)
        syncLocalFavorites(favorites)
    }

    func isLocalFavorite(_ item: WatchComicItem) -> Bool {
        localFavoritesStore.contains(item)
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
                Task { @MainActor in
                    self?.apply(message: reply)
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

    private func apply(message: [String: Any]) {
        guard let snapshot = WatchAccountSyncEnvelope.snapshot(from: message) else { return }
        var mergedSnapshot = snapshot
        mergedSnapshot.localFavorites = localFavoritesStore.merge(snapshot.localFavorites)
        self.snapshot = mergedSnapshot
        lastErrorMessage = nil
        persist(mergedSnapshot)
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
        var loadedSnapshot = snapshot
        loadedSnapshot.localFavorites = WatchLocalFavoritesStore().merge(snapshot.localFavorites)
        return loadedSnapshot
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
            self.syncLocalFavorites()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                self.requestRefresh()
                self.syncLocalFavorites()
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
            ]
        )
        return store
    }
}

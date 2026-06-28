import Foundation

extension WatchAccountSnapshot {
    func account(for platform: WatchComicPlatform) -> WatchPlatformAccount? {
        platformAccounts.first { $0.platformID == platform.id }
    }
}

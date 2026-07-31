import Foundation

enum WatchPlatformCredentialVault {
    private nonisolated static let service = "PicaXWatch.PlatformCredentials.v1"

    nonisolated static func secure(_ snapshot: WatchAccountSnapshot) throws -> WatchAccountSnapshot {
        var secured = snapshot
        let activePlatformIDs = Set(snapshot.platformAccounts.map(\.platformID))

        for platform in WatchComicPlatform.allCases where !activePlatformIDs.contains(platform.id) {
            try SecureCodableStore.delete(
                service: service,
                account: platform.id
            )
        }

        secured.platformAccounts = try snapshot.platformAccounts.map { account in
            var persisted = account
            if account.credential.hasSensitiveData {
                try SecureCodableStore.save(
                    account.credential.secrets,
                    service: service,
                    account: account.platformID
                )
            } else {
                try SecureCodableStore.delete(
                    service: service,
                    account: account.platformID
                )
            }
            persisted.credential = account.credential.removingSecrets()
            return persisted
        }
        return secured
    }

    nonisolated static func hydrate(_ snapshot: WatchAccountSnapshot) throws -> WatchAccountSnapshot {
        var hydrated = snapshot
        hydrated.platformAccounts = try snapshot.platformAccounts.map { account in
            var value = account
            if account.credential.hasSensitiveData {
                try SecureCodableStore.save(
                    account.credential.secrets,
                    service: service,
                    account: account.platformID
                )
                return value
            }
            if let secrets = try SecureCodableStore.load(
                WatchPlatformCredentialSecrets.self,
                service: service,
                account: account.platformID
            ) {
                value.credential = account.credential.applying(secrets)
            }
            return value
        }
        return hydrated
    }
}

import Foundation

enum PlatformCredentialVault {
    private nonisolated static let service = "PicaX.PlatformCredentials.v1"

    nonisolated static func persist(_ account: PlatformAccount) throws -> PlatformAccount {
        if account.credential.hasSensitiveData {
            try SecureCodableStore.save(
                account.credential.secrets,
                service: service,
                account: account.platform.id
            )
        } else {
            try SecureCodableStore.delete(service: service, account: account.platform.id)
        }

        var persistedAccount = account
        persistedAccount.credential = account.credential.removingSecrets()
        return persistedAccount
    }

    nonisolated static func persistPreservingExistingSecrets(
        _ account: PlatformAccount
    ) throws -> PlatformAccount {
        if account.credential.hasSensitiveData {
            try SecureCodableStore.save(
                account.credential.secrets,
                service: service,
                account: account.platform.id
            )
        }

        var persistedAccount = account
        persistedAccount.credential = account.credential.removingSecrets()
        return persistedAccount
    }

    nonisolated static func delete(platform: ComicPlatform) throws {
        try SecureCodableStore.delete(service: service, account: platform.id)
    }

    nonisolated static func secrets(
        for platform: ComicPlatform
    ) throws -> PlatformCredentialSecrets? {
        try SecureCodableStore.load(
            PlatformCredentialSecrets.self,
            service: service,
            account: platform.id
        )
    }

    nonisolated static func restore(
        _ secrets: PlatformCredentialSecrets?,
        for platform: ComicPlatform
    ) throws {
        if let secrets {
            try SecureCodableStore.save(
                secrets,
                service: service,
                account: platform.id
            )
        } else {
            try delete(platform: platform)
        }
    }
}

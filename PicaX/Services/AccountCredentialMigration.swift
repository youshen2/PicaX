import Foundation

nonisolated enum PlatformCredentialMigrationError: LocalizedError {
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .rollbackFailed:
            "账号凭据迁移失败，且无法完整恢复迁移前的 Keychain 状态。"
        }
    }
}

enum PlatformCredentialMigration {
    static let legacyAccountsKey = "picax.platformAccounts"

    struct Dependencies {
        var loadPersistedAccounts: () throws -> [PlatformAccount]
        var persistRedactedAccounts: ([PlatformAccount]) throws -> Void
        var loadSecrets: (ComicPlatform) throws -> PlatformCredentialSecrets?
        var restoreSecrets: (PlatformCredentialSecrets?, ComicPlatform) throws -> Void
    }

    static func migrate(
        defaults: UserDefaults = .standard,
        dependencies: Dependencies
    ) throws -> [PlatformAccount] {
        let persistedAccounts = try dependencies.loadPersistedAccounts()
        let legacyPayload = defaults.data(forKey: legacyAccountsKey)
        let legacyAccounts = legacyPayload.flatMap(decodeLegacyAccounts)
        let platforms = platformsPresent(
            persistedAccounts: persistedAccounts,
            legacyAccounts: legacyAccounts ?? []
        )
        let previousSecrets = try Dictionary(
            uniqueKeysWithValues: platforms.map {
                ($0, try dependencies.loadSecrets($0))
            }
        )
        let resolutions = resolve(
            persistedAccounts: persistedAccounts,
            legacyAccounts: legacyAccounts ?? [],
            existingSecrets: previousSecrets
        )
        let needsPersistence = persistedAccounts.contains {
            $0.credential.hasSensitiveData
        } || legacyAccounts != nil

        if needsPersistence {
            let changedSecrets = resolutions.filter {
                $0.secrets != (previousSecrets[$0.account.platform] ?? nil)
            }
            var appliedSecretChanges: [Resolution] = []
            do {
                for resolution in changedSecrets {
                    try dependencies.restoreSecrets(
                        resolution.secrets,
                        resolution.account.platform
                    )
                    appliedSecretChanges.append(resolution)
                }
                try dependencies.persistRedactedAccounts(
                    resolutions.map(\.redactedAccount)
                )
            } catch {
                let operationError = error
                var didFailRollback = false
                for resolution in appliedSecretChanges.reversed() {
                    do {
                        try dependencies.restoreSecrets(
                            previousSecrets[resolution.account.platform] ?? nil,
                            resolution.account.platform
                        )
                    } catch {
                        didFailRollback = true
                    }
                }
                if didFailRollback {
                    throw PlatformCredentialMigrationError.rollbackFailed
                }
                throw operationError
            }
        }

        if legacyAccounts != nil {
            defaults.removeObject(forKey: legacyAccountsKey)
        }
        return resolutions.map(\.account)
    }

    static func fallbackAccounts(
        persistedAccounts: [PlatformAccount],
        defaults: UserDefaults,
        loadSecrets: (ComicPlatform) throws -> PlatformCredentialSecrets?
    ) -> [PlatformAccount] {
        let legacyAccounts = defaults.data(forKey: legacyAccountsKey)
            .flatMap(decodeLegacyAccounts) ?? []
        let platforms = platformsPresent(
            persistedAccounts: persistedAccounts,
            legacyAccounts: legacyAccounts
        )
        var existingSecrets: [ComicPlatform: PlatformCredentialSecrets?] = [:]
        for platform in platforms {
            existingSecrets[platform] = try? loadSecrets(platform)
        }
        return resolve(
            persistedAccounts: persistedAccounts,
            legacyAccounts: legacyAccounts,
            existingSecrets: existingSecrets
        )
        .map(\.account)
    }

    private static func decodeLegacyAccounts(_ data: Data) -> [PlatformAccount]? {
        try? JSONDecoder().decode([PlatformAccount].self, from: data)
    }

    private static func platformsPresent(
        persistedAccounts: [PlatformAccount],
        legacyAccounts: [PlatformAccount]
    ) -> [ComicPlatform] {
        let values = Set(
            persistedAccounts.map(\.platform) + legacyAccounts.map(\.platform)
        )
        return ComicPlatform.onlinePlatforms.filter(values.contains)
    }

    private static func resolve(
        persistedAccounts: [PlatformAccount],
        legacyAccounts: [PlatformAccount],
        existingSecrets: [ComicPlatform: PlatformCredentialSecrets?]
    ) -> [Resolution] {
        let persistedByPlatform = newestAccountsByPlatform(persistedAccounts)
        let legacyByPlatform = newestAccountsByPlatform(legacyAccounts)

        return ComicPlatform.onlinePlatforms.compactMap { platform in
            let persisted = persistedByPlatform[platform]
            let legacy = legacyByPlatform[platform]
            guard let metadataAccount = preferredMetadata(
                persisted: persisted,
                legacy: legacy
            ) else {
                return nil
            }

            let secrets: PlatformCredentialSecrets?
            if let persisted, persisted.credential.hasSensitiveData {
                secrets = persisted.credential.secrets
            } else if let existing = existingSecrets[platform] ?? nil {
                secrets = existing
            } else if let legacy, legacy.credential.hasSensitiveData {
                secrets = legacy.credential.secrets
            } else {
                secrets = nil
            }

            var redactedAccount = metadataAccount
            redactedAccount.credential = metadataAccount.credential.removingSecrets()
            var hydratedAccount = redactedAccount
            if let secrets {
                hydratedAccount.credential = redactedAccount.credential.applying(secrets)
            }
            return Resolution(
                account: hydratedAccount,
                redactedAccount: redactedAccount,
                secrets: secrets
            )
        }
    }

    private static func newestAccountsByPlatform(
        _ accounts: [PlatformAccount]
    ) -> [ComicPlatform: PlatformAccount] {
        accounts.reduce(into: [:]) { result, account in
            guard let existing = result[account.platform] else {
                result[account.platform] = account
                return
            }
            if account.loggedInAt > existing.loggedInAt {
                result[account.platform] = account
            }
        }
    }

    private static func preferredMetadata(
        persisted: PlatformAccount?,
        legacy: PlatformAccount?
    ) -> PlatformAccount? {
        switch (persisted, legacy) {
        case (.none, .none):
            nil
        case (.some(let persisted), .none):
            persisted
        case (.none, .some(let legacy)):
            legacy
        case (.some(let persisted), .some(let legacy)):
            legacy.loggedInAt > persisted.loggedInAt ? legacy : persisted
        }
    }

    private struct Resolution {
        var account: PlatformAccount
        var redactedAccount: PlatformAccount
        var secrets: PlatformCredentialSecrets?
    }
}

nonisolated enum LegacyLocalAccountCredentialMigrationError: LocalizedError {
    case verificationFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            "旧版本地账号凭据写入 Keychain 后校验失败。"
        case .rollbackFailed:
            "旧版本地账号凭据迁移失败，且无法完整恢复迁移前的 Keychain 状态。"
        }
    }
}

enum LegacyLocalAccountCredentialMigration {
    static let accountsDefaultsKey = "picax.accounts"
    static let sessionDefaultsKey = "picax.session"

    struct Dependencies {
        var loadSecureData: (String) throws -> Data?
        var restoreSecureData: (Data?, String) throws -> Void
    }

    static func migrate(
        defaults: UserDefaults = .standard,
        dependencies: Dependencies
    ) throws {
        let payloads = items.compactMap { item -> (Item, Data)? in
            guard let data = defaults.data(forKey: item.defaultsKey) else {
                return nil
            }
            return (item, data)
        }
        guard !payloads.isEmpty else { return }

        let previousValues = try Dictionary(
            uniqueKeysWithValues: payloads.map {
                ($0.0.keychainAccount, try dependencies.loadSecureData($0.0.keychainAccount))
            }
        )
        var appliedItems: [Item] = []
        do {
            for (item, data) in payloads {
                try dependencies.restoreSecureData(data, item.keychainAccount)
                appliedItems.append(item)
                guard try dependencies.loadSecureData(item.keychainAccount) == data else {
                    throw LegacyLocalAccountCredentialMigrationError.verificationFailed
                }
            }
        } catch {
            let operationError = error
            var didFailRollback = false
            for item in appliedItems.reversed() {
                do {
                    try dependencies.restoreSecureData(
                        previousValues[item.keychainAccount] ?? nil,
                        item.keychainAccount
                    )
                } catch {
                    didFailRollback = true
                }
            }
            if didFailRollback {
                throw LegacyLocalAccountCredentialMigrationError.rollbackFailed
            }
            throw operationError
        }

        for (item, _) in payloads {
            defaults.removeObject(forKey: item.defaultsKey)
        }
    }

    private static let items = [
        Item(defaultsKey: accountsDefaultsKey, keychainAccount: "accounts"),
        Item(defaultsKey: sessionDefaultsKey, keychainAccount: "session")
    ]

    private struct Item {
        var defaultsKey: String
        var keychainAccount: String
    }
}

enum LegacyLocalAccountCredentialVault {
    private nonisolated static let service = "PicaX.LegacyLocalAccountCredentials.v1"

    nonisolated static func data(account: String) throws -> Data? {
        try SecureCodableStore.load(
            Data.self,
            service: service,
            account: account
        )
    }

    nonisolated static func restore(_ data: Data?, account: String) throws {
        if let data {
            try SecureCodableStore.save(
                data,
                service: service,
                account: account
            )
        } else {
            try SecureCodableStore.delete(service: service, account: account)
        }
    }
}

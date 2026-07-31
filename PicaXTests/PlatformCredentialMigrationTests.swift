import XCTest
@testable import PicaX

@MainActor
final class PlatformCredentialMigrationTests: XCTestCase {
    func testMigratesFirstVersionUserDefaultsPasswordAndRemovesPlaintext() throws {
        let isolatedDefaults = try makeDefaults()
        let defaults = isolatedDefaults.value
        defer { isolatedDefaults.remove() }
        let loggedInAt = Date(timeIntervalSince1970: 1_000)
        let legacy = LegacyPasswordAccount(
            platform: .picacg,
            username: "reader@example.com",
            password: "legacy-password",
            loggedInAt: loggedInAt
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: PlatformCredentialMigration.legacyAccountsKey)
        let probe = MigrationProbe()

        let accounts = try PlatformCredentialMigration.migrate(
            defaults: defaults,
            dependencies: probe.dependencies
        )

        XCTAssertNil(defaults.data(forKey: PlatformCredentialMigration.legacyAccountsKey))
        XCTAssertEqual(accounts.first?.credential.password, "legacy-password")
        XCTAssertEqual(probe.secrets[.picacg]?.password, "legacy-password")
        XCTAssertEqual(probe.persistedAccounts.first?.username, "reader@example.com")
        XCTAssertFalse(probe.persistedAccounts.first?.credential.hasSensitiveData ?? true)
        XCTAssertEqual(probe.persistCallCount, 1)

        let secondAccounts = try PlatformCredentialMigration.migrate(
            defaults: defaults,
            dependencies: probe.dependencies
        )
        XCTAssertEqual(secondAccounts.first?.credential.password, "legacy-password")
        XCTAssertEqual(probe.persistCallCount, 1)
    }

    func testMigratesPlaintextSQLiteCredentialToKeychainStorage() throws {
        let isolatedDefaults = try makeDefaults()
        let defaults = isolatedDefaults.value
        defer { isolatedDefaults.remove() }
        let credential = PlatformCredential(
            token: "access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            password: nil,
            cookies: [
                StoredHTTPCookie(
                    name: "session",
                    value: "cookie-secret",
                    domain: ".example.com"
                )
            ],
            userAgent: "PicaX Tests",
            baseURL: "https://example.com",
            source: .api,
            profile: nil
        )
        let probe = MigrationProbe(
            persistedAccounts: [
                PlatformAccount(
                    platform: .nhentai,
                    username: "reader",
                    credential: credential,
                    loggedInAt: Date(timeIntervalSince1970: 2_000)
                )
            ]
        )

        let accounts = try PlatformCredentialMigration.migrate(
            defaults: defaults,
            dependencies: probe.dependencies
        )

        XCTAssertEqual(accounts.first?.credential.token, "access-token")
        XCTAssertEqual(accounts.first?.credential.cookies.first?.value, "cookie-secret")
        XCTAssertEqual(probe.secrets[.nhentai], credential.secrets)
        XCTAssertFalse(probe.persistedAccounts.first?.credential.hasSensitiveData ?? true)
    }

    func testPersistenceFailureRollsBackKeychainAndKeepsLegacyPayload() throws {
        let isolatedDefaults = try makeDefaults()
        let defaults = isolatedDefaults.value
        defer { isolatedDefaults.remove() }
        let legacy = LegacyPasswordAccount(
            platform: .jmComic,
            username: "reader",
            password: "secret",
            loggedInAt: Date(timeIntervalSince1970: 3_000)
        )
        let payload = try JSONEncoder().encode([legacy])
        defaults.set(payload, forKey: PlatformCredentialMigration.legacyAccountsKey)
        let probe = MigrationProbe(failsPersistence: true)

        XCTAssertThrowsError(
            try PlatformCredentialMigration.migrate(
                defaults: defaults,
                dependencies: probe.dependencies
            )
        )

        XCTAssertEqual(
            defaults.data(forKey: PlatformCredentialMigration.legacyAccountsKey),
            payload
        )
        XCTAssertNil(probe.secrets[.jmComic])
        XCTAssertTrue(probe.persistedAccounts.isEmpty)
    }

    func testMigratesDeprecatedLocalAccountAndSessionPayloads() throws {
        let isolatedDefaults = try makeDefaults()
        let defaults = isolatedDefaults.value
        defer { isolatedDefaults.remove() }
        let accountsData = Data("legacy-accounts".utf8)
        let sessionData = Data("legacy-session-token".utf8)
        defaults.set(
            accountsData,
            forKey: LegacyLocalAccountCredentialMigration.accountsDefaultsKey
        )
        defaults.set(
            sessionData,
            forKey: LegacyLocalAccountCredentialMigration.sessionDefaultsKey
        )
        let probe = LegacyLocalAccountMigrationProbe()

        try LegacyLocalAccountCredentialMigration.migrate(
            defaults: defaults,
            dependencies: probe.dependencies
        )

        XCTAssertNil(
            defaults.data(
                forKey: LegacyLocalAccountCredentialMigration.accountsDefaultsKey
            )
        )
        XCTAssertNil(
            defaults.data(
                forKey: LegacyLocalAccountCredentialMigration.sessionDefaultsKey
            )
        )
        XCTAssertEqual(probe.values["accounts"], accountsData)
        XCTAssertEqual(probe.values["session"], sessionData)
    }

    private func makeDefaults() throws -> IsolatedDefaults {
        let suiteName = "PlatformCredentialMigrationTests.\(UUID().uuidString)"
        return IsolatedDefaults(
            suiteName: suiteName,
            value: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
    }
}

private struct IsolatedDefaults {
    let suiteName: String
    let value: UserDefaults

    func remove() {
        value.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class MigrationProbe {
    enum ProbeError: Error {
        case persistenceFailed
    }

    var persistedAccounts: [PlatformAccount]
    var secrets: [ComicPlatform: PlatformCredentialSecrets]
    var persistCallCount = 0
    var failsPersistence: Bool

    init(
        persistedAccounts: [PlatformAccount] = [],
        secrets: [ComicPlatform: PlatformCredentialSecrets] = [:],
        failsPersistence: Bool = false
    ) {
        self.persistedAccounts = persistedAccounts
        self.secrets = secrets
        self.failsPersistence = failsPersistence
    }

    var dependencies: PlatformCredentialMigration.Dependencies {
        PlatformCredentialMigration.Dependencies(
            loadPersistedAccounts: {
                self.persistedAccounts
            },
            persistRedactedAccounts: { accounts in
                self.persistCallCount += 1
                guard !self.failsPersistence else {
                    throw ProbeError.persistenceFailed
                }
                self.persistedAccounts = accounts
            },
            loadSecrets: { platform in
                self.secrets[platform]
            },
            restoreSecrets: { secrets, platform in
                self.secrets[platform] = secrets
            }
        )
    }
}

@MainActor
private final class LegacyLocalAccountMigrationProbe {
    var values: [String: Data] = [:]

    var dependencies: LegacyLocalAccountCredentialMigration.Dependencies {
        LegacyLocalAccountCredentialMigration.Dependencies(
            loadSecureData: { account in
                self.values[account]
            },
            restoreSecureData: { data, account in
                self.values[account] = data
            }
        )
    }
}

private struct LegacyPasswordAccount: Encodable {
    let platform: ComicPlatform
    let username: String
    let password: String
    let loggedInAt: Date
}

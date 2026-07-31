import Combine
import Foundation

@MainActor
final class PlatformAccountService: ObservableObject {
    @Published private(set) var accounts: [ComicPlatform: PlatformAccount]

    init(defaults: UserDefaults = .standard) {
        accounts = PicaXSQLiteStore.loadPlatformAccounts(defaults: defaults)
    }

    var loggedInAccounts: [PlatformAccount] {
        ComicPlatform.allCases.compactMap { accounts[$0] }
    }

    func account(for platform: ComicPlatform) -> PlatformAccount? {
        accounts[platform]
    }

    func isLoggedIn(_ platform: ComicPlatform) -> Bool {
        accounts[platform] != nil
    }

    func saveValidatedAccount(_ account: PlatformAccount) throws {
        try PicaXSQLiteStore.upsertPlatformAccountOrThrow(account)
        accounts[account.platform] = account
    }

    func logout(platform: ComicPlatform) throws {
        try PicaXSQLiteStore.deletePlatformAccountOrThrow(platform: platform)
        accounts[platform] = nil
    }

    func reloadFromDefaults() {
        accounts = PicaXSQLiteStore.loadPlatformAccounts()
    }
}

enum PlatformAccountError: LocalizedError, Equatable {
    case emptyUsername
    case emptyPassword
    case emptyCredential

    var errorDescription: String? {
        switch self {
        case .emptyUsername:
            "请输入账号"
        case .emptyPassword:
            "请输入密码"
        case .emptyCredential:
            "登录成功后没有取得可保存的登录信息"
        }
    }
}

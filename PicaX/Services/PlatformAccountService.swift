import Combine
import Foundation

@MainActor
final class PlatformAccountService: ObservableObject {
    @Published private(set) var accounts: [ComicPlatform: PlatformAccount]

    init() {
        accounts = PicaXSQLiteStore.loadPlatformAccounts()
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

    func saveValidatedAccount(_ account: PlatformAccount) {
        accounts[account.platform] = account
        PicaXSQLiteStore.upsertPlatformAccount(account)
    }

    func logout(platform: ComicPlatform) {
        accounts[platform] = nil
        PicaXSQLiteStore.deletePlatformAccount(platform: platform)
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

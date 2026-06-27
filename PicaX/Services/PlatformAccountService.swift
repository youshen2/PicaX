import Combine
import Foundation

@MainActor
final class PlatformAccountService: ObservableObject {
    private enum Key {
        static let accounts = "picax.platformAccounts"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    @Published private(set) var accounts: [ComicPlatform: PlatformAccount]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accounts = Self.loadAccounts(defaults: defaults, decoder: decoder)
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
        save()
    }

    func logout(platform: ComicPlatform) {
        accounts[platform] = nil
        save()
    }

    func reloadFromDefaults() {
        accounts = Self.loadAccounts(defaults: defaults, decoder: decoder)
    }

    private func save() {
        let orderedAccounts = ComicPlatform.allCases.compactMap { accounts[$0] }
        guard let data = try? encoder.encode(orderedAccounts) else { return }
        defaults.set(data, forKey: Key.accounts)
    }

    private static func loadAccounts(defaults: UserDefaults, decoder: JSONDecoder) -> [ComicPlatform: PlatformAccount] {
        guard let data = defaults.data(forKey: Key.accounts),
              let values = try? decoder.decode([PlatformAccount].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.platform, $0) })
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

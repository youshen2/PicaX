import Foundation

struct AccountStore {
    private enum Key {
        static let accounts = "picax.accounts"
        static let session = "picax.session"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAccounts() -> [UserAccount] {
        guard let data = defaults.data(forKey: Key.accounts) else { return [] }
        return (try? decoder.decode([UserAccount].self, from: data)) ?? []
    }

    func saveAccounts(_ accounts: [UserAccount]) {
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: Key.accounts)
    }

    func loadSession() -> AccountSession? {
        guard let data = defaults.data(forKey: Key.session) else { return nil }
        return try? decoder.decode(AccountSession.self, from: data)
    }

    func saveSession(_ session: AccountSession?) {
        guard let session else {
            defaults.removeObject(forKey: Key.session)
            return
        }
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: Key.session)
    }
}

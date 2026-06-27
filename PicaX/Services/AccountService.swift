import CryptoKit
import Combine
import Foundation

@MainActor
final class AccountService: ObservableObject {
    private let store: AccountStore

    @Published private(set) var accounts: [UserAccount]
    @Published private(set) var session: AccountSession?
    @Published private(set) var currentAccount: UserAccount?

    init(store: AccountStore? = nil) {
        let store = store ?? AccountStore()
        self.store = store
        accounts = store.loadAccounts()
        session = store.loadSession()
        restoreSession()
    }

    var isLoggedIn: Bool {
        currentAccount != nil
    }

    @discardableResult
    func register(email: String, username: String, password: String) throws -> UserAccount {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw AccountError.invalidEmail
        }
        guard normalizedUsername.count >= 2 else {
            throw AccountError.invalidUsername
        }
        guard password.count >= 6 else {
            throw AccountError.weakPassword
        }
        guard !accounts.contains(where: { $0.email.lowercased() == normalizedEmail }) else {
            throw AccountError.duplicateEmail
        }

        let salt = UUID().uuidString
        let account = UserAccount(
            id: UUID(),
            email: normalizedEmail,
            username: normalizedUsername,
            passwordHash: hash(password: password, salt: salt),
            salt: salt,
            createdAt: Date(),
            lastLoginAt: nil
        )
        accounts.append(account)
        store.saveAccounts(accounts)
        signIn(account)
        return account
    }

    func login(email: String, password: String) throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = accounts.firstIndex(where: { $0.email.lowercased() == normalizedEmail }) else {
            throw AccountError.accountNotFound
        }

        let account = accounts[index]
        guard account.passwordHash == hash(password: password, salt: account.salt) else {
            throw AccountError.invalidPassword
        }

        accounts[index].lastLoginAt = Date()
        store.saveAccounts(accounts)
        signIn(accounts[index])
    }

    func logout() {
        session = nil
        currentAccount = nil
        store.saveSession(nil)
    }

    func reloadFromStore() {
        accounts = store.loadAccounts()
        session = store.loadSession()
        restoreSession()
    }

    func deleteCurrentAccount() throws {
        guard let currentAccount else {
            throw AccountError.noActiveSession
        }
        accounts.removeAll { $0.id == currentAccount.id }
        store.saveAccounts(accounts)
        logout()
    }

    func updateProfile(username: String) throws {
        guard let currentAccount else {
            throw AccountError.noActiveSession
        }
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedUsername.count >= 2 else {
            throw AccountError.invalidUsername
        }
        guard let index = accounts.firstIndex(where: { $0.id == currentAccount.id }) else {
            throw AccountError.accountNotFound
        }

        accounts[index].username = normalizedUsername
        self.currentAccount = accounts[index]
        store.saveAccounts(accounts)
    }

    private func restoreSession() {
        guard let session else {
            currentAccount = nil
            return
        }
        currentAccount = accounts.first { $0.id == session.accountID }
        if currentAccount == nil {
            self.session = nil
            store.saveSession(nil)
        }
    }

    private func signIn(_ account: UserAccount) {
        let newSession = AccountSession(
            accountID: account.id,
            token: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            issuedAt: Date()
        )
        session = newSession
        currentAccount = account
        store.saveSession(newSession)
    }

    private func hash(password: String, salt: String) -> String {
        let input = Data("\(salt):\(password)".utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

struct UserAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var email: String
    var username: String
    var passwordHash: String
    var salt: String
    var createdAt: Date
    var lastLoginAt: Date?

    var displayName: String {
        username.isEmpty ? email : username
    }
}

struct AccountSession: Codable, Equatable {
    var accountID: UUID
    var token: String
    var issuedAt: Date
}

enum AccountError: LocalizedError, Equatable {
    case invalidEmail
    case invalidUsername
    case weakPassword
    case duplicateEmail
    case accountNotFound
    case invalidPassword
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "请输入有效邮箱"
        case .invalidUsername:
            "昵称至少需要 2 个字符"
        case .weakPassword:
            "密码至少需要 6 个字符"
        case .duplicateEmail:
            "该邮箱已经注册"
        case .accountNotFound:
            "账号不存在"
        case .invalidPassword:
            "密码不正确"
        case .noActiveSession:
            "当前没有登录账号"
        }
    }
}

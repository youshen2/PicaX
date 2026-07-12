import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var accountService: AccountService
    @State private var mode: AuthenticationMode = .login
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var message: String?

    var body: some View {
        PicaxNavigationContainer {
            ScrollView {
                VStack(spacing: 28) {
                    AuthHeaderView(mode: mode)

                    VStack(spacing: 14) {
                        TextField("邮箱", text: $email)
                            .textContentType(.emailAddress)
                            .picaxKeyboardType(.emailAddress)
                            .picaxDisablesTextAutocapitalization()
                            .autocorrectionDisabled()
                            .formFieldStyle()

                        if mode == .register {
                            TextField("昵称", text: $username)
                                .textContentType(.nickname)
                                .formFieldStyle()
                        }

                        SecureField("密码", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                            .formFieldStyle()

                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            Text(mode.primaryActionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            withAnimation {
                                message = nil
                                mode.toggle()
                            }
                        } label: {
                            Text(mode.secondaryActionTitle)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.groupedBackground)
            .navigationTitle(mode.navigationTitle)
        }
    }

    private func submit() {
        do {
            switch mode {
            case .login:
                try accountService.login(email: email, password: password)
            case .register:
                try accountService.register(email: email, username: username, password: password)
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private enum AuthenticationMode {
    case login
    case register

    var navigationTitle: String {
        switch self {
        case .login:
            "登录"
        case .register:
            "注册"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .login:
            "登录"
        case .register:
            "创建账号"
        }
    }

    var secondaryActionTitle: String {
        switch self {
        case .login:
            "还没有账号？去注册"
        case .register:
            "已有账号？去登录"
        }
    }

    mutating func toggle() {
        self = self == .login ? .register : .login
    }
}

private struct AuthHeaderView: View {
    let mode: AuthenticationMode

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                .font(.system(size: 68))
                .foregroundStyle(.tint)
            Text(mode == .login ? "欢迎回来" : "创建 PicaX 账号")
                .font(.title.bold())
            Text("账号会保存在本机，后续可以把 Service 层替换为真实接口。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
    }
}

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
            .environmentObject(AccountService(store: AccountStore(defaults: .preview)))
    }
}

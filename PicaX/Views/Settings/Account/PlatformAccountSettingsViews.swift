import SwiftUI

struct PlatformAccountsSettingsView: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    var body: some View {
        List {
            Section("平台") {
                ForEach(ComicPlatform.onlinePlatforms) { platform in
                    NavigationLink {
                        PlatformLoginView(platform: platform)
                    } label: {
                        PlatformAccountRow(
                            platform: platform,
                            account: platformAccounts.account(for: platform)
                        )
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle("平台账号")
        .picaxHidesTabBar()
    }
}

struct PlatformLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    let platform: ComicPlatform
    private let service = ComicContentService()

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoggingIn = false

    private var supportsPasswordLogin: Bool {
        switch platform {
        case .picacg, .jmComic, .htManga:
            true
        case .nhentai, .eHentai, .hitomi, .local:
            false
        }
    }

    var body: some View {
        List {
            if supportsPasswordLogin {
                Section {
                    TextField(platform.loginHint, text: $username)
                        .textContentType(.username)
                        .disabled(isLoggingIn)

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .disabled(isLoggingIn)
                } header: {
                    Text("登录信息")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        Text("应用会保存必要的登录信息，用来下次继续使用。")
                    }
                }
            }

            if let account = platformAccounts.account(for: platform) {
                Section("当前状态") {
                    SettingsValueRow(title: "账号", value: account.displayName)
                    SettingsValueRow(title: "登录状态", value: account.credential.summaryText)
                    SettingsValueRow(
                        title: "登录时间",
                        value: account.loggedInAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Section {
                NavigationLink {
                    HomeComicSourceFeaturePage(
                        platform: platform,
                        service: service,
                        showsAccountSection: false
                    )
                } label: {
                    Label("漫画源设置", systemImage: "slider.horizontal.3")
                }
            }

            Section {
                if supportsPasswordLogin {
                    Button(action: beginLogin) {
                        if isLoggingIn {
                            HStack {
                                ProgressView()
                                Text("正在验证")
                            }
                        } else {
                            Label(
                                platformAccounts.isLoggedIn(platform) ? "重新登录" : "登录",
                                systemImage: "arrow.right.circle"
                            )
                        }
                    }
                    .disabled(isLoggingIn)
                }

                if platform.loginWebsite != nil {
                    NavigationLink {
                        PlatformWebLoginPage(platform: platform)
                    } label: {
                        Label("通过网页登录", systemImage: "safari")
                    }
                }

                if platformAccounts.isLoggedIn(platform) {
                    Button("退出登录", role: .destructive, action: logout)
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .navigationTitle(platform.title)
        .picaxHidesTabBar()
        .onAppear(perform: populateUsername)
    }

    private func beginLogin() {
        Task {
            await login()
        }
    }

    private func populateUsername() {
        guard let account = platformAccounts.account(for: platform) else { return }
        username = account.username
    }

    private func logout() {
        do {
            try platformAccounts.logout(platform: platform)
            username = ""
            password = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func login() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil

        do {
            let account = try await service.validateLogin(
                platform: platform,
                username: username,
                password: password
            )
            try platformAccounts.saveValidatedAccount(account)
            password = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingIn = false
    }
}

private struct PlatformAccountRow: View {
    let platform: ComicPlatform
    let account: PlatformAccount?

    var body: some View {
        HStack {
            Label(platform.title, systemImage: platform.systemImage)
                .foregroundStyle(platform.accentColor, .primary)

            Spacer()

            if account != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(platform.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(account.map { "已登录，\($0.displayName)" } ?? "未登录")
    }
}

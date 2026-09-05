import SwiftUI

struct ProxyServerSettingsPage: View {
    @EnvironmentObject private var settings: AppProxySettings

    @State private var proxyType: AppProxyProtocol = .http
    @State private var host = ""
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var shareLink = ""
    @State private var feedback: Feedback?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section(
                header: Text("外部代理服务器"),
                footer: Text(
                    "此处仅配置现成的 HTTP、HTTPS 或 SOCKS5 代理服务器。"
                )
            ) {
                Picker("协议", selection: $proxyType) {
                    ForEach(AppProxyProtocol.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("主机名或 IP", text: $host)
                    .picaxKeyboardType(.url)
                    .picaxDisablesTextAutocapitalization()
                    .disableAutocorrection(true)

                TextField("端口", text: $port)
                    .picaxKeyboardType(.numberPad)
            }

            Section(
                header: Text("认证"),
                footer: Text("不需要认证时，将用户名和密码同时留空。")
            ) {
                TextField("用户名（可选）", text: $username)
                    .picaxDisablesTextAutocapitalization()
                    .disableAutocorrection(true)
                SecureField("密码（可选）", text: $password)

            }

            Section(
                header: Text("导入服务器链接"),
                footer: Text(
                    "支持 http://、https://、socks5:// 和 socks5h://；"
                        + "链接只在本机解析。"
                )
            ) {
                TextField(
                    "协议://用户:密码@主机:端口",
                    text: $shareLink
                )
                .picaxKeyboardType(.url)
                .picaxDisablesTextAutocapitalization()
                .disableAutocorrection(true)

                Button("读取链接") {
                    importShareLink()
                }
                .disabled(
                    shareLink.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }

            Section {
                Button("保存并切换到代理服务器") {
                    save()
                }

                Button {
                    Task { await testProxyServer() }
                } label: {
                    if isTesting {
                        HStack {
                            ProgressView()
                            Text("正在测试")
                        }
                    } else {
                        Text("测试已保存的代理服务器")
                    }
                }
                .disabled(
                    settings.appProxyConfiguration == nil || isTesting
                )
            }

            if let feedback {
                Section("结果") {
                    Label(
                        feedback.message,
                        systemImage: feedback.isError
                            ? "exclamationmark.triangle"
                            : "checkmark.circle"
                    )
                    .foregroundColor(
                        feedback.isError ? .red : .green
                    )
                }
            }

            Section(
                header: Text("协议说明"),
                footer: Text(
                    "HTTPS 表示应用与代理服务器之间使用 TLS；目标网站的 HTTPS 证书仍会单独校验。"
                )
            ) {
                SettingsValueRow(title: "HTTP / HTTPS", value: "CONNECT")
                SettingsValueRow(title: "SOCKS5", value: "TCP CONNECT")
            }
        }
        .picaxHidesTabBar()
        .navigationTitle("代理服务器")
        .picaxNavigationBarTitleDisplayModeInline()
        .onAppear(perform: loadSavedConfiguration)
    }

    private func loadSavedConfiguration() {
        guard let configuration = settings.appProxyConfiguration else {
            if port.isEmpty {
                port = String(proxyType.defaultPort)
            }
            return
        }
        proxyType = configuration.type
        host = configuration.host
        port = String(configuration.port)
        let credentials = settings.appProxyCredentials()
        username = credentials.username
        password = credentials.password
    }

    private func save() {
        do {
            try settings.applyAppProxyConfiguration(
                type: proxyType,
                host: host,
                port: port,
                username: username,
                password: password
            )
            loadSavedConfiguration()
            feedback = Feedback(
                message: "代理服务器已保存，并已切换到该路由。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func importShareLink() {
        do {
            let (configuration, credentials) =
                try AppProxyConfigurationParser.parseShareLink(
                    shareLink
                )
            proxyType = configuration.type
            host = configuration.host
            port = String(configuration.port)
            username = credentials.username
            password = credentials.password
            shareLink = ""
            feedback = Feedback(
                message: "链接已读取，请检查后保存。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func testProxyServer() async {
        isTesting = true
        feedback = nil
        defer { isTesting = false }
        do {
            guard settings.appProxyConfiguration != nil else {
                throw AppProxyError.configurationMissing
            }
            let statusCode = try await AppProxyConnectionTester.test(
                route: settings.networkRouteForProxyServer(),
                targetURL: try settings.connectionCheckURL()
            )
            feedback = Feedback(
                message: "连接成功（HTTP \(statusCode)）。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private struct Feedback {
        let message: String
        let isError: Bool
    }
}

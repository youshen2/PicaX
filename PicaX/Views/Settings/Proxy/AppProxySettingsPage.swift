import SwiftUI

struct AppProxySettingsPage: View {
    @ObservedObject var settings: AppProxySettings
    @AppStorage("settings.network.retryCount") private var retryCount = 2

    @State private var feedback: Feedback?
    @State private var isTesting = false
    @State private var confirmingDirect = false

    var body: some View {
        Form {
            Section(
                header: Text("请求方式"),
                footer: Text(
                    "平台接口、漫画图片及漫画下载使用所选线路。"
                        + "内置代理可导入 Clash YAML 并选择节点。"
                )
            ) {
                ForEach(AppNetworkRoutingMode.allCases) { mode in
                    routeButton(mode)
                }
            }

            Section(
                header: Text("配置"),
                footer: Text(
                    "两套配置彼此独立。保存代理服务器不会修改已导入的 YAML 节点。"
                )
            ) {
                NavigationLink {
                    ProxyServerSettingsPage(settings: settings)
                } label: {
                    configurationRow(
                        title: "代理服务器",
                        systemImage: "server.rack",
                        value: proxyServerSummary
                    )
                }

                NavigationLink {
                    BuiltInProxySettingsPage(settings: settings)
                } label: {
                    configurationRow(
                        title: "内置代理",
                        systemImage: "shippingbox",
                        value: builtInProxySummary
                    )
                }
            }

            Section {
                TextField("HTTPS 连通性检查地址", text: $settings.connectionCheckURLText)
                    .picaxKeyboardType(.url)
                    .picaxDisablesTextAutocapitalization()
                    .autocorrectionDisabled()
                Button {
                    Task { await testCurrentRoute() }
                } label: {
                    if isTesting {
                        HStack {
                            ProgressView()
                            Text("正在测试当前路由")
                        }
                    } else {
                        Text("测试当前路由")
                    }
                }
                .disabled(!settings.appProxyEnabled || isTesting)
            }

            Section("连接") {
                IntegerSettingsInputRow(
                    title: "失败重试", value: $retryCount,
                    unit: "次", lowerBound: 0, upperBound: 5
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
        }
        .picaxHidesTabBar()
        .navigationTitle("网络与代理")
        .picaxNavigationBarTitleDisplayModeInline()
        .alert("切换为直连？", isPresented: $confirmingDirect) {
            Button("取消", role: .cancel) {}
            Button("改用直连", role: .destructive) {
                applyMode(.direct)
            }
        } message: {
            Text(
                "切换后，平台与图片服务器将能看到你的真实出口 IP。"
            )
        }
    }

    private func routeButton(
        _ mode: AppNetworkRoutingMode
    ) -> some View {
        Button {
            if mode == .direct, settings.appProxyEnabled {
                confirmingDirect = true
            } else {
                applyMode(mode)
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .foregroundColor(.primary)
                    Text(mode.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if settings.appNetworkRoutingMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .accessibilityLabel("已选择")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func configurationRow(
        title: String,
        systemImage: String,
        value: String
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var proxyServerSummary: String {
        guard let configuration = settings.appProxyConfiguration else {
            return "未配置"
        }
        return "\(configuration.type.displayName) · \(configuration.displayAddress)"
    }

    private var builtInProxySummary: String {
        if let profile = settings.selectedBuiltInProxyProfile {
            return profile.name
        }
        let count = settings.appBuiltInProxyProfiles.count
        return count == 0 ? "未导入" : "\(count) 个节点"
    }

    private func applyMode(_ mode: AppNetworkRoutingMode) {
        do {
            try settings.setNetworkRoutingMode(mode)
            feedback = Feedback(
                message: "已切换为\(mode.displayName)。",
                isError: false
            )
        } catch {
            feedback = Feedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func testCurrentRoute() async {
        isTesting = true
        feedback = nil
        defer { isTesting = false }
        do {
            let statusCode = try await AppProxyConnectionTester.test(
                route: settings.appNetworkRoute(),
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

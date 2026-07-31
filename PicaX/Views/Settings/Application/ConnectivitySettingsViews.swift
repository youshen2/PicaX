import SwiftUI

struct WatchConnectivitySettingsView: View {
    @AppStorage(WatchConnectivitySettingsKey.syncsReadingHistory) private var syncsReadingHistory = true
    @AppStorage(WatchConnectivitySettingsKey.syncsLocalFavorites) private var syncsLocalFavorites = true
    @AppStorage(WatchConnectivitySettingsKey.syncsReadLater) private var syncsReadLater = true

    var body: some View {
        List {
            Section {
                Toggle("阅读记录同步", isOn: $syncsReadingHistory)
                Toggle("本地收藏同步", isOn: $syncsLocalFavorites)
                Toggle("稍后再读同步", isOn: $syncsReadLater)
            } header: {
                Text("同步内容")
            } footer: {
                Text("平台账号始终由 iPhone 同步给手表；漫画列表和平台内容仍由手表端独立请求。关闭某项后，该内容不会继续推送给手表。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("Watch 互联")
        .picaxHidesTabBar()
    }
}

struct NetworkSettingsView: View {
    @AppStorage("settings.network.useProxy") private var useProxy = false
    @AppStorage("settings.network.proxyHost") private var proxyHost = ""
    @AppStorage("settings.network.proxyPort") private var proxyPort = 7890
    @AppStorage("settings.network.retryCount") private var retryCount = 2

    @State private var proxyPortText = ""

    private var normalizedProxyHost: String {
        proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isProxyPortValid: Bool {
        guard let value = Int(proxyPortText) else { return false }
        return (1...65535).contains(value)
    }

    private var proxyFooter: String {
        guard useProxy else {
            return "启用后可填写网络代理地址和端口。"
        }
        return normalizedProxyHost.isEmpty ? "请输入代理主机和端口。" : "代理设置会应用到之后创建的网络请求。"
    }

    var body: some View {
        List {
            Section {
                Toggle("启用代理", isOn: $useProxy)

                if useProxy {
                    TextField("代理地址", text: $proxyHost)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                        .picaxKeyboardType(.url)
                        .onSubmit(normalizeProxyHost)

                    TextField("端口", text: $proxyPortText)
                        .picaxKeyboardType(.numberPad)
                        .onChange(of: proxyPortText, perform: updateProxyPort)
                }
            } header: {
                Text("代理")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if useProxy, !isProxyPortValid {
                        Text("端口范围为 1-65535")
                            .foregroundStyle(.red)
                    }
                    Text(proxyFooter)
                }
            }

            Section("连接") {
                IntegerSettingsInputRow(
                    title: "失败重试",
                    value: $retryCount,
                    unit: "次",
                    lowerBound: 0,
                    upperBound: 5
                )
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("网络与代理")
        .picaxHidesTabBar()
        .onAppear(perform: populateProxyPortText)
        .onDisappear(perform: finishEditingProxy)
        .onChange(of: useProxy, perform: handleProxyToggle)
        .onChange(of: proxyPort, perform: normalizeProxyPort)
    }

    private func populateProxyPortText() {
        proxyPortText = "\(proxyPort)"
    }

    private func finishEditingProxy() {
        normalizeProxyHost()
        if !isProxyPortValid {
            proxyPortText = "\(proxyPort)"
        }
    }

    private func handleProxyToggle(_ isEnabled: Bool) {
        if isEnabled, proxyPortText.isEmpty {
            proxyPortText = "\(proxyPort)"
        }
    }

    private func normalizeProxyHost() {
        proxyHost = normalizedProxyHost
    }

    private func normalizeProxyPort(_ newValue: Int) {
        proxyPort = min(max(newValue, 1), 65535)
        let text = "\(proxyPort)"
        if proxyPortText != text {
            proxyPortText = text
        }
    }

    private func updateProxyPort(from value: String) {
        let filtered = String(value.filter(\.isNumber).prefix(5))
        if filtered != value {
            proxyPortText = filtered
            return
        }

        guard let port = Int(filtered), (1...65535).contains(port) else { return }
        proxyPort = port
    }
}

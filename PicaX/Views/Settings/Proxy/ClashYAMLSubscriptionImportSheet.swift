import SwiftUI

struct ClashYAMLSubscriptionImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppProxySettings

    let onImported: (AppBuiltInProxyImportSummary) -> Void

    @State private var urlText = ""
    @State private var routeChoice: SubscriptionRouteChoice = .direct
    @State private var didChooseInitialRoute = false
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        PicaxNavigationContainer {
            Form {
                Section(
                    header: Text("HTTPS 订阅链接"),
                    footer: Text(
                        "链接仅用于本次下载，不会保存。下载内容限制为 5 MB，"
                            + "并按 Clash YAML 的 proxies 列表导入。"
                    )
                ) {
                    TextField("https://example.com/subscription", text: $urlText)
                        .picaxKeyboardType(.url)

                        .picaxDisablesTextAutocapitalization()
                        .disableAutocorrection(true)
                }

                Section(
                    header: Text("订阅获取线路"),
                    footer: Text(routeExplanation)
                ) {
                    Picker("获取方式", selection: $routeChoice) {
                        Text("直连获取")
                            .tag(SubscriptionRouteChoice.direct)

                        if settings.appProxyConfiguration != nil {
                            Text("经代理服务器")
                                .tag(SubscriptionRouteChoice.proxyServer)
                        }

                        ForEach(settings.appBuiltInProxyProfiles) { profile in
                            Text("经内置节点 · \(profile.name)")
                                .tag(
                                    SubscriptionRouteChoice.builtIn(
                                        profile.id
                                    )
                                )
                        }
                    }
                }

                if let errorMessage {
                    Section("无法导入") {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundColor(.red)
                    }
                }
            }
            .picaxHidesTabBar()
            .navigationTitle("订阅导入")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await importNow() }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("下载并导入")
                        }
                    }
                    .disabled(
                        urlText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || isImporting
                    )
                }
            }
            .onAppear(perform: chooseInitialRouteIfNeeded)
        }

        .interactiveDismissDisabled(isImporting)
    }

    private var routeExplanation: String {
        switch routeChoice {
        case .direct:
            return "仅本次订阅请求直接连接，订阅服务会看到当前网络出口 IP。"
        case .proxyServer:
            return "仅本次订阅请求经手动配置的代理服务器获取，不会改变应用当前线路。"
        case .builtIn(let id):
            let name = settings.appBuiltInProxyProfiles.first {
                $0.id == id
            }?.name ?? "所选节点"
            return "仅本次订阅请求经内置节点“\(name)”获取，不会改变应用当前线路。"
        }
    }

    private func chooseInitialRouteIfNeeded() {
        guard !didChooseInitialRoute else { return }
        didChooseInitialRoute = true
        switch settings.appNetworkRoutingMode {
        case .direct:
            routeChoice = .direct
        case .proxyServer:
            routeChoice = settings.appProxyConfiguration == nil
                ? .direct
                : .proxyServer
        case .builtInProxy:
            if let id = settings.selectedBuiltInProxyID,
               settings.appBuiltInProxyProfiles.contains(where: {
                   $0.id == id
               }) {
                routeChoice = .builtIn(id)
            } else {
                routeChoice = .direct
            }
        }
    }

    private func importNow() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let route: AppNetworkRoute
            switch routeChoice {
            case .direct:
                route = .direct
            case .proxyServer:
                route = try settings.networkRouteForProxyServer()
            case .builtIn(let id):
                route = try settings.networkRoute(
                    forBuiltInProxyProfileID: id
                )
            }

            let parsed = try await ClashYAMLSubscriptionFetcher.fetch(
                urlText: urlText,
                route: route
            )
            let summary = try settings.importBuiltInProxyParseResult(
                parsed
            )
            onImported(summary)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SubscriptionRouteChoice: Hashable {
    case direct
    case proxyServer
    case builtIn(UUID)
}

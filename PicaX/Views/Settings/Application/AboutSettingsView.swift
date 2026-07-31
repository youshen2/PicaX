import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var releaseNotes: AppReleaseNotesStore

    @State private var isCheckingUpdate = false
    @State private var updateAlert: AppUpdateAlert?

    private static let buildEnvironment: [String: String] = {
        guard let url = Bundle.main.url(
            forResource: "PicaXBuildEnvironment",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: url),
        let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else {
            return [:]
        }

        return plist as? [String: String] ?? [:]
    }()

    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "PicaX"
    }

    private var appVersion: String {
        Bundle.main.appVersion
    }

    private var buildNumber: String {
        Bundle.main.appBuildNumber
    }

    private var buildInfoRows: [(title: String, value: String)] {
        let environment = Self.buildEnvironment
        return [
            ("构建时间", buildEnvironmentValue("BuildTime", in: environment)),
            ("编译 Commit", buildEnvironmentValue("BuildCommit", in: environment)),
            ("主机名", buildEnvironmentValue("BuildHostName", in: environment)),
            ("编译用户", buildEnvironmentValue("BuildUser", in: environment)),
            ("主机系统", buildEnvironmentValue("BuildHostOS", in: environment)),
            ("主机架构", buildEnvironmentValue("BuildHostArchitecture", in: environment)),
            ("Xcode 版本", buildEnvironmentValue("BuildXcode", in: environment))
        ]
    }

    var body: some View {
        List {
            Section("应用") {
                SettingsValueRow(title: "名称", value: displayName)
                SettingsValueRow(title: "版本", value: appVersion)
                SettingsValueRow(title: "构建", value: buildNumber)
            }

            Section("编译信息") {
                ForEach(buildInfoRows, id: \.title) { row in
                    SettingsValueRow(title: row.title, value: row.value)
                }
            }

            Section("更新") {
                NavigationLink {
                    ReleaseNotesView(
                        releaseNotes: releaseNotes.currentReleaseNotes,
                        currentVersion: releaseNotes.currentVersion
                    )
                } label: {
                    HStack {
                        Label("更新日志", systemImage: "doc.text")

                        Spacer()

                        Text("PicaX \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: beginUpdateCheck) {
                    HStack {
                        Label(
                            isCheckingUpdate ? "正在检查更新" : "检查更新",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer()
                        if isCheckingUpdate {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCheckingUpdate)
            }

            Section("协议与声明") {
                ForEach(LegalDocument.all) { document in
                    NavigationLink {
                        LegalDocumentView(document: document)
                    } label: {
                        Label(document.title, systemImage: document.systemImage)
                    }
                }

                Link(destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!) {
                    Label("MPL-2.0 开源许可", systemImage: "doc.text")
                }
            }

            Section("开源") {
                Link(destination: AppUpdateService.repositoryURL) {
                    Label("开源地址", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("社区") {
                Link(destination: URL(string: "https://t.me/pica_x")!) {
                    Label("Telegram 群组", systemImage: "paperplane")
                }
            }

            Section("鸣谢") {
                Link(destination: URL(string: "https://github.com/ccbkv/PicaComic")!) {
                    Label("ccbkv/PicaComic", systemImage: "heart")
                }

                Link(destination: URL(string: "https://github.com/Pacalini/PicaComic")!) {
                    Label("Pacalini/PicaComic", systemImage: "arrow.triangle.branch")
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("关于 PicaX")
        .picaxHidesTabBar()
        .alert(item: $updateAlert) { alert in
            updateAlert(for: alert)
        }
    }

    private func buildEnvironmentValue(
        _ key: String,
        in environment: [String: String],
        fallback: String = "未知"
    ) -> String {
        let value = environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private func beginUpdateCheck() {
        Task {
            await checkForUpdates()
        }
    }

    private func updateAlert(for alert: AppUpdateAlert) -> Alert {
        if let releaseURL = alert.releaseURL {
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("打开发布页")) {
                    openURL(releaseURL)
                },
                secondaryButton: .cancel(Text("好"))
            )
        }

        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("好"))
        )
    }

    @MainActor
    private func checkForUpdates() async {
        guard !isCheckingUpdate else { return }

        isCheckingUpdate = true
        defer {
            isCheckingUpdate = false
        }

        do {
            let result = try await AppUpdateService.checkLatestRelease(
                currentVersion: appVersion
            )
            if result.hasUpdate {
                updateAlert = AppUpdateAlert(
                    title: "发现新版本",
                    message: "当前版本 \(result.currentVersion)，最新版本 \(result.latestVersion)。可以前往发布页查看更新内容。",
                    releaseURL: result.releaseURL
                )
            } else {
                updateAlert = AppUpdateAlert(
                    title: "已是最新版本",
                    message: "当前版本 \(result.currentVersion) 已是最新版本。",
                    releaseURL: nil
                )
            }
        } catch {
            updateAlert = AppUpdateAlert(
                title: "检查更新失败",
                message: error.localizedDescription,
                releaseURL: nil
            )
        }
    }
}

private struct AppUpdateAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let releaseURL: URL?
}

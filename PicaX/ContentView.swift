import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var accountService: AccountService
    @AppStorage(AppAppearanceSettingsKey.colorScheme) private var colorScheme = AppAppearanceMode.system.rawValue
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true
    @State private var didRunAutomaticUpdateCheck = false
    @State private var automaticUpdateAlert: AutomaticUpdateAlert?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Group {
            if !appSettings.hasCompletedOnboarding || !appSettings.hasAcceptedTerms {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(selectedAppearanceMode.colorScheme)
        .task {
            await checkForUpdatesOnLaunch()
        }
        .alert(item: $automaticUpdateAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("打开发布页")) {
                    openURL(alert.releaseURL)
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: colorScheme) ?? .system
    }

    @MainActor
    private func checkForUpdatesOnLaunch() async {
        guard checksUpdatesOnLaunch, !didRunAutomaticUpdateCheck else { return }
        didRunAutomaticUpdateCheck = true

        do {
            let result = try await AppUpdateService.checkLatestRelease(currentVersion: appVersion)
            guard result.hasUpdate else { return }

            automaticUpdateAlert = AutomaticUpdateAlert(
                title: "发现新版本",
                message: "当前版本 \(result.currentVersion)，最新版本 \(result.latestVersion)。可以前往发布页查看更新内容。",
                releaseURL: result.releaseURL
            )
        } catch {
            // 自动检查更新不打断启动流程。
        }
    }

    private struct AutomaticUpdateAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let releaseURL: URL
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppSettings(defaults: .preview))
            .environmentObject(AccountService(store: AccountStore(defaults: .preview)))
            .environmentObject(PlatformAccountService())
            .environmentObject(ReadingHistoryService(defaults: .preview))
            .environmentObject(ReadLaterService(defaults: .preview))
            .environmentObject(ReadingDurationService(defaults: .preview))
            .environmentObject(DownloadService(defaults: .preview))
            .environmentObject(BlockingKeywordService(defaults: .preview))
            .environmentObject(SearchHistoryService(defaults: .preview))
            .environmentObject(FollowUpdatesService(defaults: .preview))
    }
}

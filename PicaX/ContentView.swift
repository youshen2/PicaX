import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var accountService: AccountService
    @AppStorage(AppAppearanceSettingsKey.colorScheme) private var colorScheme = AppAppearanceMode.system.rawValue
    @AppStorage(AppAppearanceSettingsKey.usesSmoothComicDetailTransitions) private var usesSmoothComicDetailTransitions = true
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true
    @State private var didHandleLaunch = false
    @State private var showsRecommendationDialog = false
    @State private var sharesRecommendationAfterDialogDismissal = false
    @State private var showsRecommendationShareSheet = false
    @State private var didRunAutomaticUpdateCheck = false
    @State private var automaticUpdateAlert: AutomaticUpdateAlert?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Group {
            if !appSettings.hasConfirmedAdultAge {
                AgeRequirementView()
            } else if !appSettings.hasCompletedOnboarding || !appSettings.hasAcceptedTerms {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(selectedAppearanceMode.colorScheme)
        .environment(\.picaxUsesSmoothComicDetailTransitions, usesSmoothComicDetailTransitions)
        .task(id: hasFinishedInitialSetup) {
            guard hasFinishedInitialSetup else { return }
            await handleLaunch()
        }
        .confirmationDialog(
            "喜欢 PicaX 吗？",
            isPresented: $showsRecommendationDialog,
            titleVisibility: .visible
        ) {
            Button("分享 PicaX") {
                shareApplication()
            }
            Button("还是算了") {}
        } message: {
            Text("如果 PicaX 对你有帮助，欢迎把它推荐给更多人。你的分享会帮助项目被更多用户发现。")
        }
        .onChange(of: showsRecommendationDialog) { isPresented in
            guard !isPresented else { return }
#if os(iOS)
            if sharesRecommendationAfterDialogDismissal {
                sharesRecommendationAfterDialogDismissal = false
                DispatchQueue.main.async {
                    showsRecommendationShareSheet = true
                }
                return
            }
#endif
            Task { await checkForUpdatesOnLaunch() }
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
#if os(iOS)
        .sheet(isPresented: $showsRecommendationShareSheet, onDismiss: {
            Task { await checkForUpdatesOnLaunch() }
        }) {
            ApplicationRecommendationShareSheet(
                activityItems: ["我正在使用 PicaX，推荐你也试试！", AppUpdateService.repositoryURL]
            )
        }
#endif
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: colorScheme) ?? .system
    }

    private var hasFinishedInitialSetup: Bool {
        appSettings.hasConfirmedAdultAge
            && appSettings.hasCompletedOnboarding
            && appSettings.hasAcceptedTerms
    }

    @MainActor
    private func handleLaunch() async {
        guard !didHandleLaunch else { return }
        didHandleLaunch = true

        if AppRecommendationPrompt.recordLaunch() {
            showsRecommendationDialog = true
        } else {
            await checkForUpdatesOnLaunch()
        }
    }

    private func shareApplication() {
#if os(iOS)
        sharesRecommendationAfterDialogDismissal = true
#else
        openURL(AppUpdateService.repositoryURL)
#endif
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

#if os(iOS)
private struct ApplicationRecommendationShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

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

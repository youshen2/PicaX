import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    func appLaunchExperience(isReady: Bool) -> some View {
        modifier(AppLaunchExperienceModifier(isReady: isReady))
    }
}

private struct AppLaunchExperienceModifier: ViewModifier {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var releaseNotes: AppReleaseNotesStore
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true

    let isReady: Bool

    @State private var didHandleLaunch = false
    @State private var didContinueLaunchExperience = false
    @State private var didRunAutomaticUpdateCheck = false
    @State private var showsRecommendationDialog = false
    @State private var sharesRecommendationAfterDialogDismissal = false
    @State private var showsRecommendationShareSheet = false
    @State private var presentedReleaseNotes: AppReleaseNotes?
    @State private var automaticUpdateAlert: AutomaticUpdateAlert?

    func body(content: Content) -> some View {
        content
            .task(id: isReady) {
                guard isReady else { return }
                await handleLaunch()
            }
            .sheet(
                item: $presentedReleaseNotes,
                onDismiss: finishReleaseNotesPresentation
            ) { notes in
                ReleaseNotesSheet(releaseNotes: notes)
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
                    title: Text("发现新版本"),
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
                    activityItems: [
                        "我正在使用 PicaX，推荐你也试试！",
                        AppUpdateService.repositoryURL
                    ]
                )
            }
#endif
    }

    @MainActor
    private func handleLaunch() async {
        guard !didHandleLaunch else { return }
        didHandleLaunch = true

        if let pendingReleaseNotes = releaseNotes.releaseNotesToPresent {
            presentedReleaseNotes = pendingReleaseNotes
            return
        }

        await continueLaunchExperience()
    }

    @MainActor
    private func finishReleaseNotesPresentation() {
        releaseNotes.markCurrentVersionPresented()

        Task {
            await continueLaunchExperience()
        }
    }

    @MainActor
    private func continueLaunchExperience() async {
        guard !didContinueLaunchExperience else { return }
        didContinueLaunchExperience = true

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
            let result = try await AppUpdateService.checkLatestRelease(
                currentVersion: Bundle.main.appVersion
            )
            guard result.hasUpdate else { return }

            automaticUpdateAlert = AutomaticUpdateAlert(
                message: "当前版本 \(result.currentVersion)，最新版本 \(result.latestVersion)。可以前往发布页查看更新内容。",
                releaseURL: result.releaseURL
            )
        } catch {
            // 自动检查更新不打断启动流程。
        }
    }
}

private struct AutomaticUpdateAlert: Identifiable {
    let id = UUID()
    let message: String
    let releaseURL: URL
}

#if os(iOS)
private struct ApplicationRecommendationShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif

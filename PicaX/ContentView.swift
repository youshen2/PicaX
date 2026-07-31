import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @AppStorage(AppAppearanceSettingsKey.colorScheme) private var colorScheme = AppAppearanceMode.system.rawValue
    @AppStorage(AppAppearanceSettingsKey.usesSmoothComicDetailTransitions) private var usesSmoothComicDetailTransitions = true

    var body: some View {
        Group {
            if !appSettings.hasConfirmedAdultAge {
                AgeRequirementView()
            } else if !appSettings.hasCompletedOnboarding
                        || !appSettings.hasAcceptedTerms
                        || !appSettings.hasAcceptedDisclaimer {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(selectedAppearanceMode.colorScheme)
        .environment(\.picaxUsesSmoothComicDetailTransitions, usesSmoothComicDetailTransitions)
        .appLaunchExperience(isReady: hasFinishedInitialSetup)
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: colorScheme) ?? .system
    }

    private var hasFinishedInitialSetup: Bool {
        appSettings.hasCompletedInitialSetup
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let downloadService = DownloadService(defaults: .preview)
        let releaseNotes = AppReleaseNotesStore(
            currentVersion: "1.1.6",
            hadCompletedOnboarding: false,
            currentReleaseNotes: nil,
            defaults: .preview
        )

        ContentView()
            .environmentObject(AppSettings(defaults: .preview))
            .environmentObject(releaseNotes)
            .environmentObject(PlatformAccountService())
            .environmentObject(ReadingHistoryService(defaults: .preview))
            .environmentObject(ReadLaterService(defaults: .preview))
            .environmentObject(ReadingDurationService(defaults: .preview))
            .environmentObject(downloadService)
            .environmentObject(downloadService.taskStore)
            .environmentObject(BlockingKeywordService(defaults: .preview))
            .environmentObject(SearchHistoryService(defaults: .preview))
            .environmentObject(FollowUpdatesService(defaults: .preview))
    }
}

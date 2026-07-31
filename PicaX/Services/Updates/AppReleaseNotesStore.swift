import Combine
import Foundation

@MainActor
final class AppReleaseNotesStore: ObservableObject {
    private enum Key {
        static let lastPresentedVersion = "appReleaseNotes.lastPresentedVersion"
    }

    let currentVersion: String
    let currentReleaseNotes: AppReleaseNotes?
    @Published private(set) var releaseNotesToPresent: AppReleaseNotes?

    private let defaults: UserDefaults

    init(
        currentVersion: String,
        hadCompletedOnboarding: Bool,
        currentReleaseNotes: AppReleaseNotes?,
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.currentReleaseNotes = currentReleaseNotes
        self.defaults = defaults

        let lastPresentedVersion = defaults.string(forKey: Key.lastPresentedVersion)

        guard hadCompletedOnboarding else {
            defaults.set(currentVersion, forKey: Key.lastPresentedVersion)
            return
        }

        guard let currentReleaseNotes,
              AppVersion.isEquivalent(currentReleaseNotes.version, to: currentVersion) else {
            if lastPresentedVersion == nil {
                defaults.set(currentVersion, forKey: Key.lastPresentedVersion)
            }
            return
        }

        if let lastPresentedVersion {
            if AppVersion.compare(currentVersion, to: lastPresentedVersion) == .orderedDescending {
                releaseNotesToPresent = currentReleaseNotes
            }
        } else {
            releaseNotesToPresent = currentReleaseNotes
        }
    }

    func markCurrentVersionPresented() {
        defaults.set(currentVersion, forKey: Key.lastPresentedVersion)
        releaseNotesToPresent = nil
    }
}

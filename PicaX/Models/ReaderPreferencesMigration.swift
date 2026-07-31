import Foundation

nonisolated enum ReaderPreferencesMigration {
    private static let currentVersion = 2

    static func apply(defaults: UserDefaults = .standard) {
        var version = defaults.integer(forKey: ReaderSettingsKey.visibilityDefaultsVersion)
        guard version < currentVersion else { return }

        if version < 1 {
            defaults.set(false, forKey: ReaderSettingsKey.progressFollowsUIVisibility)
            defaults.set(false, forKey: ReaderSettingsKey.systemStatusFollowsUIVisibility)
            version = 1
        }

        if version < 2 {
            if defaults.object(forKey: ReaderSettingsKey.progressBottomInset) as? Double == 16 {
                defaults.set(0.0, forKey: ReaderSettingsKey.progressBottomInset)
            }
            if defaults.object(forKey: ReaderSettingsKey.systemStatusBottomInset) as? Double == 16 {
                defaults.set(0.0, forKey: ReaderSettingsKey.systemStatusBottomInset)
            }
            version = 2
        }

        defaults.set(version, forKey: ReaderSettingsKey.visibilityDefaultsVersion)
    }
}

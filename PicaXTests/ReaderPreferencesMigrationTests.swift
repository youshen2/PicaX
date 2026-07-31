import XCTest
@testable import PicaX

final class ReaderPreferencesMigrationTests: XCTestCase {
    func testMigrationUpdatesLegacyInsetsAndVisibilityDefaults() throws {
        let suiteName = "ReaderPreferencesMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(16.0, forKey: ReaderSettingsKey.progressBottomInset)
        defaults.set(16.0, forKey: ReaderSettingsKey.systemStatusBottomInset)
        defaults.set(true, forKey: ReaderSettingsKey.progressFollowsUIVisibility)
        defaults.set(true, forKey: ReaderSettingsKey.systemStatusFollowsUIVisibility)

        ReaderPreferencesMigration.apply(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: ReaderSettingsKey.visibilityDefaultsVersion), 2)
        XCTAssertEqual(defaults.double(forKey: ReaderSettingsKey.progressBottomInset), 0)
        XCTAssertEqual(defaults.double(forKey: ReaderSettingsKey.systemStatusBottomInset), 0)
        XCTAssertFalse(defaults.bool(forKey: ReaderSettingsKey.progressFollowsUIVisibility))
        XCTAssertFalse(defaults.bool(forKey: ReaderSettingsKey.systemStatusFollowsUIVisibility))
    }

    func testMigrationPreservesCustomizedInsetsAndIsIdempotent() throws {
        let suiteName = "ReaderPreferencesMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(23.0, forKey: ReaderSettingsKey.progressBottomInset)
        defaults.set(31.0, forKey: ReaderSettingsKey.systemStatusBottomInset)

        ReaderPreferencesMigration.apply(defaults: defaults)
        ReaderPreferencesMigration.apply(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: ReaderSettingsKey.progressBottomInset), 23)
        XCTAssertEqual(defaults.double(forKey: ReaderSettingsKey.systemStatusBottomInset), 31)
        XCTAssertEqual(defaults.integer(forKey: ReaderSettingsKey.visibilityDefaultsVersion), 2)
    }
}

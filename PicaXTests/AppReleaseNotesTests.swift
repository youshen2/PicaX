import Foundation
import XCTest
@testable import PicaX

final class AppReleaseNotesLoaderTests: XCTestCase {
    func testParsesBundledMetadataAndMarkdownEntries() throws {
        let metadata = try XCTUnwrap(
            #"{"schemaVersion":2,"version":"1.1.7","sourceRevision":"abc123","previousVersion":"1.1.6"}"#
                .data(using: .utf8)
        )

        let releaseNotes = try XCTUnwrap(
            AppReleaseNotesLoader.parse(
                metadataData: metadata,
                markdown: "- 第一项\n- 第二项\n"
            )
        )

        XCTAssertEqual(releaseNotes.version, "1.1.7")
        XCTAssertEqual(releaseNotes.previousVersion, "1.1.6")
        XCTAssertEqual(releaseNotes.entries, ["第一项", "第二项"])
    }

    func testRejectsUnsupportedMetadataSchema() throws {
        let metadata = try XCTUnwrap(
            #"{"schemaVersion":1,"version":"1.1.7","sourceRevision":"abc123","previousVersion":null}"#
                .data(using: .utf8)
        )

        XCTAssertNil(
            AppReleaseNotesLoader.parse(
                metadataData: metadata,
                markdown: "- 更新内容\n"
            )
        )
    }
}

@MainActor
final class AppReleaseNotesStoreTests: XCTestCase {
    func testPresentsNewVersionOnceAfterUpgrade() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = AppReleaseNotesStore(
            currentVersion: "1.1.6",
            hadCompletedOnboarding: false,
            currentReleaseNotes: nil,
            defaults: defaults
        )

        let notes = makeReleaseNotes(version: "1.1.7")
        let upgradedStore = AppReleaseNotesStore(
            currentVersion: "1.1.7",
            hadCompletedOnboarding: true,
            currentReleaseNotes: notes,
            defaults: defaults
        )

        XCTAssertEqual(upgradedStore.releaseNotesToPresent, notes)

        upgradedStore.markCurrentVersionPresented()

        let relaunchedStore = AppReleaseNotesStore(
            currentVersion: "1.1.7",
            hadCompletedOnboarding: true,
            currentReleaseNotes: notes,
            defaults: defaults
        )
        XCTAssertNil(relaunchedStore.releaseNotesToPresent)
    }

    func testDoesNotPresentReleaseNotesDuringFirstRunOnboarding() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppReleaseNotesStore(
            currentVersion: "1.1.7",
            hadCompletedOnboarding: false,
            currentReleaseNotes: makeReleaseNotes(version: "1.1.7"),
            defaults: defaults
        )

        XCTAssertNil(store.releaseNotesToPresent)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppReleaseNotesStoreTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }

    private func makeReleaseNotes(version: String) -> AppReleaseNotes {
        AppReleaseNotes(
            version: version,
            sourceRevision: "abc123",
            previousVersion: "1.1.6",
            entries: ["更新内容"]
        )
    }
}

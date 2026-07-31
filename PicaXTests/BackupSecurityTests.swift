import XCTest
@testable import PicaX

final class BackupSecurityTests: XCTestCase {
    func testArchiveRejectsParentDirectoryTraversal() {
        XCTAssertThrowsError(
            try StoredZipArchive.makeArchive(
                entries: [StoredZipEntry(path: "../credentials.json", data: Data())]
            )
        ) { error in
            guard case BackupArchiveError.invalidPath = error else {
                return XCTFail("Expected invalidPath, got \(error)")
            }
        }
    }

    func testArchiveRejectsDuplicatePaths() {
        XCTAssertThrowsError(
            try StoredZipArchive.makeArchive(
                entries: [
                    StoredZipEntry(path: "backup.json", data: Data("first".utf8)),
                    StoredZipEntry(path: "backup.json", data: Data("second".utf8))
                ]
            )
        ) { error in
            guard case BackupArchiveError.duplicateEntry = error else {
                return XCTFail("Expected duplicateEntry, got \(error)")
            }
        }
    }

    func testArchiveWritesToFileBackedStorage() throws {
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaXArchive-\(UUID().uuidString)")
            .appendingPathExtension("picax")
        defer {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try? FileManager.default.removeItem(at: archiveURL)
            }
        }
        let payload = Data("file-backed archive".utf8)

        try StoredZipArchive.makeArchive(
            entries: [StoredZipEntry(path: "backup.json", data: payload)],
            at: archiveURL
        )

        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertEqual(
            try StoredZipArchive.extractEntry(named: "backup.json", from: archiveData),
            payload
        )
    }

    func testArchiveStreamsSelectedDownloadToDisk() throws {
        let payload = Data((0..<(256 * 1024)).map { _ in
            UInt8.random(in: .min ... .max)
        })
        let archive = try StoredZipArchive.makeArchive(
            entries: [
                StoredZipEntry(path: "backup.json", data: Data("{}".utf8)),
                StoredZipEntry(path: "downloads/picacg/comic/page.jpg", data: payload)
            ]
        )
        let outputRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaXBackupTest-\(UUID().uuidString)", isDirectory: true)
        defer {
            if FileManager.default.fileExists(atPath: outputRoot.path) {
                try? FileManager.default.removeItem(at: outputRoot)
            }
        }
        let destination = outputRoot.appendingPathComponent(
            "picacg/comic/page.jpg",
            isDirectory: false
        )

        try StoredZipArchive.extractEntries(
            from: archive,
            to: ["downloads/picacg/comic/page.jpg": destination]
        )

        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }

    func testArchiveReportsMissingStreamedDownload() throws {
        let archive = try StoredZipArchive.makeArchive(
            entries: [StoredZipEntry(path: "backup.json", data: Data("{}".utf8))]
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicaXMissing-\(UUID().uuidString)")

        XCTAssertThrowsError(
            try StoredZipArchive.extractEntries(
                from: archive,
                to: ["downloads/missing.jpg": destination]
            )
        ) { error in
            guard case BackupArchiveError.missingDownloadFile("missing.jpg") = error else {
                return XCTFail("Expected missingDownloadFile, got \(error)")
            }
        }
    }
}

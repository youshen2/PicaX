import XCTest
@testable import PicaX

@MainActor
final class DownloadRecordTests: XCTestCase {
    func testFullyDownloadedRequiresEveryKnownChapter() {
        XCTAssertFalse(makeRecord(totalChapterCount: 0, downloadedChapterCount: 0).isFullyDownloaded)
        XCTAssertFalse(makeRecord(totalChapterCount: 2, downloadedChapterCount: 1).isFullyDownloaded)
        XCTAssertTrue(makeRecord(totalChapterCount: 2, downloadedChapterCount: 2).isFullyDownloaded)
    }

    private func makeRecord(totalChapterCount: Int, downloadedChapterCount: Int) -> DownloadRecord {
        let item = ComicListItem(
            id: "download-test",
            platform: .picacg,
            title: "下载测试",
            subtitle: "",
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
        let chapters = (0..<downloadedChapterCount).map { index in
            DownloadedChapterRecord(
                index: index,
                chapter: ComicChapter(id: "chapter-\(index)", title: "第 \(index + 1) 章", subtitle: nil),
                pageCount: 1,
                bytes: 1,
                downloadedAt: .distantPast
            )
        }
        return DownloadRecord(
            item: item,
            chapters: chapters,
            totalChapterCount: totalChapterCount,
            totalBytes: Int64(downloadedChapterCount),
            directoryName: "download-test",
            coverFileName: nil,
            detail: nil,
            comments: [],
            updatedAt: .distantPast
        )
    }
}

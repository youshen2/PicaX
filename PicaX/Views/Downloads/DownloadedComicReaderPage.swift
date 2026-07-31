import SwiftUI

struct DownloadedComicReaderPage: View {
    @EnvironmentObject private var downloadService: DownloadService

    let request: DownloadedComicReaderRequest
    let service: ComicContentService

    @State private var deletesLocalDownloadOnExit = false
    @State private var didHandleReaderExit = false

    var body: some View {
        ComicReaderPage(
            detail: request.detail,
            initialChapterIndex: request.initialChapterIndex,
            initialPageIndex: request.initialPageIndex,
            ignoresHistoryProgress: request.ignoresHistoryProgress,
            recordsReadingHistory: request.recordsReadingHistory,
            service: service,
            localChapterImageProvider: { _, chapterIndex in
                guard request.localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                return await downloadService.localChapterImages(
                    for: request.record,
                    chapterIndex: request.localChapterIndexes[chapterIndex]
                )
            },
            localChapterCommentsProvider: { _, chapterIndex in
                guard request.localChapterIndexes.indices.contains(chapterIndex) else { return [] }
                return await downloadService.localChapterComments(
                    for: request.record,
                    chapterIndex: request.localChapterIndexes[chapterIndex]
                )
            },
            historyChapterIndexResolver: { chapterIndex in
                guard request.localChapterIndexes.indices.contains(chapterIndex) else { return chapterIndex }
                return request.localChapterIndexes[chapterIndex]
            },
            deletesLocalDownloadOnExit: $deletesLocalDownloadOnExit,
            onReaderExit: handleReaderExit
        )
    }

    private func handleReaderExit() {
        guard deletesLocalDownloadOnExit, !didHandleReaderExit else { return }
        didHandleReaderExit = true
        downloadService.removeRecord(request.record)
    }
}

import SwiftUI

struct HomeDownloadsHeader: View {
    let service: ComicContentService

    var body: some View {
        HStack {
            Text("下载")
            Spacer()
            NavigationLink {
                DownloadListPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                Image(systemName: "chevron.right.circle")
                    .imageScale(.medium)
            }
            .accessibilityLabel("查看全部下载")
        }
    }
}

struct HomeDownloadsCard: View {
    @EnvironmentObject private var downloadService: DownloadService

    let records: [DownloadRecord]
    let service: ComicContentService
    let openReader: (DownloadedComicReaderRequest) -> Void
    let openSearch: (DownloadedComicSearchRequest) -> Void
    @State private var selectedRecord: DownloadRecord?

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("暂无下载", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Text("漫画下载完成后会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(records) { record in
                            Button {
                                selectedRecord = record
                            } label: {
                                DownloadRecordCardItem(
                                    record: record,
                                    coverURL: downloadService.localCoverURL(for: record) ?? record.item.coverURL
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            DownloadedComicInfoSheet(record: record, service: service) { request in
                selectedRecord = nil
                openReader(request)
            } openSearch: { request in
                selectedRecord = nil
                openSearch(request)
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct HomeDownloadsEntryLink: View {
    let service: ComicContentService

    var body: some View {
        NavigationLink {
            DownloadListPage(service: service)
                .picaxHidesTabBar()
        } label: {
            ToolRow(
                title: "下载",
                subtitle: "查看下载列表和队列",
                systemImage: "arrow.down.circle"
            )
        }
    }
}

private struct DownloadRecordCardItem: View {
    let record: DownloadRecord
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ComicCoverView(url: coverURL, accentColor: record.item.accentColor, width: 92, height: 124)

            Text(record.item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 92, alignment: .leading)

            Text(record.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
        }
        .frame(width: 92, alignment: .topLeading)
    }
}

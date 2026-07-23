import SwiftUI

struct HomeHistoryHeader: View {
    let service: ComicContentService

    var body: some View {
        HStack {
            Text("历史记录")
            Spacer()
            NavigationLink {
                ReadingHistoryListPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                Image(systemName: "chevron.right.circle")
                    .imageScale(.medium)
            }
            .accessibilityLabel("查看全部历史记录")
        }
    }
}

struct HomeHistoryCard: View {
    let records: [ReadingHistoryRecord]
    let service: ComicContentService

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("暂无历史记录", systemImage: "clock")
                        .font(.headline)
                    Text("打开漫画详情后会在这里显示最近阅读。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(records) { record in
                            ComicDetailNavigationLink(item: record.item, service: service) {
                                HistoryCardItem(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

struct HomeHistoryEntryLink: View {
    let service: ComicContentService

    var body: some View {
        NavigationLink {
            ReadingHistoryListPage(service: service)
                .picaxHidesTabBar()
        } label: {
            ToolRow(
                title: "阅读历史",
                subtitle: "查看全部阅读记录",
                systemImage: "clock.arrow.circlepath"
            )
        }
    }
}

private struct HistoryCardItem: View {
    let record: ReadingHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 92, height: 124)

            Text(record.item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 92, alignment: .leading)

            Text(record.progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
        }
        .frame(width: 92, alignment: .topLeading)
    }
}

private struct ReadingHistoryListPage: View {
    @EnvironmentObject private var readingHistory: ReadingHistoryService
    let service: ComicContentService

    var body: some View {
        List {
            if readingHistory.records.isEmpty {
                ContentUnavailableView("暂无历史记录", systemImage: "clock", description: Text("打开漫画详情后会记录到这里"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(readingHistory.records) { record in
                        ComicDetailNavigationLink(item: record.item, service: service) {
                            ReadingHistoryRow(record: record)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                readingHistory.remove(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("左滑可删除单条记录。")
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .picaxSensitiveImageContent(!readingHistory.records.isEmpty)
        .navigationTitle("历史记录")
    }
}

private struct ReadingHistoryRow: View {
    let record: ReadingHistoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 64, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(record.item.platformTitle) · 编号 \(record.item.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(record.detailTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(record.progressText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.isReadingRecord ? record.item.accentColor : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

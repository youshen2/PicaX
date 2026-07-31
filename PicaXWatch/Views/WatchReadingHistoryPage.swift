import SwiftUI

struct WatchReadingHistoryPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @State private var records: [WatchReadingHistoryRecord] = []
    @State private var showsClearConfirmation = false

    private let store = WatchReadingHistoryStore()

    var body: some View {
        List {
            Section("阅读记录") {
                if records.isEmpty {
                    WatchEmptyRow(title: "暂无阅读记录", systemImage: "clock.arrow.circlepath")
                } else {
                    ForEach(records) { record in
                        NavigationLink {
                            WatchComicDetailPage(item: record.item)
                        } label: {
                            WatchReadingHistoryRow(record: record)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets where records.indices.contains(index) {
                            store.remove(records[index])
                        }
                        reload()
                        accountSyncStore.syncReadingHistory()
                    }
                }
            }

            if !records.isEmpty {
                Section("操作") {
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("清空阅读记录", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("阅读记录")
        .onAppear {
            reload()
        }
        .alert("清空阅读记录？", isPresented: $showsClearConfirmation) {
            Button("清空", role: .destructive) {
                store.clear()
                reload()
                accountSyncStore.syncReadingHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("手表上的全部阅读记录会被删除，并在下次同步时合并到 iPhone。")
        }
    }

    private func reload() {
        records = store.load()
    }
}

private struct WatchReadingHistoryRow: View {
    let record: WatchReadingHistoryRecord

    var body: some View {
        HStack(spacing: 8) {
            WatchCoverThumbnail(url: record.item.coverURL, width: 36, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(record.progress.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.viewedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

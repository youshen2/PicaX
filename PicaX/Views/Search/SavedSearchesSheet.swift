import SwiftUI

struct SavedSearchesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoredCollection<SavedComicSearch>(key: SavedComicSearch.storageKey)
    let current: SearchHistoryRecord
    let onSelect: (SearchHistoryRecord) -> Void
    @State private var name = ""

    private var sortedRecords: [SavedComicSearch] {
        store.records.sorted { $0.isPinned && !$1.isPinned }
    }

    var body: some View {
        PicaxNavigationContainer {
            List {
                Section("保存当前搜索") {
                    TextField("名称", text: $name)
                    Text(current.keyword.isEmpty ? "先输入搜索关键词" : current.keyword)
                        .foregroundStyle(.secondary)
                    Button("保存") {
                        store.put(SavedComicSearch(name: name.trimmingCharacters(in: .whitespacesAndNewlines), search: current))
                        name = ""
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || current.keyword.isEmpty)
                }
                Section("常用搜索") {
                    ForEach(sortedRecords) { record in
                        NavigationLink {
                            SavedSearchEditor(record: record, store: store) {
                                onSelect($0)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(record.name, systemImage: record.isPinned ? "pin.fill" : "magnifyingglass")
                                Text("\(record.search.keyword) · \(record.search.target.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button(record.isPinned ? "取消置顶" : "置顶") {
                                var updated = record
                                updated.isPinned.toggle()
                                store.put(updated)
                            }.tint(.orange)
                        }
                    }
                    .onDelete { offsets in
                        let records = sortedRecords
                        for index in offsets { store.remove(records[index]) }
                    }
                }
            }
            .navigationTitle("常用搜索")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .onAppear { name = current.keyword }
    }
}

private struct SavedSearchEditor: View {
    @State var record: SavedComicSearch
    @ObservedObject var store: StoredCollection<SavedComicSearch>
    let onSelect: (SearchHistoryRecord) -> Void
    var body: some View {
        Form {
            TextField("名称", text: $record.name)
            Toggle("置顶", isOn: $record.isPinned)
            Text(record.search.keyword)
            Text(record.search.target.searchTarget.platformSummary).foregroundStyle(.secondary)
            Button("使用此搜索") { onSelect(record.search) }
        }
        .navigationTitle("编辑常用搜索")
        .onDisappear {
            if !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.put(record) }
        }
    }
}

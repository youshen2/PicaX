import SwiftUI

struct ReaderBookmarksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoredCollection<ComicPageBookmark>(key: ComicPageBookmark.storageKey)
    let current: ComicPageBookmark?
    let comicID: String
    let availableChapterIDs: Set<String>
    let onSelect: (ComicPageBookmark) -> Void
    @State private var note = ""
    @State private var editing: ComicPageBookmark?

    private var bookmarks: [ComicPageBookmark] {
        store.records.filter { $0.comicID == comicID }.sorted {
            ($0.chapterIndex, $0.pageIndex) < ($1.chapterIndex, $1.pageIndex)
        }
    }

    var body: some View {
        PicaxNavigationContainer {
            List {
                if var current {
                    Section("当前位置") {
                        Text("\(current.chapterTitle) · 第 \(current.pageIndex + 1) 页")
                        TextField("书签备注（可选）", text: $note)
                        Button("保存当前位置") {
                            current.note = note
                            store.put(current)
                        }
                    }
                }
                Section("本书书签") {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            onSelect(bookmark)
                            dismiss()
                        } label: {
                            HStack {
                                ComicCoverView(url: URL.picaxResolved(from: bookmark.thumbnailURLString),
                                               accentColor: .blue, width: 42, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(bookmark.chapterTitle) · 第 \(bookmark.pageIndex + 1) 页")
                                    if !bookmark.note.isEmpty { Text(bookmark.note).font(.caption).foregroundStyle(.secondary) }
                                    if !availableChapterIDs.contains(bookmark.chapterID) {
                                        Text("当前书库中没有此章节").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!availableChapterIDs.contains(bookmark.chapterID))
                        .contextMenu { Button("编辑备注") { editing = bookmark } }
                    }
                    .onDelete { offsets in
                        let current = bookmarks
                        for index in offsets { store.remove(current[index]) }
                    }
                }
            }
            .navigationTitle("页级书签")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { bookmark in
                BookmarkNoteEditor(bookmark: bookmark, store: store)
            }
        }
        .onAppear { note = store.records.first { $0.id == current?.id }?.note ?? "" }
        .picaxSensitiveImageContent(!bookmarks.isEmpty)
    }
}

private struct BookmarkNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var bookmark: ComicPageBookmark
    let store: StoredCollection<ComicPageBookmark>
    var body: some View {
        PicaxNavigationContainer {
            Form { TextField("备注", text: $bookmark.note) }
                .navigationTitle("编辑书签")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { store.put(bookmark); dismiss() }
                    }
                }
        }
    }
}

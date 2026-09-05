import SwiftUI

nonisolated struct BlockedComicMatch: Identifiable, Sendable {
    let item: ComicListItem
    let rule: String
    var id: String { item.readingHistoryID }
}

struct BlockedComicResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let matches: [BlockedComicMatch]
    let service: ComicContentService
    @State private var revealsContent = false

    var body: some View {
        PicaxNavigationContainer {
            VStack(spacing: 0) {
                Toggle("临时显示本页屏蔽内容", isOn: $revealsContent).padding()
                if revealsContent {
                    ComicListSection(comics: matches.map(\.item), service: service,
                                     appliesBlocking: false, appliesReadProgressFilter: false,
                                     appliesReadLaterFilter: false)
                } else {
                    List(matches) { match in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(match.item.title)
                            Text("\(match.item.platformTitle) · 命中：\(match.rule)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("屏蔽说明")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    NavigationLink("管理规则") { BlockingKeywordSettingsView() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

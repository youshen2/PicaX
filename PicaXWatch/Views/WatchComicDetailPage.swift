import SwiftUI

struct WatchComicDetailPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @StateObject private var viewModel = WatchComicDetailViewModel()

    let item: WatchComicItem

    var body: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                Section {
                    ProgressView()
                }
            case .failed(let message):
                Section {
                    WatchValueRow(title: "加载失败", subtitle: message, systemImage: "exclamationmark.triangle", tint: .orange)
                }
            case .loaded(let detail):
                headerSection(detail)
                if !detail.description.isEmpty {
                    Section("简介") {
                        Text(detail.description)
                            .font(.caption)
                    }
                }
                if !detail.metadata.isEmpty || detail.updatedText != nil {
                    Section("信息") {
                        if let updatedText = detail.updatedText {
                            WatchValueRow(title: "更新", subtitle: updatedText, systemImage: "clock")
                        }
                        ForEach(detail.metadata) { row in
                            WatchValueRow(title: row.title, subtitle: row.value, systemImage: "info.circle")
                        }
                    }
                }
                if !detail.chapters.isEmpty {
                    Section("章节") {
                        ForEach(detail.chapters.prefix(8)) { chapter in
                            WatchValueRow(
                                title: chapter.title,
                                subtitle: chapter.subtitle ?? "可阅读章节",
                                systemImage: "book.pages"
                            )
                        }
                    }
                }
                ForEach(detail.tagGroups) { group in
                    Section(group.title) {
                        ForEach(group.tags.prefix(12)) { tag in
                            WatchValueRow(title: tag.title, subtitle: tag.query, systemImage: "tag")
                        }
                    }
                }
                if !detail.related.isEmpty {
                    Section("相关") {
                        ForEach(detail.related.prefix(6)) { item in
                            NavigationLink {
                                WatchComicDetailPage(item: item)
                            } label: {
                                WatchComicRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func headerSection(_ detail: WatchComicDetailInfo) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                AsyncImage(url: detail.item.coverURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: detail.item.platform.systemImage)
                        .font(.title2)
                        .foregroundStyle(detail.item.platform.watchColor)
                }
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.item.title)
                        .font(.headline)
                        .lineLimit(3)
                    Text(detail.item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(detail.item.platform.title)
                        .font(.caption2)
                        .foregroundStyle(detail.item.platform.watchColor)
                }
            }

            Button {
                if accountSyncStore.isLocalFavorite(detail.item) {
                    accountSyncStore.removeLocalFavorite(detail.item)
                } else {
                    accountSyncStore.addLocalFavorite(detail.item)
                }
            } label: {
                Label(
                    accountSyncStore.isLocalFavorite(detail.item) ? "取消本地收藏" : "加入本地收藏",
                    systemImage: accountSyncStore.isLocalFavorite(detail.item) ? "heart.slash" : "heart"
                )
            }
        }
    }

    private func load(force: Bool = false) async {
        await viewModel.load(
            item: item,
            account: accountSyncStore.snapshot.account(for: item.platform),
            force: force
        )
    }
}

#Preview {
    NavigationStack {
        WatchComicDetailPage(
            item: WatchComicItem(
                id: "preview",
                platform: .picacg,
                title: "Preview Comic",
                subtitle: "Author",
                coverURLString: nil,
                tags: ["tag"],
                pageCount: 12,
                favoriteDate: nil
            )
        )
    }
    .environmentObject(WatchAccountSyncStore.preview)
}

import SwiftUI

struct FavoritesPage: View {
    @EnvironmentObject private var platformAccounts: PlatformAccountService

    private let service = ComicContentService()

    var body: some View {
        List {
            Section("本地收藏夹") {
                ForEach(service.localFolders) { folder in
                    NavigationLink {
                        FavoritesCollectionPage(source: .local(folder), service: service)
                    } label: {
                        FavoriteSourceRow(
                            title: folder.title,
                            subtitle: folder.subtitle,
                            systemImage: "folder",
                            accentColor: .orange
                        )
                    }
                }
            }

            Section("平台收藏") {
                if platformAccounts.loggedInAccounts.isEmpty {
                    ContentUnavailableView("暂无已登录平台", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("登录平台账号后会在这里显示对应收藏"))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(platformAccounts.loggedInAccounts) { account in
                        NavigationLink {
                            FavoritesCollectionPage(source: .platform(account), service: service)
                        } label: {
                            FavoriteSourceRow(
                                title: account.platform.title,
                                subtitle: account.displayName,
                                systemImage: account.platform.systemImage,
                                accentColor: account.platform.accentColor
                            )
                        }
                    }
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
    }
}

private struct FavoriteSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 5)
    }
}

private struct FavoritesCollectionPage: View {
    let source: FavoriteCollectionSource
    let service: ComicContentService
    @State private var comics: [ComicListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        Group {
            if isLoading {
                LoadingFavoriteListView(accentColor: source.accentColor)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task {
                            await load(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if comics.isEmpty {
                ContentUnavailableView("暂无收藏", systemImage: source.systemImage, description: Text("这个收藏源当前没有返回漫画"))
            } else if filteredComics.isEmpty {
                ContentUnavailableView("没有匹配收藏", systemImage: "magnifyingglass", description: Text("换个关键词再试"))
            } else {
                ComicListSection(comics: filteredComics, service: service, appliesBlocking: false, appliesReadProgressFilter: false)
                .refreshable {
                    await load(force: true)
                }
            }
        }
        .navigationTitle(source.title)
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
        .searchable(text: $searchText, placement: .picaxNavigationSearch, prompt: "搜索当前收藏夹")
        .toolbar {
            ToolbarItem(placement: .picaxTopBarTrailing) {
                Button {
                    Task {
                        await load(force: true)
                    }
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

    private var filteredComics: [ComicListItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return comics }
        return comics.filter { comic in
            favoriteSearchFields(for: comic).contains { field in
                field.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    private func favoriteSearchFields(for comic: ComicListItem) -> [String] {
        [
            comic.title,
            comic.subtitle,
            comic.id,
            comic.platformTitle,
            comic.pageText ?? "",
            comic.metadataText
        ] + comic.tags
    }

    @MainActor
    private func load(force: Bool = false) async {
        if !force, !comics.isEmpty {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            switch source {
            case .local(let folder):
                comics = service.loadLocalFavorites(folder: folder)
            case .platform(let account):
                comics = try await service.loadFavorites(account: account)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LoadingFavoriteListView: View {
    let accentColor: Color

    var body: some View {
        LoadingStateView(title: "正在加载收藏")
    }
}

private enum FavoriteCollectionSource: Identifiable {
    case local(LocalFavoriteFolder)
    case platform(PlatformAccount)

    var id: String {
        switch self {
        case .local(let folder):
            return "local-\(folder.id)"
        case .platform(let account):
            return "platform-\(account.platform.id)"
        }
    }

    var title: String {
        switch self {
        case .local(let folder):
            return folder.title
        case .platform(let account):
            return account.platform.title
        }
    }

    var systemImage: String {
        switch self {
        case .local:
            return "folder"
        case .platform(let account):
            return account.platform.systemImage
        }
    }

    var accentColor: Color {
        switch self {
        case .local:
            return .orange
        case .platform(let account):
            return account.platform.accentColor
        }
    }
}

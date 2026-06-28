import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeToolDetailRequest: Identifiable, Hashable {
    let id = UUID()
    let item: ComicListItem

    static func == (lhs: HomeToolDetailRequest, rhs: HomeToolDetailRequest) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct HomeToolsSection: View {
    @Environment(\.openURL) private var openURL
    let service: ComicContentService
    let requestInput: (HomeToolInputTarget) -> Void
    let showError: (String) -> Void

    var body: some View {
        Section("快捷工具") {
            NavigationLink {
                EhentaiSubscriptionPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                ToolRow(title: "EH 订阅", subtitle: "查看 watched 订阅更新", systemImage: "antenna.radiowaves.left.and.right")
            }

            Button {
                openExternalURL("https://soutubot.moe/")
            } label: {
                ToolRow(title: "图片搜索 [搜图bot酱]", subtitle: "打开搜图 bot 酱网页", systemImage: "photo.badge.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                openExternalURL("https://saucenao.com/")
            } label: {
                ToolRow(title: "图片搜索 [SauceNAO]", subtitle: "打开 SauceNAO 网页", systemImage: "camera.metering.matrix")
            }
            .buttonStyle(.plain)

            Button {
                requestInput(.openLink)
            } label: {
                ToolRow(title: "打开链接", subtitle: "解析各平台分享链接", systemImage: "link")
            }
            .buttonStyle(.plain)

            Button {
                requestInput(.jmComicID)
            } label: {
                ToolRow(title: "JM 车牌号", subtitle: "输入 jm123 或 123 并打开详情", systemImage: "number")
            }
            .buttonStyle(.plain)
        }
    }

    private func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else {
            showError("链接无效")
            return
        }
        openURL(url)
    }
}

private struct EhentaiSubscriptionPage: View {
    let service: ComicContentService
    @StateObject private var viewModel: EhentaiSubscriptionViewModel

    init(service: ComicContentService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: EhentaiSubscriptionViewModel(service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingComicListView(accentColor: ComicPlatform.eHentai.accentColor)
            case .loaded(let comics):
                if comics.isEmpty {
                    ContentUnavailableView("暂无订阅", systemImage: "antenna.radiowaves.left.and.right", description: Text("E-Hentai watched 暂无返回内容"))
                } else {
                    ComicListSection(
                        comics: comics,
                        service: service,
                        isLoadingMore: viewModel.isLoadingMore,
                        hasMore: viewModel.hasMore
                    ) {
                        Task { await viewModel.loadMore() }
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.load(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("EH 订阅")
        .picaxNavigationBarTitleDisplayModeInline()
        .toolbar {
            ToolbarItem(placement: .picaxTopBarTrailing) {
                Button {
                    Task { await viewModel.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

@MainActor
private final class EhentaiSubscriptionViewModel: ObservableObject {
    @Published private(set) var state: EhentaiSubscriptionLoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false

    private let service: ComicContentService
    private var currentPage = 0
    private var loadedIDs = Set<String>()

    init(service: ComicContentService) {
        self.service = service
    }

    func load(force: Bool = false) async {
        if case .loaded = state, !force {
            return
        }

        state = .loading
        currentPage = 0
        loadedIDs.removeAll()
        hasMore = false
        isLoadingMore = false
        do {
            let comics = try await service.loadEhentaiSubscription(page: 1)
            currentPage = 1
            loadedIDs = Set(comics.map(\.id))
            hasMore = !comics.isEmpty
            state = .loaded(comics)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, case .loaded(let comics) = state else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let newComics = try await service.loadEhentaiSubscription(page: nextPage)
            currentPage = nextPage
            let uniqueComics = newComics.filter { loadedIDs.insert($0.id).inserted }
            hasMore = !newComics.isEmpty && !uniqueComics.isEmpty
            guard !uniqueComics.isEmpty else { return }
            state = .loaded(comics + uniqueComics)
        } catch {
            hasMore = false
        }
    }
}

private enum EhentaiSubscriptionLoadState {
    case idle
    case loading
    case loaded([ComicListItem])
    case failed(String)
}

enum HomeToolInputTarget: Identifiable {
    case openLink
    case jmComicID

    var id: String {
        switch self {
        case .openLink:
            "openLink"
        case .jmComicID:
            "jmComicID"
        }
    }

    var title: String {
        switch self {
        case .openLink:
            "打开链接"
        case .jmComicID:
            "JM 车牌号"
        }
    }

    var prompt: String {
        switch self {
        case .openLink:
            "输入链接"
        case .jmComicID:
            "输入禁漫车牌号"
        }
    }

    var placeholder: String {
        switch self {
        case .openLink:
            "https://"
        case .jmComicID:
            "jm123456"
        }
    }

    var keyboard: PicaXKeyboardType {
        switch self {
        case .openLink:
            .url
        case .jmComicID:
            .asciiCapable
        }
    }
}

enum HomeToolLinkParser {
    static func item(from rawValue: String) -> Result<ComicListItem, HomeToolLinkParseError> {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(HomeToolLinkParseError(message: "链接不能为空")) }
        if let id = jmComicID(from: trimmed) {
            return .success(jmComicItem(id: id))
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased() else {
            return .failure(HomeToolLinkParseError(message: "不支持的链接"))
        }

        if matchesHost(host, platform: .eHentai, defaults: ["e-hentai.org", "exhentai.org"]) {
            guard url.path.contains("/g/") else { return .failure(HomeToolLinkParseError(message: "不是有效的 E-Hentai 画廊链接")) }
            return .success(ehentaiItem(url: normalizedEhentaiURL(url)))
        }

        if matchesHost(host, platform: .nhentai, defaults: ["nhentai.net", "nhentai.xxx"]) {
            guard let id = firstNumber(in: url.path) else { return .failure(HomeToolLinkParseError(message: "不是有效的 NHentai 链接")) }
            return .success(nhentaiItem(id: id))
        }

        if matchesHost(host, platform: .hitomi, defaults: ["hitomi.la"]) {
            guard let id = firstNumber(in: url.absoluteString) else { return .failure(HomeToolLinkParseError(message: "不是有效的 Hitomi 链接")) }
            return .success(hitomiItem(id: id))
        }

        if matchesHost(host, platform: .htManga, defaults: ["www.wnacg.com", "wnacg.com", "www.htmanga3.top", "htmanga3.top"]) {
            guard let id = htMangaID(from: url) else { return .failure(HomeToolLinkParseError(message: "不是有效的 HT Manga 链接")) }
            return .success(htMangaItem(id: id))
        }

        if isJmComicHost(host), let id = firstNumber(in: url.path.isEmpty ? url.absoluteString : url.path) {
            return .success(jmComicItem(id: id))
        }
        return .failure(HomeToolLinkParseError(message: "暂不支持这个链接"))
    }

    static func jmComicID(from rawValue: String) -> String? {
        let compact = rawValue.filter { !$0.isWhitespace }
        let normalized = compact.lowercased().hasPrefix("jm") ? String(compact.dropFirst(2)) : compact
        guard !normalized.isEmpty, normalized.allSatisfy(\.isNumber) else { return nil }
        return normalized
    }

    static func jmComicItem(id: String) -> ComicListItem {
        ComicListItem(
            id: id,
            platform: .jmComic,
            title: "JM\(id)",
            subtitle: id,
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }

    private static func htMangaItem(id: String) -> ComicListItem {
        ComicListItem(
            id: id,
            platform: .htManga,
            title: "HT Manga \(id)",
            subtitle: id,
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }

    private static func ehentaiItem(url: URL) -> ComicListItem {
        ComicListItem(
            id: url.absoluteString,
            platform: .eHentai,
            title: "E-Hentai 画廊",
            subtitle: url.host ?? "E-Hentai",
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }

    private static func nhentaiItem(id: String) -> ComicListItem {
        ComicListItem(
            id: id,
            platform: .nhentai,
            title: "NHentai \(id)",
            subtitle: id,
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }

    private static func hitomiItem(id: String) -> ComicListItem {
        ComicListItem(
            id: id,
            platform: .hitomi,
            title: "Hitomi \(id)",
            subtitle: id,
            coverURLString: "",
            tags: [],
            pageCount: nil,
            likesCount: nil,
            favoriteDate: nil
        )
    }

    private static func normalizedEhentaiURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let frontendURL = URL(string: PlatformFeatureSettings.frontendBaseURL(for: .eHentai)) {
            components?.scheme = frontendURL.scheme ?? "https"
            components?.host = frontendURL.host ?? "e-hentai.org"
        } else {
            components?.scheme = "https"
            components?.host = "e-hentai.org"
        }
        return components?.url ?? url
    }

    private static func firstNumber(in value: String) -> String? {
        var result = ""
        for character in value {
            if character.isNumber {
                result.append(character)
            } else if !result.isEmpty {
                return result
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func htMangaID(from url: URL) -> String? {
        let path = url.path.lowercased()
        if let range = path.range(of: "aid-") {
            return leadingNumber(in: String(path[range.upperBound...]))
        }
        return firstNumber(in: path)
    }

    private static func leadingNumber(in value: String) -> String? {
        let result = value.prefix { $0.isNumber }
        return result.isEmpty ? nil : String(result)
    }

    private static func isJmComicHost(_ host: String) -> Bool {
        matchesHost(host, platform: .jmComic, defaults: []) || host.contains("18comic") || host.contains("jmcomic")
    }

    private static func matchesHost(_ host: String, platform: ComicPlatform, defaults: Set<String>) -> Bool {
        if defaults.contains(host) {
            return true
        }
        guard let configuredHost = URL(string: PlatformFeatureSettings.frontendBaseURL(for: platform))?.host?.lowercased() else {
            return false
        }
        return host == configuredHost
    }
}

struct HomeToolLinkParseError: Error {
    let message: String
}

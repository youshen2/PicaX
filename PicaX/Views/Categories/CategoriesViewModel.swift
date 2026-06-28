import Combine
import Foundation

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published private(set) var state: CategoriesLoadState = .idle

    private let service: ComicContentService
    private var currentPlatform: ComicPlatform?
    private let pageSize = 12

    init(service: ComicContentService) {
        self.service = service
    }

    var canLoadMore: Bool {
        guard case .loaded(let items, let visibleCount) = state else { return false }
        return visibleCount < items.count
    }

    func load(platform: ComicPlatform, account: PlatformAccount?, force: Bool = false) async {
        if currentPlatform == platform, !force, case .loaded = state {
            return
        }

        currentPlatform = platform
        state = .loading

        do {
            let items = try await service.loadCategories(platform: platform, account: account)
            let initialVisibleCount = items.contains { $0.groupTitle != nil } ? items.count : min(pageSize, items.count)
            state = .loaded(items, visibleCount: initialVisibleCount)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreCategories() {
        guard case .loaded(let items, let visibleCount) = state else { return }
        state = .loaded(items, visibleCount: min(visibleCount + pageSize, items.count))
    }
}

enum CategoriesLoadState {
    case idle
    case loading
    case loaded([ComicCategoryItem], visibleCount: Int)
    case failed(String)
}

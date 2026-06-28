import SwiftUI

struct LazyLocalForEach<Item: Identifiable, Content: View>: View where Item.ID: Equatable {
    let items: [Item]
    private let initialCount: Int
    private let pageSize: Int
    private let row: (Item) -> Content

    @State private var visibleCount: Int

    init(
        items: [Item],
        initialCount: Int = 48,
        pageSize: Int = 48,
        @ViewBuilder row: @escaping (Item) -> Content
    ) {
        let safeInitialCount = max(initialCount, 1)
        self.items = items
        self.initialCount = safeInitialCount
        self.pageSize = max(pageSize, 1)
        self.row = row
        _visibleCount = State(initialValue: safeInitialCount)
    }

    var body: some View {
        let visibleItems = Array(items.prefix(currentVisibleCount))

        ForEach(visibleItems) { item in
            row(item)
                .onAppear {
                    loadMoreIfNeeded(appearing: item, visibleItems: visibleItems)
                }
        }
        .onChange(of: items.map(\.id)) { oldIDs, newIDs in
            updateVisibleCount(oldIDs: oldIDs, newIDs: newIDs)
        }
    }

    private var currentVisibleCount: Int {
        min(max(visibleCount, 0), items.count)
    }

    private func loadMoreIfNeeded(appearing item: Item, visibleItems: [Item]) {
        guard item.id == visibleItems.last?.id,
              visibleCount < items.count else {
            return
        }
        visibleCount = min(items.count, visibleCount + pageSize)
    }

    private func updateVisibleCount(oldIDs: [Item.ID], newIDs: [Item.ID]) {
        let minimumVisibleCount = min(initialCount, max(newIDs.count, 1))
        let comparedPrefixCount = min(visibleCount, oldIDs.count, newIDs.count)
        let visiblePrefixChanged = Array(oldIDs.prefix(comparedPrefixCount)) != Array(newIDs.prefix(comparedPrefixCount))

        if visiblePrefixChanged {
            visibleCount = minimumVisibleCount
        } else if visibleCount > newIDs.count {
            visibleCount = max(minimumVisibleCount, newIDs.count)
        }
    }
}

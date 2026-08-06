#if os(iOS)
import SwiftUI
import UIKit

/// A single-page SwiftUI host backed by UIKit's native page-curl transition.
struct ReaderPageCurlView<Page: View>: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var selectedIndex: Int
    let contentID: String
    private let page: (Int) -> Page

    init(
        pageCount: Int,
        selectedIndex: Binding<Int>,
        contentID: String,
        @ViewBuilder page: @escaping (Int) -> Page
    ) {
        self.pageCount = max(pageCount, 0)
        _selectedIndex = selectedIndex
        self.contentID = contentID
        self.page = page
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.isDoubleSided = false
        pageViewController.view.backgroundColor = .black
        context.coordinator.attach(to: pageViewController)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.update(parent: self, pageViewController: pageViewController)
    }

    static func dismantleUIViewController(
        _ pageViewController: UIPageViewController,
        coordinator: Coordinator
    ) {
        pageViewController.dataSource = nil
        pageViewController.delegate = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        private var parent: ReaderPageCurlView
        private weak var pageViewController: UIPageViewController?
        private var pageControllers: [Int: UIHostingController<Page>] = [:]
        private var indexesByController: [ObjectIdentifier: Int] = [:]
        private var representedContentID: String
        private var visibleIndex: Int?
        private var isTransitioning = false

        init(parent: ReaderPageCurlView) {
            self.parent = parent
            representedContentID = parent.contentID
        }

        func attach(to pageViewController: UIPageViewController) {
            self.pageViewController = pageViewController
            resetContent(in: pageViewController)
        }

        func update(parent: ReaderPageCurlView, pageViewController: UIPageViewController) {
            self.parent = parent
            self.pageViewController = pageViewController

            guard representedContentID == parent.contentID else {
                representedContentID = parent.contentID
                resetContent(in: pageViewController)
                return
            }

            refreshCachedPages()
            guard parent.pageCount > 0, !isTransitioning else { return }
            showSelectedPage(in: pageViewController, animated: true)
        }

        func detach() {
            pageViewController = nil
            pageControllers.removeAll()
            indexesByController.removeAll()
            visibleIndex = nil
            isTransitioning = false
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(for: viewController) else { return nil }
            return controller(for: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = index(for: viewController) else { return nil }
            return controller(for: index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isTransitioning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            guard let current = pageViewController.viewControllers?.first,
                  let index = index(for: current) else {
                return
            }

            visibleIndex = index
            if completed, parent.selectedIndex != index {
                parent.selectedIndex = index
            }
            refreshCachedPages()
            pruneCache(around: index)
            showSelectedPage(in: pageViewController, animated: true)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            spineLocationFor orientation: UIInterfaceOrientation
        ) -> UIPageViewController.SpineLocation {
            pageViewController.isDoubleSided = false
            return .min
        }

        private func resetContent(in pageViewController: UIPageViewController) {
            pageControllers.removeAll()
            indexesByController.removeAll()
            isTransitioning = false

            guard parent.pageCount > 0 else {
                visibleIndex = nil
                pageViewController.setViewControllers(nil, direction: .forward, animated: false)
                return
            }

            let index = normalized(parent.selectedIndex)
            guard let controller = controller(for: index) else { return }
            visibleIndex = index
            pageViewController.setViewControllers([controller], direction: .forward, animated: false)
            pruneCache(around: index)
        }

        private func showSelectedPage(in pageViewController: UIPageViewController, animated: Bool) {
            let targetIndex = normalized(parent.selectedIndex)
            let currentIndex = pageViewController.viewControllers?.first.flatMap(index(for:)) ?? visibleIndex
            guard currentIndex != targetIndex,
                  let controller = controller(for: targetIndex) else {
                return
            }

            let direction: UIPageViewController.NavigationDirection = if let currentIndex,
                                                                         targetIndex < currentIndex {
                .reverse
            } else {
                .forward
            }
            isTransitioning = true
            pageViewController.setViewControllers(
                [controller],
                direction: direction,
                animated: animated
            ) { [weak self, weak pageViewController] completed in
                guard let self, let pageViewController else { return }
                self.isTransitioning = false
                if completed {
                    self.visibleIndex = targetIndex
                }
                self.pruneCache(around: self.visibleIndex ?? targetIndex)
                self.showSelectedPage(in: pageViewController, animated: animated)
            }
        }

        private func controller(for index: Int) -> UIHostingController<Page>? {
            guard (0..<parent.pageCount).contains(index) else { return nil }
            if let controller = pageControllers[index] {
                controller.rootView = parent.page(index)
                return controller
            }

            let controller = UIHostingController(rootView: parent.page(index))
            controller.view.backgroundColor = .black
            pageControllers[index] = controller
            indexesByController[ObjectIdentifier(controller)] = index
            return controller
        }

        private func index(for viewController: UIViewController) -> Int? {
            indexesByController[ObjectIdentifier(viewController)]
        }

        private func normalized(_ index: Int) -> Int {
            min(max(index, 0), max(parent.pageCount - 1, 0))
        }

        private func refreshCachedPages() {
            for index in Array(pageControllers.keys) {
                guard (0..<parent.pageCount).contains(index),
                      let controller = pageControllers[index] else {
                    removeCachedController(at: index)
                    continue
                }
                controller.rootView = parent.page(index)
            }
        }

        private func pruneCache(around index: Int) {
            let retainedIndexes = Set(max(index - 2, 0)...min(index + 2, max(parent.pageCount - 1, 0)))
            for cachedIndex in Array(pageControllers.keys) where !retainedIndexes.contains(cachedIndex) {
                removeCachedController(at: cachedIndex)
            }
        }

        private func removeCachedController(at index: Int) {
            guard let controller = pageControllers.removeValue(forKey: index) else { return }
            indexesByController.removeValue(forKey: ObjectIdentifier(controller))
        }
    }
}
#endif

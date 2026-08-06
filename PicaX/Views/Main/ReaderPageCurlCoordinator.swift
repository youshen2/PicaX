#if os(iOS)
import SwiftUI
import UIKit

/// Owns UIKit page-curl state without specializing its lifetime for a SwiftUI page type.
@MainActor
final class ReaderPageCurlCoordinator: NSObject,
                                       UIPageViewControllerDataSource,
                                       UIPageViewControllerDelegate {
    struct Configuration {
        let pageCount: Int
        let selectedIndex: Binding<Int>
        let contentID: String
        let makeController: (Int) -> UIViewController
        let updateController: (UIViewController, Int) -> Void
    }

    private var configuration: Configuration
    private weak var pageViewController: UIPageViewController?
    private var pageControllers: [Int: UIViewController] = [:]
    private var indexesByController: [ObjectIdentifier: Int] = [:]
    private var representedContentID: String
    private var visibleIndex: Int?
    private var isTransitioning = false

    init(configuration: Configuration) {
        self.configuration = configuration
        representedContentID = configuration.contentID
    }

    func attach(to pageViewController: UIPageViewController) {
        self.pageViewController = pageViewController
        resetContent(in: pageViewController)
    }

    func update(configuration: Configuration, pageViewController: UIPageViewController) {
        self.configuration = configuration
        self.pageViewController = pageViewController

        guard representedContentID == configuration.contentID else {
            representedContentID = configuration.contentID
            resetContent(in: pageViewController)
            return
        }

        refreshCachedPages()
        guard configuration.pageCount > 0, !isTransitioning else { return }
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
        if completed, configuration.selectedIndex.wrappedValue != index {
            configuration.selectedIndex.wrappedValue = index
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

        guard configuration.pageCount > 0 else {
            visibleIndex = nil
            pageViewController.setViewControllers(nil, direction: .forward, animated: false)
            return
        }

        let index = normalized(configuration.selectedIndex.wrappedValue)
        guard let controller = controller(for: index) else { return }
        visibleIndex = index
        pageViewController.setViewControllers([controller], direction: .forward, animated: false)
        pruneCache(around: index)
    }

    private func showSelectedPage(in pageViewController: UIPageViewController, animated: Bool) {
        let targetIndex = normalized(configuration.selectedIndex.wrappedValue)
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

    private func controller(for index: Int) -> UIViewController? {
        guard (0..<configuration.pageCount).contains(index) else { return nil }
        if let controller = pageControllers[index] {
            configuration.updateController(controller, index)
            return controller
        }

        let controller = configuration.makeController(index)
        controller.view.backgroundColor = .black
        pageControllers[index] = controller
        indexesByController[ObjectIdentifier(controller)] = index
        return controller
    }

    private func index(for viewController: UIViewController) -> Int? {
        indexesByController[ObjectIdentifier(viewController)]
    }

    private func normalized(_ index: Int) -> Int {
        min(max(index, 0), max(configuration.pageCount - 1, 0))
    }

    private func refreshCachedPages() {
        for index in Array(pageControllers.keys) {
            guard (0..<configuration.pageCount).contains(index),
                  let controller = pageControllers[index] else {
                removeCachedController(at: index)
                continue
            }
            configuration.updateController(controller, index)
        }
    }

    private func pruneCache(around index: Int) {
        let retainedIndexes = Set(
            max(index - 2, 0)...min(index + 2, max(configuration.pageCount - 1, 0))
        )
        for cachedIndex in Array(pageControllers.keys) where !retainedIndexes.contains(cachedIndex) {
            removeCachedController(at: cachedIndex)
        }
    }

    private func removeCachedController(at index: Int) {
        guard let controller = pageControllers.removeValue(forKey: index) else { return }
        indexesByController.removeValue(forKey: ObjectIdentifier(controller))
    }
}
#endif

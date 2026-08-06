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

    func makeCoordinator() -> ReaderPageCurlCoordinator {
        ReaderPageCurlCoordinator(configuration: coordinatorConfiguration)
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
        context.coordinator.update(
            configuration: coordinatorConfiguration,
            pageViewController: pageViewController
        )
    }

    static func dismantleUIViewController(
        _ pageViewController: UIPageViewController,
        coordinator: ReaderPageCurlCoordinator
    ) {
        pageViewController.dataSource = nil
        pageViewController.delegate = nil
        coordinator.detach()
    }

    private var coordinatorConfiguration: ReaderPageCurlCoordinator.Configuration {
        let page = page
        return ReaderPageCurlCoordinator.Configuration(
            pageCount: pageCount,
            selectedIndex: $selectedIndex,
            contentID: contentID,
            makeController: { index in
                UIHostingController(rootView: page(index))
            },
            updateController: { controller, index in
                guard let hostingController = controller as? UIHostingController<Page> else {
                    assertionFailure("Unexpected page controller type")
                    return
                }
                hostingController.rootView = page(index)
            }
        )
    }
}
#endif

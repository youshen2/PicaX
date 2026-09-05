#if os(iOS)
import SwiftUI
import UIKit

/// Reconcile interrupted transitions with the visibility requested by the active page.
struct PicaxTabBarVisibilityBridge: UIViewControllerRepresentable {
    let hidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidden: hidden)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(hidden: hidden)
    }

    final class Controller: UIViewController {
        private var hidden: Bool
        private var isAppearing = false

        init(hidden: Bool) {
            self.hidden = hidden
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isAppearing = true
            if hidden {
                applyIfVisible()
            }
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                self?.applyIfVisible()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isAppearing = true
            applyIfVisible()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isAppearing = false
        }

        func update(hidden: Bool) {
            guard self.hidden != hidden else { return }
            self.hidden = hidden
            applyIfVisible()
        }

        private func applyIfVisible() {
            guard isAppearing,
                  viewIfLoaded?.window != nil,
                  let navigationController,
                  let top = navigationController.topViewController,
                  let tabBarController else { return }
            var ancestor: UIViewController? = self
            while let controller = ancestor, controller !== top {
                ancestor = controller.parent
            }
            guard ancestor === top else { return }
            // A root retained underneath a pushed page must not restore the bar.
            guard hidden || navigationController.viewControllers.count == 1 else { return }
            if #available(iOS 18.0, *) {
                tabBarController.setTabBarHidden(hidden, animated: false)
            } else {
                tabBarController.tabBar.isHidden = hidden
            }
        }
    }
}
#endif

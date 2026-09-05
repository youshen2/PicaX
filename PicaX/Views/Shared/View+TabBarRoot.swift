import SwiftUI

extension View {
    @ViewBuilder
    func picaxTabBarRoot() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            toolbar(.visible, for: .tabBar)
                .background(PicaxTabBarRootBridge())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
import UIKit

/// SwiftUI can leave the tab bar hidden when an interactive pop interrupts a zoom push.
/// Restore it only after this root actually becomes the visible navigation controller.
private struct PicaxTabBarRootBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                self?.restoreIfVisible()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreIfVisible()
        }

        private func restoreIfVisible() {
            guard viewIfLoaded?.window != nil,
                  let navigationController,
                  navigationController.viewControllers.count == 1,
                  let top = navigationController.topViewController,
                  let tabBarController else { return }
            var ancestor: UIViewController? = self
            while let controller = ancestor, controller !== top {
                ancestor = controller.parent
            }
            guard ancestor === top else { return }
            if #available(iOS 18.0, *) {
                tabBarController.setTabBarHidden(false, animated: false)
            } else {
                tabBarController.tabBar.isHidden = false
            }
        }
    }
}
#endif

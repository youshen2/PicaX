import SwiftUI

#if os(iOS)
import UIKit
#endif

extension View {
    @ViewBuilder
    func picaxHidesTabBar(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            toolbar(hidden ? .hidden : .visible, for: .tabBar)
        } else {
            modifier(PicaxLegacyTabBarVisibilityModifier(hidden: hidden))
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func picaxInsetGroupedListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }
}

#if os(iOS)
@MainActor
private final class PicaxLegacyTabBarVisibilityRegistry {
    static let shared = PicaxLegacyTabBarVisibilityRegistry()

    private var hiddenRequests: Set<UUID> = []
    private weak var tabBar: UITabBar?

    func update(
        requestID: UUID,
        hidden: Bool,
        tabBarController: UITabBarController?
    ) {
        if let tabBar = tabBarController?.tabBar {
            self.tabBar = tabBar
        }
        if hidden {
            hiddenRequests.insert(requestID)
        } else {
            hiddenRequests.remove(requestID)
        }
        tabBar?.isHidden = !hiddenRequests.isEmpty
    }
}

private struct PicaxLegacyTabBarVisibilityBridge: UIViewControllerRepresentable {
    let requestID: UUID
    let hidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(requestID: requestID, hidden: hidden)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(hidden: hidden)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.deactivate()
    }

    final class Controller: UIViewController {
        private let requestID: UUID
        private var hidden: Bool
        private var isActive = false

        init(requestID: UUID, hidden: Bool) {
            self.requestID = requestID
            self.hidden = hidden
            super.init(nibName: nil, bundle: nil)
            view.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            activate()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            activate()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            deactivate()
        }

        func update(hidden: Bool) {
            self.hidden = hidden
            guard isActive else { return }
            applyVisibility()
        }

        func activate() {
            isActive = true
            applyVisibility()
        }

        func deactivate() {
            guard isActive else { return }
            isActive = false
            PicaxLegacyTabBarVisibilityRegistry.shared.update(
                requestID: requestID,
                hidden: false,
                tabBarController: tabBarController
            )
        }

        private func applyVisibility() {
            PicaxLegacyTabBarVisibilityRegistry.shared.update(
                requestID: requestID,
                hidden: hidden,
                tabBarController: tabBarController
            )
        }
    }
}

private struct PicaxLegacyTabBarVisibilityModifier: ViewModifier {
    @State private var requestID = UUID()
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .background {
                PicaxLegacyTabBarVisibilityBridge(
                    requestID: requestID,
                    hidden: hidden
                )
            }
    }
}
#endif

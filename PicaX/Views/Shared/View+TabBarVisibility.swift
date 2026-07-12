import SwiftUI

#if os(iOS)
import UIKit
#endif

private let picaxTabBarVisibilityAnimation = Animation.easeInOut(duration: 0.3)

private struct PicaxTabBarVisibilityActionKey: EnvironmentKey {
    static let defaultValue: (UUID, Bool) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var picaxSetTabBarHidden: (UUID, Bool) -> Void {
        get { self[PicaxTabBarVisibilityActionKey.self] }
        set { self[PicaxTabBarVisibilityActionKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func picaxHidesTabBar(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        modifier(PicaxTabBarVisibilityModifier(hidden: hidden))
        #else
        self
        #endif
    }

    @ViewBuilder
    func picaxTabBarVisibilityHost(
        isVisible: Bool,
        setHidden: @escaping (UUID, Bool) -> Void
    ) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            toolbar(isVisible ? .visible : .hidden, for: .tabBar)
                .animation(picaxTabBarVisibilityAnimation, value: isVisible)
                .environment(\.picaxSetTabBarHidden, setHidden)
        } else {
            background(PicaxLegacyTabBarVisibilityBridge(isVisible: isVisible))
                .animation(picaxTabBarVisibilityAnimation, value: isVisible)
                .environment(\.picaxSetTabBarHidden, setHidden)
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
private struct PicaxLegacyTabBarVisibilityBridge: UIViewControllerRepresentable {
    let isVisible: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(isVisible: isVisible)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isVisible = isVisible
        controller.updateTabBarVisibility()
    }

    final class Controller: UIViewController {
        var isVisible: Bool

        init(isVisible: Bool) {
            self.isVisible = isVisible
            super.init(nibName: nil, bundle: nil)
            view.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateTabBarVisibility()
        }

        func updateTabBarVisibility() {
            tabBarController?.tabBar.isHidden = !isVisible
        }
    }
}

private struct PicaxTabBarVisibilityModifier: ViewModifier {
    @Environment(\.picaxSetTabBarHidden) private var setTabBarHidden
    @State private var requestID = UUID()
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                setTabBarHidden(requestID, hidden)
            }
            .onDisappear {
                setTabBarHidden(requestID, false)
            }
            .onChange(of: hidden) { newValue in
                setTabBarHidden(requestID, newValue)
            }
    }
}
#endif

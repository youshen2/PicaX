import SwiftUI

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
        toolbar(isVisible ? .visible : .hidden, for: .tabBar)
            .animation(picaxTabBarVisibilityAnimation, value: isVisible)
            .environment(\.picaxSetTabBarHidden, setHidden)
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
            .onChange(of: hidden) { _, newValue in
                setTabBarHidden(requestID, newValue)
            }
    }
}
#endif

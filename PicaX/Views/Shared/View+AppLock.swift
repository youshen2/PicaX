import SwiftUI

extension View {
    @ViewBuilder
    func picaxAppLockProtection() -> some View {
        #if os(iOS)
        modifier(AppLockProtectionModifier())
        #else
        self
        #endif
    }
}

#if os(iOS)
import UIKit

private struct AppLockProtectionModifier: ViewModifier {
    @ObservedObject private var lock = AppLockService.shared
    func body(content: Content) -> some View {
        content.background(AppLockWindowBridge(lock: lock, isPresented: lock.shieldsContent))
    }
}

/// A scene-owned window covers navigation and modal presentations without destroying either.
private struct AppLockWindowBridge: UIViewRepresentable {
    let lock: AppLockService
    let isPresented: Bool
    func makeUIView(context: Context) -> AnchorView { AnchorView(lock: lock) }
    func updateUIView(_ view: AnchorView, context: Context) { view.setPresented(isPresented) }
    static func dismantleUIView(_ view: AnchorView, coordinator: Void) { view.tearDown() }

    final class AnchorView: UIView {
        private let lock: AppLockService
        private var shield: UIWindow?
        private weak var previousKeyWindow: UIWindow?
        private var isPresented = false

        init(lock: AppLockService) {
            self.lock = lock
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateShield()
        }

        func setPresented(_ presented: Bool) {
            isPresented = presented
            updateShield()
        }

        func tearDown() {
            if shield?.isKeyWindow == true { previousKeyWindow?.makeKey() }
            shield?.isHidden = true
            previousKeyWindow = nil
            shield?.rootViewController = nil
            shield = nil
        }

        private func updateShield() {
            guard let scene = window?.windowScene else { tearDown(); return }
            if shield?.windowScene !== scene { tearDown() }
            if isPresented, shield == nil {
                let shield = UIWindow(windowScene: scene)
                shield.windowLevel = .alert + 1
                shield.rootViewController = UIHostingController(rootView: AppLockScreen(lock: lock))
                shield.backgroundColor = .systemBackground
                self.shield = shield
            }
            if isPresented, shield?.isHidden == true {
                previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
                shield?.makeKeyAndVisible()
            } else if !isPresented {
                if shield?.isKeyWindow == true { previousKeyWindow?.makeKey() }
                shield?.isHidden = true
                previousKeyWindow = nil
            }
        }
    }
}

private struct AppLockScreen: View {
    @ObservedObject var lock: AppLockService
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
            Text("PicaX 已锁定").font(.title2.bold())
            if !lock.isObscured {
                if lock.isAuthenticating {
                    ProgressView("正在验证身份")
                } else {
                    Button("解锁") { Task { await lock.unlock() } }.buttonStyle(.borderedProminent)
                }
                if let message = lock.errorMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .privacySensitive()
    }
}
#endif

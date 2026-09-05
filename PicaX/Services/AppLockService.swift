#if os(iOS)
import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockService: ObservableObject {
    static let shared = AppLockService()
    static let enabledKey = "settings.appLock.enabled"
    static let timeoutKey = "settings.appLock.backgroundTimeout"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var isObscured = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?
    private var backgroundDate: Date?
    private var phase: ScenePhase = .inactive
    private var context: LAContext?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    var shieldsContent: Bool { isEnabled && (isLocked || isObscured) }

    func scenePhaseChanged(_ phase: ScenePhase) {
        self.phase = phase
        guard isEnabled else { return }
        switch phase {
        case .inactive:
            isObscured = true
        case .background:
            isObscured = true
            if backgroundDate == nil { backgroundDate = Date() }
            context?.invalidate()
        case .active:
            if let backgroundDate {
                let timeout = max(UserDefaults.standard.double(forKey: Self.timeoutKey), 0)
                if Date().timeIntervalSince(backgroundDate) >= timeout { isLocked = true }
            }
            backgroundDate = nil
            isObscured = false
            // Cancellation leaves the unlock button available without prompting in a loop.
        @unknown default: break
        }
    }

    func unlock() async {
        guard isLocked, phase == .active else { return }
        if await authenticate(reason: "解锁 PicaX 以查看内容"), phase != .background {
            isLocked = false
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        guard await authenticate(reason: enabled ? "验证身份以启用 PicaX 应用锁" : "验证身份以关闭 PicaX 应用锁") else { return }
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = false
        isObscured = false
        backgroundDate = nil
    }

    func lockNow() {
        guard isEnabled else { return }
        isLocked = true
        errorMessage = nil
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        errorMessage = nil
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = error?.localizedDescription ?? "请先在设备设置中配置密码或生物识别。"
            return false
        }
        self.context = context
        isAuthenticating = true
        defer { isAuthenticating = false; self.context = nil }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
#endif

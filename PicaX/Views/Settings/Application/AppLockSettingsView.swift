#if os(iOS)
import SwiftUI

struct AppLockSettingsView: View {
    @ObservedObject private var lock = AppLockService.shared
    @AppStorage(AppLockService.timeoutKey) private var timeout = 0

    var body: some View {
        Form {
            Section {
                Toggle("应用锁", isOn: Binding(get: { lock.isEnabled }, set: { enabled in
                    Task { await lock.setEnabled(enabled) }
                }))
                .disabled(lock.isAuthenticating)
                if lock.isAuthenticating { ProgressView("正在验证身份") }
            } footer: {
                Text("启用后，启动应用需通过 Face ID、Touch ID 或设备密码验证。开关应用锁也需要验证身份。")
            }
            if lock.isEnabled {
                Section {
                    Picker("后台多久后锁定", selection: $timeout) {
                        Text("立即").tag(0)
                        Text("1 分钟").tag(60)
                        Text("5 分钟").tag(300)
                        Text("15 分钟").tag(900)
                    }
                    Button("立即锁定") { lock.lockNow() }
                } footer: {
                    Text("离开应用时会立即遮挡内容，超过所选时间后再次打开需要解锁。")
                }
            }
            if let message = lock.errorMessage { Text(message).foregroundStyle(.secondary) }
        }
        .navigationTitle("应用锁")
        .picaxHidesTabBar()
    }
}
#endif

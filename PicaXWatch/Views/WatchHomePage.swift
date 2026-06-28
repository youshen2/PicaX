import SwiftUI

struct WatchHomePage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore

    var body: some View {
        List {
            Section("同步") {
                WatchValueRow(
                    title: accountSyncStore.snapshot.hasSyncedAccounts ? "已同步" : "等待同步",
                    subtitle: syncSubtitle,
                    systemImage: accountSyncStore.snapshot.hasSyncedAccounts ? "checkmark.icloud" : "icloud.slash",
                    tint: accountSyncStore.snapshot.hasSyncedAccounts ? .green : .secondary
                )
            }
        }
        .navigationTitle("主页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }

    private var syncSubtitle: String {
        guard accountSyncStore.snapshot.updatedAt > .distantPast else {
            return "手机端只负责同步平台账号信息"
        }
        return "上次同步 \(accountSyncStore.snapshot.updatedAt.formatted(date: .numeric, time: .shortened))"
    }
}

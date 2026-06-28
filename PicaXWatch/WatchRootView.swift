import SwiftUI

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("PicaX")
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
    }
}

private struct WatchSettingsView: View {
    var body: some View {
        List {
            NavigationLink {
                WatchAccountManagementView()
            } label: {
                Label("账号管理", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("设置")
    }
}

private struct WatchAccountManagementView: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore

    var body: some View {
        List {
            Section("PicaX 账号") {
                if let account = accountSyncStore.snapshot.localAccount {
                    WatchValueRow(title: account.displayName, subtitle: account.email)
                    if let lastLoginAt = account.lastLoginAt {
                        WatchValueRow(title: "上次登录", subtitle: lastLoginAt.formatted(date: .numeric, time: .shortened))
                    }
                } else {
                    Text(accountSyncStore.snapshot.localAccountCount > 0 ? "未在 iPhone 登录" : "未同步账号")
                        .foregroundStyle(.secondary)
                }
            }

            Section("平台账号") {
                if accountSyncStore.snapshot.platformAccounts.isEmpty {
                    Text("暂无已登录平台")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountSyncStore.snapshot.platformAccounts) { account in
                        WatchValueRow(
                            title: account.title,
                            subtitle: "\(account.displayName) · \(account.credentialState)"
                        )
                    }
                }
            }

            Section {
                Button {
                    accountSyncStore.requestRefresh()
                } label: {
                    Label("从 iPhone 同步", systemImage: "arrow.clockwise")
                }

                if accountSyncStore.snapshot.updatedAt > .distantPast {
                    WatchValueRow(
                        title: "同步时间",
                        subtitle: accountSyncStore.snapshot.updatedAt.formatted(date: .numeric, time: .shortened)
                    )
                }

                if let errorMessage = accountSyncStore.lastErrorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("账号管理")
    }
}

private struct WatchValueRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchAccountSyncStore.preview)
}

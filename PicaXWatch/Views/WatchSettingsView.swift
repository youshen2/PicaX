import SwiftUI
import WatchConnectivity

struct WatchSettingsView: View {
    var body: some View {
        List {
            Section("账号") {
                NavigationLink {
                    WatchPlatformAccountsPage()
                } label: {
                    Label("账号管理", systemImage: "person.crop.circle")
                }
            }

            Section("页面") {
                NavigationLink {
                    WatchDiscoverySettingsPage()
                } label: {
                    Label("发现", systemImage: "safari")
                }

                NavigationLink {
                    WatchTagsSettingsPage()
                } label: {
                    Label("标签", systemImage: "tag")
                }

                NavigationLink {
                    WatchListSettingsPage()
                } label: {
                    Label("列表", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("设置")
    }
}

struct WatchPlatformAccountsPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore

    var body: some View {
        List {
            Section("同步") {
                Button {
                    accountSyncStore.requestRefresh()
                } label: {
                    Label("从 iPhone 同步", systemImage: "arrow.clockwise")
                }

                Button {
                    accountSyncStore.syncLocalFavorites()
                } label: {
                    Label("同步本地收藏", systemImage: "heart")
                }

                WatchValueRow(title: "连接状态", subtitle: syncStateText, systemImage: "iphone.gen3.radiowaves.left.and.right")

                if accountSyncStore.snapshot.updatedAt > .distantPast {
                    WatchValueRow(
                        title: "同步时间",
                        subtitle: accountSyncStore.snapshot.updatedAt.formatted(date: .numeric, time: .shortened),
                        systemImage: "clock"
                    )
                }
            }

            Section("已同步账号") {
                if accountSyncStore.snapshot.platformAccounts.isEmpty {
                    WatchEmptyRow(title: "暂无已同步账号", systemImage: "person.crop.circle.badge.exclamationmark")
                } else {
                    ForEach(accountSyncStore.snapshot.platformAccounts) { account in
                        WatchValueRow(
                            title: account.title,
                            subtitle: "\(account.displayName) · \(account.credentialState)",
                            systemImage: WatchComicPlatform(rawValue: account.platformID)?.systemImage
                        )
                    }
                }
            }

            Section("未登录账号") {
                let platforms = missingPlatforms
                if platforms.isEmpty {
                    WatchEmptyRow(title: "全部平台已同步", systemImage: "checkmark.circle")
                } else {
                    ForEach(platforms) { platform in
                        WatchValueRow(
                            title: platform.title,
                            subtitle: platform.subtitle,
                            systemImage: platform.systemImage,
                            tint: .secondary
                        )
                    }
                }
            }
        }
        .navigationTitle("账号管理")
    }

    private var missingPlatforms: [WatchComicPlatform] {
        let synced = Set(accountSyncStore.snapshot.platformAccounts.map(\.platformID))
        return WatchComicPlatform.allCases.filter { !synced.contains($0.id) }
    }

    private var syncStateText: String {
        if accountSyncStore.isReachable {
            return "iPhone 可达"
        }
        switch accountSyncStore.activationState {
        case .activated:
            return "等待 iPhone 推送"
        case .inactive:
            return "连接未激活"
        case .notActivated:
            return "尚未连接"
        @unknown default:
            return "未知"
        }
    }
}

struct WatchDiscoverySettingsPage: View {
    @AppStorage(WatchSettingsKey.defaultExplorePlatform) private var defaultExplorePlatformID = WatchComicPlatform.picacg.rawValue
    @AppStorage(WatchSettingsKey.showsAllExplorePlatforms) private var showsAllExplorePlatforms = false

    var body: some View {
        List {
            Section("发现") {
                Picker("默认平台", selection: defaultExplorePlatform) {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
                Toggle("显示全部平台", isOn: $showsAllExplorePlatforms)
            }
        }
        .navigationTitle("发现")
    }

    private var defaultExplorePlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: defaultExplorePlatformID) ?? .picacg },
            set: { defaultExplorePlatformID = $0.rawValue }
        )
    }
}

struct WatchTagsSettingsPage: View {
    @AppStorage(WatchSettingsKey.defaultTagsPlatform) private var defaultTagsPlatformID = WatchComicPlatform.picacg.rawValue

    var body: some View {
        List {
            Section("标签") {
                Picker("默认平台", selection: defaultTagsPlatform) {
                    ForEach(WatchComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform)
                    }
                }
            }
        }
        .navigationTitle("标签")
    }

    private var defaultTagsPlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: defaultTagsPlatformID) ?? .picacg },
            set: { defaultTagsPlatformID = $0.rawValue }
        )
    }
}

struct WatchListSettingsPage: View {
    @AppStorage(WatchSettingsKey.maxVisibleComics) private var maxVisibleComics = 24

    var body: some View {
        List {
            Section("列表") {
                Stepper(value: $maxVisibleComics, in: 6...60) {
                    WatchValueRow(title: "显示数量", subtitle: "\(maxVisibleComics)", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("列表")
    }
}

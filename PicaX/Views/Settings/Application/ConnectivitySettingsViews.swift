import SwiftUI

struct WatchConnectivitySettingsView: View {
    @AppStorage(WatchConnectivitySettingsKey.syncsReadingHistory) private var syncsReadingHistory = true
    @AppStorage(WatchConnectivitySettingsKey.syncsLocalFavorites) private var syncsLocalFavorites = true
    @AppStorage(WatchConnectivitySettingsKey.syncsReadLater) private var syncsReadLater = true

    var body: some View {
        List {
            Section {
                Toggle("阅读记录同步", isOn: $syncsReadingHistory)
                Toggle("本地收藏同步", isOn: $syncsLocalFavorites)
                Toggle("稍后再读同步", isOn: $syncsReadLater)
            } header: {
                Text("同步内容")
            } footer: {
                Text("平台账号始终由 iPhone 同步给手表；漫画列表和平台内容仍由手表端独立请求。关闭某项后，该内容不会继续推送给手表。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("Watch 互联")
        .picaxHidesTabBar()
    }
}

struct NetworkSettingsView: View {
    var body: some View {
        AppProxySettingsPage(settings: AppProxySettings.shared)
    }
}

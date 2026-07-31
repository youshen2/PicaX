import SwiftUI

struct ExploreSettingsView: View {
    @AppStorage("settings.explore.defaultPlatform") private var defaultPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage("settings.explore.rememberSelectedPlatform") private var rememberSelectedPlatform = true
    @AppStorage("settings.explore.lastSelectedPlatform") private var lastSelectedPlatformID = ComicPlatform.picacg.rawValue

    var body: some View {
        List {
            Section("平台") {
                Picker("默认选中平台", selection: $defaultPlatformID) {
                    ForEach(ComicPlatform.allCases) { platform in
                        Text(platform.title)
                            .tag(platform.rawValue)
                    }
                }

                Toggle("记住选中平台", isOn: $rememberSelectedPlatform)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("发现页")
        .picaxHidesTabBar()
        .onChange(of: rememberSelectedPlatform, perform: updateRememberedPlatform)
    }

    private func updateRememberedPlatform(_ remembersSelection: Bool) {
        if !remembersSelection {
            lastSelectedPlatformID = defaultPlatformID
        }
    }
}

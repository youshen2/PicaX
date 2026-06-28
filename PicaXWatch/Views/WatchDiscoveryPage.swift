import SwiftUI

struct WatchDiscoveryPage: View {
    @AppStorage(WatchSettingsKey.defaultExplorePlatform) private var selectedPlatformID = WatchComicPlatform.picacg.rawValue
    @AppStorage(WatchSettingsKey.showsAllExplorePlatforms) private var showsAllPlatforms = false

    var body: some View {
        List {
            if !showsAllPlatforms {
                Section("平台") {
                    Picker("平台", selection: selectedPlatform) {
                        ForEach(WatchComicPlatform.allCases) { platform in
                            Text(platform.title)
                                .tag(platform)
                        }
                    }
                }
            }

            ForEach(visiblePlatforms) { platform in
                Section(platform.title) {
                    ForEach(platform.discoveryEntries) { kind in
                        NavigationLink {
                            WatchComicListPage(source: .explore(platform: platform, kind: kind))
                        } label: {
                            WatchValueRow(
                                title: kind.title,
                                subtitle: kind.subtitle,
                                systemImage: kind.systemImage,
                                tint: platform.watchColor
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("发现")
    }

    private var selectedPlatform: Binding<WatchComicPlatform> {
        Binding(
            get: { WatchComicPlatform(rawValue: selectedPlatformID) ?? .picacg },
            set: { selectedPlatformID = $0.rawValue }
        )
    }

    private var visiblePlatforms: [WatchComicPlatform] {
        showsAllPlatforms ? WatchComicPlatform.allCases : [selectedPlatform.wrappedValue]
    }
}

import SwiftUI

struct AppDisplaySettingsView: View {
    @AppStorage(AppAppearanceSettingsKey.colorScheme) private var colorScheme = AppAppearanceMode.system.rawValue
    @AppStorage(AppAppearanceSettingsKey.usesSmoothComicDetailTransitions) private var usesSmoothComicDetailTransitions = true

    #if os(iOS)
    private var supportsSmoothComicDetailTransitions: Bool {
        if #available(iOS 18.0, *) {
            true
        } else {
            false
        }
    }
    #endif

    var body: some View {
        List {
            Section {
                Picker("显示模式", selection: $colorScheme) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("选择后会应用到整个应用。")
            }

            #if os(iOS)
            Section {
                Toggle("漫画详情平滑过渡", isOn: $usesSmoothComicDetailTransitions)
                    .disabled(!supportsSmoothComicDetailTransitions)
            } header: {
                Text("页面过渡")
            } footer: {
                Text("开启后，打开漫画详情时会从所选内容平滑缩放。此设置仅影响漫画详情，且需要 iOS 18 或更高版本。")
            }
            #endif
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("显示")
        .picaxHidesTabBar()
    }
}

struct AppBehaviorSettingsView: View {
    @AppStorage(AppBehaviorSettingsKey.checksClipboardForComicLinks) private var checksClipboardForComicLinks = false
    @AppStorage(AppBehaviorSettingsKey.checksClipboardOnlyOnLaunch) private var checksClipboardOnlyOnLaunch = false
    @AppStorage(AppBehaviorSettingsKey.checksUpdatesOnLaunch) private var checksUpdatesOnLaunch = true
    @AppStorage(AppBehaviorSettingsKey.marksImageContentAsSensitive) private var marksImageContentAsSensitive = false

    var body: some View {
        List {
            Section {
                Toggle("检查剪贴板链接", isOn: $checksClipboardForComicLinks)

                if checksClipboardForComicLinks {
                    Toggle("仅启动应用时检查", isOn: $checksClipboardOnlyOnLaunch)
                }

                Toggle("启动时检查更新", isOn: $checksUpdatesOnLaunch)
            } footer: {
                Text("剪贴板检查会提示打开支持链接或 JM 车牌号。启动更新检查只会在发现新版本时提示，检查失败不会打断启动。")
            }

            Section {
                Toggle("图片页面标记为敏感内容", isOn: $marksImageContentAsSensitive)
            } footer: {
                Text("开启后，包含漫画封面或章节图片的页面会标记为敏感内容；进入后台后系统会用占位内容保护这些页面。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("App 行为")
        .picaxHidesTabBar()
    }
}

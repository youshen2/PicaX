import SwiftUI

struct SearchSettingsView: View {
    @EnvironmentObject private var searchHistory: SearchHistoryService

    @StateObject private var ehTagTranslationUpdates = EhTagTranslationUpdateService()

    @AppStorage(SearchSettingsKey.focusesSearchFieldOnOpen) private var focusesSearchFieldOnOpen = false
    @AppStorage(SearchSettingsKey.enablesSearchSuggestions) private var enablesSearchSuggestions = true
    @AppStorage(SearchSettingsKey.translatesChineseSearchTerms) private var translatesChineseSearchTerms = true
    @AppStorage(SearchSettingsKey.suggestionSelectionBehavior) private var suggestionSelectionBehavior = SearchSuggestionSelectionBehavior.fill.rawValue
    @AppStorage(SearchSettingsKey.defaultTargetMode) private var defaultTargetMode = SearchDefaultTargetMode.platform.rawValue
    @AppStorage(SearchSettingsKey.defaultPlatform) private var defaultSearchPlatformID = ComicPlatform.picacg.rawValue
    @AppStorage(SearchSettingsKey.defaultAggregatePlatforms) private var defaultAggregatePlatformIDs = ComicPlatform.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(SearchHistorySettingsKey.isEnabled) private var savesSearchHistory = true
    @AppStorage(SearchHistorySettingsKey.maxRecords) private var maxSearchHistoryRecords = 50

    @State private var showsClearSearchHistoryConfirmation = false
    @State private var showsRestoreEhTagsConfirmation = false

    private var selectedDefaultTargetMode: SearchDefaultTargetMode {
        SearchDefaultTargetMode(rawValue: defaultTargetMode) ?? .platform
    }

    private var defaultAggregatePlatforms: Set<ComicPlatform> {
        let platforms = Set(
            defaultAggregatePlatformIDs
                .split(separator: ",")
                .compactMap { ComicPlatform(rawValue: String($0)) }
        )
        return platforms.isEmpty ? Set(ComicPlatform.allCases) : platforms
    }

    var body: some View {
        List {
            Section {
                Picker("默认搜索源", selection: $defaultTargetMode) {
                    ForEach(SearchDefaultTargetMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }

                if selectedDefaultTargetMode == .platform {
                    Picker("默认平台", selection: $defaultSearchPlatformID) {
                        ForEach(ComicPlatform.allCases) { platform in
                            Text(platform.title)
                                .tag(platform.rawValue)
                        }
                    }
                } else {
                    ForEach(ComicPlatform.allCases) { platform in
                        Button {
                            toggleDefaultAggregatePlatform(platform)
                        } label: {
                            Label(
                                platform.title,
                                systemImage: defaultAggregatePlatforms.contains(platform)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("从底部标签栏进入搜索页时使用这里的默认源；从标签、分类或详情进入时仍会使用来源平台。")
            }

            Section {
                Toggle("进入搜索页自动聚焦", isOn: $focusesSearchFieldOnOpen)
            } footer: {
                Text("关闭后，打开搜索页不会自动弹出键盘；从标签或已下载详情进入并带有关键词时仍会自动搜索。")
            }

            Section {
                Toggle("搜索补全", isOn: $enablesSearchSuggestions)

                if enablesSearchSuggestions {
                    Picker("点击补全后", selection: $suggestionSelectionBehavior) {
                        ForEach(SearchSuggestionSelectionBehavior.allCases) { behavior in
                            Text(behavior.title)
                                .tag(behavior.rawValue)
                        }
                    }
                }
            } footer: {
                Text("开启后，E-Hentai 和 NHentai 搜索会根据本地标签数据提供补全建议；填入模式会在关键词末尾自动加空格。")
            }

            Section {
                Toggle("中文标签词自动转英文", isOn: $translatesChineseSearchTerms)
            } footer: {
                Text("开启后，搜索时会为 E-Hentai 和 NHentai 把能匹配本地标签字段的中文词转为英文词；搜索框和搜索历史仍保留原文，聚合搜索里的其他平台不受影响。")
            }

            Section {
                LabeledContent(
                    "当前数据",
                    value: ehTagTranslationUpdates.info.usesDownloadedDatabase ? "已下载" : "内置"
                )
                LabeledContent(
                    "数据库版本",
                    value: ehTagTranslationUpdates.info.version ?? "内置版本"
                )

                if let updatedAt = ehTagTranslationUpdates.info.updatedAt {
                    LabeledContent(
                        "更新时间",
                        value: updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Button(action: beginTagTranslationUpdate) {
                    if ehTagTranslationUpdates.isUpdating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在下载标签翻译库")
                        }
                    } else {
                        Label("下载更新", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(ehTagTranslationUpdates.isUpdating)

                if ehTagTranslationUpdates.info.usesDownloadedDatabase {
                    Button(role: .destructive, action: confirmTagTranslationRestore) {
                        Label("恢复内置版本", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(ehTagTranslationUpdates.isUpdating)
                }
            } header: {
                Text("E-Hentai 标签翻译库")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let statusMessage = ehTagTranslationUpdates.statusMessage {
                        Text(statusMessage)
                    }
                    Text("从 EhTagTranslation/Database 下载公开标签对应并保存在本机；下载或校验失败时继续使用当前数据，内置版本始终可恢复。")
                }
            }

            Section {
                Toggle("保存搜索历史", isOn: $savesSearchHistory)

                if savesSearchHistory {
                    IntegerSettingsInputRow(
                        title: "最多保留",
                        value: $maxSearchHistoryRecords,
                        unit: "条",
                        lowerBound: 1,
                        upperBound: 200
                    )
                }
            } footer: {
                Text("搜索历史会记录关键词和平台选择，用于在搜索页快速重新搜索。")
            }

            Section {
                Button(role: .destructive, action: confirmSearchHistoryClear) {
                    Label("清空搜索历史", systemImage: "trash")
                }
                .disabled(searchHistory.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("搜索")
        .picaxHidesTabBar()
        .onChange(of: maxSearchHistoryRecords) { _ in
            searchHistory.trimToCurrentLimit()
        }
        .alert("清空搜索历史？", isPresented: $showsClearSearchHistoryConfirmation) {
            Button("清空", role: .destructive, action: searchHistory.clear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本地保存的搜索历史，不会影响收藏、阅读历史或下载。")
        }
        .confirmationDialog("恢复内置标签翻译库？", isPresented: $showsRestoreEhTagsConfirmation) {
            Button("恢复内置版本", role: .destructive, action: ehTagTranslationUpdates.restoreBundled)
            Button("取消", role: .cancel) {}
        } message: {
            Text("已下载的标签对应会从本机删除，之后仍可重新下载。")
        }
    }

    private func beginTagTranslationUpdate() {
        Task {
            await ehTagTranslationUpdates.update()
        }
    }

    private func confirmTagTranslationRestore() {
        showsRestoreEhTagsConfirmation = true
    }

    private func confirmSearchHistoryClear() {
        showsClearSearchHistoryConfirmation = true
    }

    private func toggleDefaultAggregatePlatform(_ platform: ComicPlatform) {
        var platforms = defaultAggregatePlatforms
        if platforms.contains(platform) {
            guard platforms.count > 1 else { return }
            platforms.remove(platform)
        } else {
            platforms.insert(platform)
        }

        defaultAggregatePlatformIDs = ComicPlatform.allCases
            .filter { platforms.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

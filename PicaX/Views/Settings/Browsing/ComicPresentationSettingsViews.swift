import SwiftUI

struct ComicListSettingsView: View {
    @AppStorage(ComicListSettingsKey.layoutMode) private var layoutMode = ComicListLayoutMode.list.rawValue
    @AppStorage(ComicListSettingsKey.showsReadingProgress) private var showsReadingProgress = true
    @AppStorage(ComicListSettingsKey.showsFavoriteState) private var showsFavoriteState = true
    @AppStorage(ComicListSettingsKey.showsTags) private var showsTags = true
    @AppStorage(ComicListSettingsKey.maxVisibleTags) private var maxVisibleTags = 5
    @AppStorage(ComicListSettingsKey.showsPopularity) private var showsPopularity = true
    @AppStorage(ReadFilterSettingsKey.hidesReadComicsInLists) private var hidesReadComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hidesReadLaterComicsInLists) private var hidesReadLaterComicsInLists = false
    @AppStorage(ReadFilterSettingsKey.hiddenProgressThreshold) private var hiddenProgressThreshold = 100
    @AppStorage(ComicTitleMatchingSettingsKey.isEnabled) private var matchesComicTitles = ComicTitleMatchingSettingsKey.defaultIsEnabled
    @AppStorage(ComicTitleMatchingSettingsKey.similarityThreshold) private var comicTitleSimilarityThreshold = ComicTitleMatchingSettingsKey.defaultSimilarityThreshold

    private var hiddenProgressThresholdBinding: Binding<Double> {
        Binding {
            Double(hiddenProgressThreshold)
        } set: { value in
            hiddenProgressThreshold = min(max(Int(value.rounded()), 0), 100)
        }
    }

    private var comicTitleSimilarityThresholdBinding: Binding<Double> {
        Binding {
            Double(comicTitleSimilarityThreshold)
        } set: { value in
            comicTitleSimilarityThreshold = min(max(Int(value.rounded()), 50), 100)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("布局", selection: $layoutMode) {
                    ForEach(ComicListLayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("布局")
            } footer: {
                Text("瀑布流会根据可用宽度自动调整每行漫画数量；辅助功能大字号下会使用更宽的卡片。")
            }

            Section {
                Toggle("显示阅读进度", isOn: $showsReadingProgress)
                Toggle("显示收藏状态", isOn: $showsFavoriteState)
                Toggle("显示标签", isOn: $showsTags)

                if showsTags {
                    IntegerSettingsInputRow(
                        title: "最多显示",
                        value: $maxVisibleTags,
                        unit: "个标签",
                        lowerBound: 1,
                        upperBound: 10
                    )
                }

                Toggle("显示热度", isOn: $showsPopularity)
            } header: {
                Text("显示内容")
            } footer: {
                Text("这些开关只影响漫画列表条目上的附加内容，不会影响阅读记录、收藏数据或详情页。")
            }

            Section {
                Toggle("按名称识别跨平台记录", isOn: $matchesComicTitles)

                if matchesComicTitles {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("名称相似度阈值")
                            Spacer()
                            Text("\(comicTitleSimilarityThreshold)%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: comicTitleSimilarityThresholdBinding, in: 50...100, step: 1)
                    }
                }
            } header: {
                Text("跨平台阅读记录")
            } footer: {
                Text("默认开启。标题达到阈值且语言相同时，会在开启“显示阅读进度”后标记“已在别的平台阅读”，并辅助“隐藏已读内容”和“隐藏稍后再读内容”判断；不会合并搜索结果，也不会跨平台复用章节或页码。无法识别语言时仍按标题匹配。")
            }

            Section {
                Toggle("隐藏已读内容", isOn: $hidesReadComicsInLists)

                if hidesReadComicsInLists {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已读隐藏阈值")
                            Spacer()
                            Text("\(hiddenProgressThreshold)%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: hiddenProgressThresholdBinding, in: 0...100, step: 5)
                    }
                }

                Toggle("隐藏稍后再读内容", isOn: $hidesReadLaterComicsInLists)
            } header: {
                Text("列表隐藏")
            } footer: {
                Text("已读隐藏阈值只对“隐藏已读内容”生效。开启后，普通漫画列表会隐藏符合条件的漫画；收藏夹、历史记录、已下载页面和稍后再读不受影响。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("漫画列表")
        .picaxHidesTabBar()
    }
}

struct ComicDetailSettingsView: View {
    @AppStorage(DetailSettingsKey.usesCoverAccent) private var usesCoverAccent = true
    @AppStorage(DetailSettingsKey.chapterSortOrder) private var chapterSortOrder = ComicDetailChapterSortOrder.ascending.rawValue
    @AppStorage(DetailSettingsKey.showsChaptersAsSection) private var showsChaptersAsSection = false
    @AppStorage(DetailSettingsKey.contentOrder) private var contentOrderRaw = ComicDetailContentSectionKind.defaultRawValue

    @State private var contentOrder = ComicDetailContentSectionKind.defaultOrder

    var body: some View {
        List {
            Section {
                Toggle("阅读按钮使用封面颜色", isOn: $usesCoverAccent)
            } footer: {
                Text("开启后，详情页会根据封面提取颜色，用于阅读按钮和章节按钮。关闭后使用漫画来源的固定颜色。")
            }

            Section {
                Picker("章节排序", selection: $chapterSortOrder) {
                    ForEach(ComicDetailChapterSortOrder.allCases) { order in
                        Text(order.title)
                            .tag(order.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("单独分区显示章节", isOn: $showsChaptersAsSection)
            } footer: {
                Text("开启后，章节会作为详情页里的独立分区显示，封面旁不再显示章节按钮。")
            }

            Section {
                ForEach(contentOrder) { section in
                    Label(section.title, systemImage: section.systemImage)
                }
                .onMove(perform: moveContentSections)

                Button("恢复默认排序", action: restoreDefaultOrder)
            } header: {
                Text("内容顺序")
            } footer: {
                Text("点按编辑后拖动项目调整详情页内容显示顺序。章节需要开启单独分区后才会显示在此顺序中。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("漫画详情")
        .picaxHidesTabBar()
        #if os(iOS)
        .toolbar {
            EditButton()
        }
        #endif
        .onAppear(perform: loadContentOrder)
        .onChange(of: contentOrderRaw, perform: updateContentOrder)
    }

    private func moveContentSections(from source: IndexSet, to destination: Int) {
        contentOrder.move(fromOffsets: source, toOffset: destination)
        saveContentOrder()
    }

    private func restoreDefaultOrder() {
        contentOrder = ComicDetailContentSectionKind.defaultOrder
        saveContentOrder()
    }

    private func loadContentOrder() {
        contentOrder = ComicDetailContentSectionKind.normalizedOrder(from: contentOrderRaw)
        saveContentOrder()
    }

    private func updateContentOrder(from rawValue: String) {
        contentOrder = ComicDetailContentSectionKind.normalizedOrder(from: rawValue)
    }

    private func saveContentOrder() {
        contentOrderRaw = ComicDetailContentSectionKind.rawValue(for: contentOrder)
    }
}

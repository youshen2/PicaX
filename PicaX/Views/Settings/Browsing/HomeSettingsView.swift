import SwiftUI

struct HomeSettingsView: View {
    @AppStorage(ReadingHistoryService.Key.homeLimit) private var homeLimit = 10
    @AppStorage(ReadLaterService.Key.homeLimit) private var readLaterHomeLimit = 10
    @AppStorage(ReadingDurationService.Key.homeLimit) private var readingDurationHomeLimit = 6
    @AppStorage(DownloadSettingsKey.homeLimit) private var downloadHomeLimit = 8
    @AppStorage(HomeSettingsKey.showsHistorySection) private var showsHistorySection = true
    @AppStorage(HomeSettingsKey.showsReadLaterSection) private var showsReadLaterSection = true
    @AppStorage(HomeSettingsKey.showsReadingDurationSection) private var showsReadingDurationSection = true
    @AppStorage(HomeSettingsKey.showsDownloadSection) private var showsDownloadSection = true
    @AppStorage(HomeSettingsKey.showsAccountManagementEntry) private var showsAccountManagementEntry = true
    @AppStorage(HomeSettingsKey.sectionOrder) private var sectionOrderRaw = HomeSectionKind.defaultRawValue

    @State private var sectionOrder = HomeSectionKind.defaultOrder

    var body: some View {
        List {
            Section {
                Toggle("账号管理入口", isOn: $showsAccountManagementEntry)
                Toggle("阅读历史", isOn: $showsHistorySection)
                Toggle("稍后再读", isOn: $showsReadLaterSection)
                Toggle("阅读时长", isOn: $showsReadingDurationSection)
                Toggle("下载", isOn: $showsDownloadSection)
            } header: {
                Text("详细内容")
            } footer: {
                Text("关闭阅读历史、阅读时长或下载后，首页仍保留入口，只折叠横向卡片等详细内容。")
            }

            Section {
                if showsHistorySection {
                    IntegerSettingsInputRow(
                        title: "阅读历史显示",
                        value: $homeLimit,
                        unit: "条",
                        lowerBound: 1,
                        upperBound: 30
                    )
                }

                if showsReadLaterSection {
                    IntegerSettingsInputRow(
                        title: "稍后再读显示",
                        value: $readLaterHomeLimit,
                        unit: "条",
                        lowerBound: 1,
                        upperBound: 30
                    )
                }

                if showsReadingDurationSection {
                    IntegerSettingsInputRow(
                        title: "阅读时长显示",
                        value: $readingDurationHomeLimit,
                        unit: "部",
                        lowerBound: 1,
                        upperBound: 30
                    )
                }

                if showsDownloadSection {
                    IntegerSettingsInputRow(
                        title: "下载显示",
                        value: $downloadHomeLimit,
                        unit: "条",
                        lowerBound: 1,
                        upperBound: 30
                    )
                }
            } footer: {
                Text("只影响首页详细卡片数量，不影响完整列表和本地数据。")
            }

            Section {
                ForEach(sectionOrder) { section in
                    Label(section.title, systemImage: section.systemImage)
                }
                .onMove(perform: moveSections)

                Button("恢复默认排序", action: restoreDefaultOrder)
            } header: {
                Text("排序")
            } footer: {
                Text("点按编辑后拖动项目调整首页显示顺序。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("首页")
        .picaxHidesTabBar()
        #if os(iOS)
        .toolbar {
            EditButton()
        }
        #endif
        .onAppear(perform: loadSectionOrder)
        .onChange(of: sectionOrderRaw, perform: updateSectionOrder)
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
        saveSectionOrder()
    }

    private func restoreDefaultOrder() {
        sectionOrder = HomeSectionKind.defaultOrder
        saveSectionOrder()
    }

    private func loadSectionOrder() {
        sectionOrder = HomeSectionKind.normalizedOrder(from: sectionOrderRaw)
        saveSectionOrder()
    }

    private func updateSectionOrder(from rawValue: String) {
        sectionOrder = HomeSectionKind.normalizedOrder(from: rawValue)
    }

    private func saveSectionOrder() {
        sectionOrderRaw = HomeSectionKind.rawValue(for: sectionOrder)
    }
}

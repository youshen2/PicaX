import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject private var readingHistory: ReadingHistoryService

    @AppStorage(ReadingHistoryService.Key.isEnabled) private var isEnabled = true
    @AppStorage(ReadingHistoryService.Key.maxRecords) private var maxRecords = 200

    @State private var showsClearConfirmation = false
    @State private var showsClearProgressConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("记录历史记录", isOn: $isEnabled)
                IntegerSettingsInputRow(
                    title: "最多保存",
                    value: $maxRecords,
                    unit: "条",
                    lowerBound: 20,
                    upperBound: 500
                )
            } header: {
                Text("记录")
            } footer: {
                Text("历史记录保存在本地，包含平台、漫画编号、标题、封面和查看时间。")
            }

            Section {
                Button(role: .destructive, action: confirmProgressClear) {
                    Label("清空阅读进度", systemImage: "bookmark.slash")
                }
                .disabled(!readingHistory.hasAnyReadingProgress)

                Button(role: .destructive, action: confirmHistoryClear) {
                    Label("清空历史记录", systemImage: "trash")
                }
                .disabled(readingHistory.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("历史记录")
        .picaxHidesTabBar()
        .onChange(of: maxRecords) { _ in
            readingHistory.trimToCurrentLimit()
        }
        .alert("清空历史记录？", isPresented: $showsClearConfirmation) {
            Button("清空历史记录", role: .destructive, action: readingHistory.clear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本地历史记录，不会影响收藏和平台账号。")
        }
        .alert("清空阅读进度？", isPresented: $showsClearProgressConfirmation) {
            Button("清空阅读进度", role: .destructive, action: readingHistory.clearReadingProgress)
            Button("取消", role: .cancel) {}
        } message: {
            Text("历史条目会保留，但会移除章节和页码进度。")
        }
    }

    private func confirmProgressClear() {
        showsClearProgressConfirmation = true
    }

    private func confirmHistoryClear() {
        showsClearConfirmation = true
    }
}

struct ReadingDurationSettingsView: View {
    @EnvironmentObject private var readingDuration: ReadingDurationService

    @AppStorage(ReadingDurationService.Key.isEnabled) private var recordsReadingDuration = true
    @AppStorage(ReadingDurationService.Key.maxRecords) private var maxReadingDurationRecords = 300
    @AppStorage(ReadingDurationService.Key.minimumSessionSeconds) private var minimumReadingDurationSessionSeconds = 1

    @State private var showsClearDurationConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("记录阅读时长", isOn: $recordsReadingDuration)
                IntegerSettingsInputRow(
                    title: "低于不记录",
                    value: $minimumReadingDurationSessionSeconds,
                    unit: "秒",
                    lowerBound: 1,
                    upperBound: 600
                )
                IntegerSettingsInputRow(
                    title: "最多保存",
                    value: $maxReadingDurationRecords,
                    unit: "部",
                    lowerBound: 20,
                    upperBound: 1_000
                )
            } footer: {
                Text("阅读时长会在阅读器打开期间累计，应用进入后台或离开阅读器时保存。单次停留时间低于设置值时不写入统计。")
            }

            Section {
                Button(role: .destructive, action: confirmDurationClear) {
                    Label("清空阅读时长", systemImage: "timer")
                }
                .disabled(readingDuration.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("阅读时长")
        .picaxHidesTabBar()
        .onChange(of: maxReadingDurationRecords) { _ in
            readingDuration.trimToCurrentLimit()
        }
        .alert("清空阅读时长？", isPresented: $showsClearDurationConfirmation) {
            Button("清空阅读时长", role: .destructive, action: readingDuration.clear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除阅读时长统计，不会影响历史记录和阅读进度。")
        }
    }

    private func confirmDurationClear() {
        showsClearDurationConfirmation = true
    }
}

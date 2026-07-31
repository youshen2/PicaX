import SwiftUI

struct DownloadSettingsView: View {
    @EnvironmentObject private var downloadService: DownloadService

    @AppStorage(DownloadSettingsKey.imageRetryCount) private var imageRetryCount = 2
    @AppStorage(DownloadSettingsKey.concurrentDownloadCount) private var concurrentDownloadCount = 1
    @AppStorage(DownloadSettingsKey.concurrentImageDownloadCount) private var concurrentImageDownloadCount = 3
    @AppStorage(DownloadSettingsKey.chapterTitleBlockingKeywords) private var chapterTitleBlockingKeywords = ""
    @AppStorage(DownloadSettingsKey.speedLimitEnabled) private var speedLimitEnabled = false
    @AppStorage(DownloadSettingsKey.speedLimitKBPerSecond) private var speedLimitKBPerSecond = 1024
    @AppStorage(DownloadSettingsKey.readsImagesFromCache) private var readsImagesFromCache = true
    @AppStorage(DownloadSettingsKey.recordsDownloadedReadingHistory) private var recordsDownloadedReadingHistory = true
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false
    @AppStorage(DownloadSettingsKey.archiveFileNameTemplate) private var archiveFileNameTemplate = DownloadSettingsKey.defaultArchiveFileNameTemplate
    @AppStorage(DownloadSettingsKey.showsProgressNotifications) private var showsProgressNotifications = true
    @AppStorage(DownloadSettingsKey.showsProgressLiveActivity) private var showsProgressLiveActivity = true
    @AppStorage(DownloadSettingsKey.progressNotificationUpdateIntervalSeconds) private var progressNotificationUpdateIntervalSeconds = DownloadSettingsKey.defaultProgressNotificationUpdateIntervalSeconds

    var body: some View {
        List {
            Section {
                Toggle("默认保存评论区", isOn: $downloadsCommentsByDefault)
                Toggle("已下载阅读计入历史", isOn: $recordsDownloadedReadingHistory)
            } header: {
                Text("下载内容")
            } footer: {
                Text("评论开关会让支持评论区的漫画在打开下载面板时默认一并保存评论；历史开关会让本地已下载漫画的阅读进度写入阅读历史。")
            }

            Section {
                Toggle("读取图片缓存", isOn: $readsImagesFromCache)
            } header: {
                Text("图片")
            } footer: {
                Text("开启后，下载会优先使用已缓存的图片数据。关闭后，每次下载都绕过图片缓存并从网络重新获取。")
            }

            #if os(iOS)
            Section {
                Toggle("常驻进度通知", isOn: $showsProgressNotifications)

                if showsProgressNotifications {
                    IntegerSettingsInputRow(
                        title: "通知更新间隔",
                        value: $progressNotificationUpdateIntervalSeconds,
                        unit: "秒",
                        lowerBound: 1,
                        upperBound: 60
                    )
                }

                if #available(iOS 16.1, *) {
                    Toggle("灵动岛下载进度", isOn: $showsProgressLiveActivity)
                } else {
                    LabeledContent("灵动岛下载进度", value: "需要 iOS 16.1")
                }
            } header: {
                Text("进度显示")
            } footer: {
                Text("常驻通知会按设定间隔合并更新队列进度；灵动岛开关会启用实时活动，支持的 iPhone 会在灵动岛显示。")
            }
            #endif

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ZIP 文件名格式")
                        .font(.subheadline)

                    TextField(DownloadSettingsKey.defaultArchiveFileNameTemplate, text: $archiveFileNameTemplate)
                        .picaxDisablesTextAutocapitalization()
                        .autocorrectionDisabled()
                }

                Button(action: restoreArchiveFileNameTemplate) {
                    Label("恢复默认格式", systemImage: "arrow.counterclockwise")
                }
                .disabled(archiveFileNameTemplate == DownloadSettingsKey.defaultArchiveFileNameTemplate)
            } header: {
                Text("导出")
            } footer: {
                Text("留空时使用漫画标题。可用：{title}、{id}、{platform}、{date}。")
            }

            Section {
                IntegerSettingsInputRow(
                    title: "同时任务数",
                    value: $concurrentDownloadCount,
                    lowerBound: 1,
                    upperBound: 20
                )
                IntegerSettingsInputRow(
                    title: "图片线程数",
                    value: $concurrentImageDownloadCount,
                    lowerBound: 1,
                    upperBound: 20
                )
                IntegerSettingsInputRow(
                    title: "图片重试",
                    value: $imageRetryCount,
                    unit: "次",
                    lowerBound: 0,
                    upperBound: 8
                )
            } header: {
                Text("任务")
            } footer: {
                Text("同时任务数控制队列里可并行下载的漫画数量；图片线程数控制单个章节内可同时下载的图片数量。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("章节名屏蔽词")
                        .font(.subheadline)

                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("每行一个关键词", text: $chapterTitleBlockingKeywords, axis: .vertical)
                            .lineLimit(3...8)
                            .picaxDisablesTextAutocapitalization()
                            .autocorrectionDisabled()
                    } else {
                        TextEditor(text: $chapterTitleBlockingKeywords)
                            .frame(minHeight: 72, maxHeight: 180)
                            .picaxDisablesTextAutocapitalization()
                            .autocorrectionDisabled()
                    }
                }

                if !chapterTitleBlockingKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: clearChapterBlockingKeywords) {
                        Label("清空章节名屏蔽词", systemImage: "trash")
                    }
                }
            } header: {
                Text("章节过滤")
            } footer: {
                Text("批量下载或选章下载时，章节名包含任一关键词的章节不会加入下载。")
            }

            Section {
                Toggle("启用限速", isOn: $speedLimitEnabled)

                if speedLimitEnabled {
                    IntegerSettingsInputRow(
                        title: "速度上限",
                        value: $speedLimitKBPerSecond,
                        unit: "KB/s",
                        lowerBound: 64,
                        upperBound: 10_240
                    )
                }
            } header: {
                Text("限速")
            } footer: {
                Text("限速会应用到之后的图片下载。")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("下载")
        .picaxHidesTabBar()
        #if os(iOS)
        .onChange(of: showsProgressNotifications) { _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: showsProgressLiveActivity) { _ in
            downloadService.refreshProgressPresentation()
        }
        .onChange(of: progressNotificationUpdateIntervalSeconds) { _ in
            downloadService.refreshProgressPresentation()
        }
        #endif
    }

    private func restoreArchiveFileNameTemplate() {
        archiveFileNameTemplate = DownloadSettingsKey.defaultArchiveFileNameTemplate
    }

    private func clearChapterBlockingKeywords() {
        chapterTitleBlockingKeywords = ""
    }
}

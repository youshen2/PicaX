import SwiftUI

struct StorageManagementView: View {
    @EnvironmentObject private var downloadService: DownloadService
    @EnvironmentObject private var readingHistory: ReadingHistoryService

    @AppStorage(ImageCacheSettingsKey.maxDiskSizeMB) private var maxDiskSizeMB = ImageCacheService.defaultMaxDiskSizeMB
    @AppStorage(DetailCacheSettingsKey.isEnabled) private var detailCacheEnabled = true
    @AppStorage(DetailCacheSettingsKey.maxDiskSizeMB) private var maxDetailCacheDiskSizeMB = ComicDetailCacheService.defaultMaxDiskSizeMB

    @State private var showsClearCacheConfirmation = false
    @State private var showsClearDetailCacheConfirmation = false
    @State private var showsClearDownloadsConfirmation = false
    @State private var usage = ImageCacheUsage(memoryBytes: 0, diskBytes: 0)
    @State private var detailCacheUsage = ComicDetailCacheUsage(diskBytes: 0)
    @State private var downloadUsage = DownloadStorageUsage(filesBytes: 0, recordsBytes: 0, tasksBytes: 0)
    @State private var historyBytes = 0
    @State private var durationBytes = 0

    private var localDataBytes: Int64 {
        Int64(historyBytes + durationBytes + downloadUsage.metadataBytes)
    }

    private var totalDiskUsage: Int64 {
        Int64(usage.diskBytes + detailCacheUsage.diskBytes)
            + downloadUsage.filesBytes
            + localDataBytes
    }

    var body: some View {
        List {
            Section("总览") {
                SettingsValueRow(
                    title: "总占用",
                    value: ImageCacheService.formattedSize(totalDiskUsage)
                )
                SettingsValueRow(
                    title: "图片缓存",
                    value: ImageCacheService.formattedSize(usage.diskBytes)
                )
                SettingsValueRow(
                    title: "详情缓存",
                    value: ImageCacheService.formattedSize(detailCacheUsage.diskBytes)
                )
                SettingsValueRow(
                    title: "下载文件",
                    value: ImageCacheService.formattedSize(downloadUsage.filesBytes)
                )
                SettingsValueRow(
                    title: "本地数据",
                    value: ImageCacheService.formattedSize(localDataBytes)
                )
            }

            Section {
                SettingsValueRow(
                    title: "当前占用",
                    value: ImageCacheService.formattedSize(usage.diskBytes)
                )
                IntegerSettingsInputRow(
                    title: "最大缓存",
                    value: $maxDiskSizeMB,
                    unit: "MB",
                    lowerBound: 50
                )
            } header: {
                Text("图片缓存")
            } footer: {
                Text("封面、分类图和阅读图片会优先使用已缓存的数据。调整容量后会应用到之后的图片请求。")
            }

            Section {
                Toggle("启用详情缓存", isOn: $detailCacheEnabled)
                SettingsValueRow(
                    title: "当前占用",
                    value: ImageCacheService.formattedSize(detailCacheUsage.diskBytes)
                )
                IntegerSettingsInputRow(
                    title: "最大缓存",
                    value: $maxDetailCacheDiskSizeMB,
                    unit: "MB",
                    lowerBound: 5
                )
            } header: {
                Text("详情缓存")
            } footer: {
                Text("开启后，第二次打开同一漫画会先显示已缓存的基础详情，再从网络补齐章节和相关推荐。章节、相关推荐和 PicACG 上传者信息不会保存到详情缓存。")
            }

            Section("下载") {
                SettingsValueRow(title: "已下载漫画", value: "\(downloadService.records.count) 部")
                SettingsValueRow(title: "下载队列", value: "\(downloadService.tasks.count) 个任务")
                SettingsValueRow(
                    title: "文件占用",
                    value: ImageCacheService.formattedSize(downloadUsage.filesBytes)
                )
                SettingsValueRow(
                    title: "记录占用",
                    value: ImageCacheService.formattedSize(downloadUsage.recordsBytes)
                )
                SettingsValueRow(
                    title: "队列占用",
                    value: ImageCacheService.formattedSize(downloadUsage.tasksBytes)
                )
            }

            Section("阅读历史") {
                SettingsValueRow(title: "记录数量", value: "\(readingHistory.records.count) 条")
                SettingsValueRow(
                    title: "记录占用",
                    value: ImageCacheService.formattedSize(historyBytes)
                )
                SettingsValueRow(
                    title: "阅读时长",
                    value: ImageCacheService.formattedSize(durationBytes)
                )
            }

            Section("清理") {
                Button(role: .destructive, action: confirmImageCacheClear) {
                    Label("清空图片缓存", systemImage: "trash")
                }

                Button(role: .destructive, action: confirmDetailCacheClear) {
                    Label("清空详情缓存", systemImage: "trash")
                }

                Button(role: .destructive, action: confirmDownloadsClear) {
                    Label("删除已下载文件", systemImage: "trash")
                }
                .disabled(downloadService.records.isEmpty)
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("存储管理")
        .picaxHidesTabBar()
        .onAppear(perform: configureStorage)
        .onChange(of: maxDiskSizeMB, perform: updateImageCacheLimit)
        .onChange(of: detailCacheEnabled) { _ in
            refreshStorageUsageInTask()
        }
        .onChange(of: maxDetailCacheDiskSizeMB, perform: updateDetailCacheLimit)
        .alert("清空图片缓存？", isPresented: $showsClearCacheConfirmation) {
            Button("清空缓存", role: .destructive, action: clearImageCache)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地缓存的封面、分类图和阅读图片，不会影响下载、收藏或历史记录。")
        }
        .alert("清空详情缓存？", isPresented: $showsClearDetailCacheConfirmation) {
            Button("清空缓存", role: .destructive, action: clearDetailCache)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地缓存的漫画基础详情，不会影响下载、收藏或历史记录。")
        }
        .alert("删除所有已下载文件？", isPresented: $showsClearDownloadsConfirmation) {
            Button("删除已下载文件", role: .destructive, action: clearDownloads)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本地下载的图片和下载完成记录，不会影响历史记录、收藏和平台账号。")
        }
    }

    private func confirmImageCacheClear() {
        showsClearCacheConfirmation = true
    }

    private func confirmDetailCacheClear() {
        showsClearDetailCacheConfirmation = true
    }

    private func confirmDownloadsClear() {
        showsClearDownloadsConfirmation = true
    }

    private func configureStorage() {
        if maxDiskSizeMB <= 0 {
            maxDiskSizeMB = ImageCacheService.defaultMaxDiskSizeMB
        }
        if maxDetailCacheDiskSizeMB <= 0 {
            maxDetailCacheDiskSizeMB = ComicDetailCacheService.defaultMaxDiskSizeMB
        }

        let imageTrimTask = ImageCacheService.configure()
        let detailTrimTask = ComicDetailCacheService.configure()
        Task {
            await imageTrimTask.value
            await detailTrimTask.value
            await refreshStorageUsage()
        }
    }

    private func updateImageCacheLimit(_ newValue: Int) {
        guard newValue > 0 else { return }
        let trimTask = ImageCacheService.configure()
        Task {
            await trimTask.value
            await refreshStorageUsage()
        }
    }

    private func updateDetailCacheLimit(_ newValue: Int) {
        guard newValue > 0 else { return }
        let trimTask = ComicDetailCacheService.configure()
        Task {
            await trimTask.value
            await refreshStorageUsage()
        }
    }

    private func refreshStorageUsageInTask() {
        Task {
            await refreshStorageUsage()
        }
    }

    private func clearImageCache() {
        Task {
            await ImageCacheService.clear()
            await refreshStorageUsage()
        }
    }

    private func clearDetailCache() {
        Task {
            await ComicDetailCacheService.clear()
            await refreshStorageUsage()
        }
    }

    private func clearDownloads() {
        downloadService.clearFinishedDownloads()
        refreshStorageUsageInTask()
    }

    @MainActor
    private func refreshStorageUsage() async {
        async let nextUsage = ImageCacheService.usage()
        async let nextDetailCacheUsage = ComicDetailCacheService.usage()
        async let nextDownloadUsage = downloadService.storageUsage()
        async let nextLocalDatabaseBytes = Self.localDatabaseBytes()

        let values = await (
            nextUsage,
            nextDetailCacheUsage,
            nextDownloadUsage,
            nextLocalDatabaseBytes
        )
        usage = values.0
        detailCacheUsage = values.1
        downloadUsage = values.2
        historyBytes = values.3.history
        durationBytes = values.3.duration
    }

    private nonisolated static func localDatabaseBytes() async -> (history: Int, duration: Int) {
        await Task.detached(priority: .utility) {
            (
                history: PicaXSQLiteStore.bytes(for: .readingHistory),
                duration: PicaXSQLiteStore.bytes(for: .readingDuration)
            )
        }.value
    }
}

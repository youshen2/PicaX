import SwiftUI

struct WatchHomePage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @EnvironmentObject private var downloadService: WatchDownloadService

    var body: some View {
        List {
            Section("同步") {
                WatchValueRow(
                    title: accountSyncStore.snapshot.hasSyncedAccounts ? "已同步" : "等待同步",
                    subtitle: syncSubtitle,
                    systemImage: accountSyncStore.snapshot.hasSyncedAccounts ? "checkmark.icloud" : "icloud.slash",
                    tint: accountSyncStore.snapshot.hasSyncedAccounts ? .green : .secondary
                )
            }

            Section("阅读") {
                NavigationLink {
                    WatchSearchPage()
                } label: {
                    WatchValueRow(
                        title: "搜索",
                        subtitle: "搜索漫画、作者和标签",
                        systemImage: "magnifyingglass"
                    )
                }

                NavigationLink {
                    WatchReadingHistoryPage()
                } label: {
                    WatchValueRow(
                        title: "阅读记录",
                        subtitle: "继续手表上的阅读进度",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                NavigationLink {
                    WatchComicListPage(source: .readLater)
                } label: {
                    WatchValueRow(
                        title: "稍后再读",
                        subtitle: readLaterSubtitle,
                        systemImage: "bookmark"
                    )
                }
            }

            Section("下载") {
                NavigationLink {
                    WatchDownloadsPage()
                } label: {
                    WatchValueRow(
                        title: "下载管理",
                        subtitle: downloadSubtitle,
                        systemImage: "arrow.down.circle"
                    )
                }
            }
        }
        .navigationTitle("主页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }

    private var syncSubtitle: String {
        guard accountSyncStore.snapshot.updatedAt > .distantPast else {
            return "手机端只负责同步平台账号信息"
        }
        return "上次同步 \(accountSyncStore.snapshot.updatedAt.formatted(date: .numeric, time: .shortened))"
    }

    private var downloadSubtitle: String {
        let taskCount = downloadService.tasks.count
        let recordCount = downloadService.records.count
        if taskCount > 0 {
            return "\(taskCount) 个任务 · \(recordCount) 部已下载"
        }
        return recordCount > 0 ? "\(recordCount) 部已下载" : "暂无下载"
    }

    private var readLaterSubtitle: String {
        let count = accountSyncStore.snapshot.readLater.count
        return count > 0 ? "\(count) 本待读" : "暂无待读漫画"
    }
}

import SwiftUI

struct FollowUpdatesPage: View {
    @EnvironmentObject private var followUpdates: FollowUpdatesService
    let service: ComicContentService
    @State private var showsDisableConfirmation = false

    var body: some View {
        List {
            configurationSection
            if followUpdates.isEnabled {
                updatedSection
                allComicsSection
            }
        }
        .navigationTitle("追更")
        .picaxNavigationBarTitleDisplayModeInline()
        .refreshable {
            followUpdates.checkNow()
            while followUpdates.isChecking, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        .confirmationDialog("禁用追更？", isPresented: $showsDisableConfirmation, titleVisibility: .visible) {
            Button("禁用", role: .destructive) {
                followUpdates.setEnabled(false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已保存的检查状态会保留，再次启用时可继续使用。")
        }
    }

    @ViewBuilder
    private var configurationSection: some View {
        Section {
            Picker("自动检查频率", selection: checkFrequencyBinding) {
                ForEach(FollowUpdateCheckFrequency.allCases) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }

            if followUpdates.isEnabled {
                LabeledContent("收藏夹", value: "本地收藏")

                if followUpdates.isChecking {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: followUpdates.progress.fractionCompleted)
                        Text(progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    followUpdates.checkNow()
                } label: {
                    Label("立即检查", systemImage: "arrow.clockwise")
                }
                .disabled(followUpdates.isChecking)

                Button("禁用追更", role: .destructive) {
                    showsDisableConfirmation = true
                }
            } else {
                Label("追更尚未启用", systemImage: "info.circle")
                Text("启用后会为本地收藏建立更新基线，并按所选频率自动检查。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    followUpdates.setEnabled(true)
                } label: {
                    Label("启用并建立基线", systemImage: "sparkles")
                }
            }
        } header: {
            Text("设置")
        } footer: {
            if followUpdates.isEnabled {
                Text("手动检查不受自动检查间隔限制；网络错误会自动重试三次。")
            }
        }
    }

    @ViewBuilder
    private var updatedSection: some View {
        Section {
            if followUpdates.updatedRecords.isEmpty {
                Label("未找到更新", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(followUpdates.updatedRecords) { record in
                    comicLink(record)
                }
                Button("全部标记为已读") {
                    followUpdates.markAllAsRead()
                }
            }
        } header: {
            Text("更新（\(followUpdates.updatedCount)）")
        } footer: {
            if !followUpdates.updatedRecords.isEmpty {
                Text("进入漫画阅读器后会自动标记为已读。")
            }
        }
    }

    private var allComicsSection: some View {
        Section("全部漫画（\(followUpdates.records.count)）") {
            if followUpdates.records.isEmpty {
                ContentUnavailableView("暂无本地收藏", systemImage: "star", description: Text("先将漫画加入本地收藏，再回来建立追更基线。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(followUpdates.records) { record in
                    comicLink(record)
                }
            }
        }
    }

    private func comicLink(_ record: FollowUpdateRecord) -> some View {
        NavigationLink {
            ComicDetailPage(item: record.item, service: service)
                .picaxHidesTabBar()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.item.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    if record.hasNewUpdate {
                        Text("有更新")
                            .font(.caption.bold())
                            .foregroundStyle(record.item.accentColor)
                    }
                }
                Text(record.item.subtitle.isEmpty ? record.item.platformTitle : record.item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let errorMessage = record.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var progressText: String {
        let progress = followUpdates.progress
        var text = "正在检查 \(progress.completed)/\(progress.total)"
        if progress.updated > 0 { text += "，发现 \(progress.updated) 项更新" }
        if progress.errors > 0 { text += "，\(progress.errors) 项失败" }
        return text
    }

    private var checkFrequencyBinding: Binding<FollowUpdateCheckFrequency> {
        Binding {
            followUpdates.checkFrequency
        } set: { frequency in
            followUpdates.setCheckFrequency(frequency)
        }
    }
}

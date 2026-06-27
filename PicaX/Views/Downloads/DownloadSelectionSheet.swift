import SwiftUI

struct DownloadSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadService: DownloadService
    @AppStorage(DownloadSettingsKey.downloadsCommentsByDefault) private var downloadsCommentsByDefault = false

    let detail: ComicDetailInfo
    @State private var selectedIndexes: Set<Int> = []
    @State private var message: String?
    @State private var downloadsComments = false
    @State private var didApplyDefaultOptions = false

    var body: some View {
        NavigationStack {
            List {
                if detail.chapters.isEmpty {
                    ContentUnavailableView("暂无可下载章节", systemImage: "tray")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        Toggle("一并下载评论区", isOn: $downloadsComments)
                            .disabled(!detail.item.supportsComments || activeTask != nil)
                    } footer: {
                        Text(detail.item.supportsComments ? "详情评论和章节评论会保存到本地。" : "当前来源不支持评论区下载。")
                    }

                    Section {
                        ForEach(Array(detail.chapters.enumerated()), id: \.element.id) { index, chapter in
                            DownloadChapterSelectionRow(
                                chapter: chapter,
                                index: index,
                                isSelected: selectedIndexes.contains(index),
                                isDownloaded: downloadedIndexes.contains(index),
                                isDisabled: isSelectionDisabled
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggle(index)
                            }
                        }
                    } header: {
                        Text(detail.item.title)
                    } footer: {
                        if let task = activeTask {
                            Text(task.statusText)
                        }
                    }
                }
            }
            .picaxInsetGroupedListStyle()
            .background(AppColor.groupedBackground)
            .navigationTitle("下载漫画")
            .picaxNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .picaxTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .safeAreaInset(edge: .bottom) {
                DownloadSelectionFooter(
                    message: message,
                    selectedCount: selectedIndexes.count,
                    canDownloadAll: activeTask == nil && !availableIndexes.isEmpty,
                    canDownloadSelected: activeTask == nil && !selectedIndexes.isEmpty,
                    isActive: activeTask != nil,
                    downloadAll: {
                        enqueue(Array(availableIndexes))
                    },
                    downloadSelected: {
                        enqueue(Array(selectedIndexes))
                    }
                )
            }
            .onAppear {
                if !didApplyDefaultOptions {
                    downloadsComments = downloadsCommentsByDefault && detail.item.supportsComments
                    didApplyDefaultOptions = true
                }

                if selectedIndexes.isEmpty, availableIndexes.count == 1, let onlyIndex = availableIndexes.first {
                    selectedIndexes = [onlyIndex]
                }
            }
        }
    }

    private var downloadedIndexes: Set<Int> {
        downloadService.downloadedChapterIndexes(for: detail.item)
    }

    private var activeTask: ComicDownloadTask? {
        downloadService.task(for: detail.item)
    }

    private var availableIndexes: Set<Int> {
        Set(detail.chapters.indices.filter { !downloadedIndexes.contains($0) })
    }

    private var isSelectionDisabled: Bool {
        activeTask != nil
    }

    private func toggle(_ index: Int) {
        guard activeTask == nil, availableIndexes.contains(index) else { return }
        if selectedIndexes.contains(index) {
            selectedIndexes.remove(index)
        } else {
            selectedIndexes.insert(index)
        }
    }

    private func enqueue(_ indexes: [Int]) {
        let result = downloadService.enqueue(
            detail: detail,
            chapterIndexes: indexes,
            downloadsComments: downloadsComments
        )
        switch result {
        case .queued:
            dismiss()
        default:
            message = result.message
        }
    }
}

private struct DownloadChapterSelectionRow: View {
    let chapter: ComicChapter
    let index: Int
    let isSelected: Bool
    let isDownloaded: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selectionImage)
                .font(.title3)
                .foregroundStyle(selectionColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .foregroundStyle(isUnavailable ? .secondary : .primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var isUnavailable: Bool {
        isDownloaded || isDisabled
    }

    private var selectionImage: String {
        if isDownloaded { return "checkmark.circle.fill" }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var selectionColor: Color {
        if isDownloaded { return .secondary }
        return isSelected ? .accentColor : .secondary
    }

    private var subtitle: String {
        if isDownloaded { return "已下载" }
        if isDisabled { return "已有下载任务" }
        return chapter.subtitle ?? "第 \(index + 1) 章"
    }
}

private struct DownloadSelectionFooter: View {
    let message: String?
    let selectedCount: Int
    let canDownloadAll: Bool
    let canDownloadSelected: Bool
    let isActive: Bool
    let downloadAll: () -> Void
    let downloadSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 10) {
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                buttons
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var buttons: some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    glassButton(
                        title: isActive ? "下载中" : "下载全部",
                        isProminent: false,
                        isEnabled: canDownloadAll,
                        action: downloadAll
                    )

                    glassButton(
                        title: selectedCount > 0 ? "下载选中 \(selectedCount)" : "下载选中",
                        isProminent: true,
                        isEnabled: canDownloadSelected,
                        action: downloadSelected
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                fallbackButton(
                    title: isActive ? "下载中" : "下载全部",
                    isProminent: false,
                    isEnabled: canDownloadAll,
                    action: downloadAll
                )

                fallbackButton(
                    title: selectedCount > 0 ? "下载选中 \(selectedCount)" : "下载选中",
                    isProminent: true,
                    isEnabled: canDownloadSelected,
                    action: downloadSelected
                )
            }
        }
    }

    @available(iOS 26, macOS 26, visionOS 26, *)
    @ViewBuilder
    private func glassButton(title: String, isProminent: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        if isProminent {
            Button(action: action) {
                buttonLabel(title)
            }
            .buttonStyle(.glassProminent)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                buttonLabel(title)
            }
            .buttonStyle(.glass)
            .disabled(!isEnabled)
        }
    }

    @ViewBuilder
    private func fallbackButton(title: String, isProminent: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        if isProminent {
            Button(action: action) {
                buttonLabel(title)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                buttonLabel(title)
            }
            .buttonStyle(.bordered)
            .disabled(!isEnabled)
        }
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
    }
}

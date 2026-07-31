import SwiftUI

struct ReleaseNotesView: View {
    let releaseNotes: AppReleaseNotes?
    let currentVersion: String

    init(
        releaseNotes: AppReleaseNotes?,
        currentVersion: String = Bundle.main.appVersion
    ) {
        self.releaseNotes = releaseNotes
        self.currentVersion = currentVersion
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text("PicaX \(displayVersion)")
                        .font(.title2.bold())

                    Text("当前版本更新日志")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if let releaseNotes, !releaseNotes.entries.isEmpty {
                    ForEach(releaseNotes.entries.indices, id: \.self) { index in
                        Text(releaseNotes.entries[index])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ContentUnavailableView(
                        "暂无更新内容",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(emptyStateDescription)
                    )
                }
            } header: {
                Text("更新内容")
            } footer: {
                if let previousVersion = releaseNotes?.displayPreviousVersion {
                    Text("版本范围：PicaX \(previousVersion) 至 PicaX \(displayVersion)")
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("更新日志")
        .picaxNavigationBarTitleDisplayModeInline()
        .picaxHidesTabBar()
    }

    private var displayVersion: String {
        releaseNotes?.displayVersion ?? AppVersion.displayName(for: currentVersion)
    }

    private var emptyStateDescription: String {
        releaseNotes == nil
            ? "此构建未包含有效的更新日志。"
            : "本次没有需要公开展示的更新内容。"
    }
}

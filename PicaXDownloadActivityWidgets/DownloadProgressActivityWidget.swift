import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PicaXDownloadActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        PicaXDownloadActivityWidget()
    }
}

struct PicaXDownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PicaXDownloadActivityAttributes.self) { context in
            DownloadActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("下载", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .padding(.leading, 8)
                        .padding(.top, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progressText)
                        .font(.headline.monospacedDigit())
                        .padding(.trailing, 8)
                        .padding(.top, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        HStack {
                            Text(context.state.detail)
                                .lineLimit(1)
                                .layoutPriority(1)
                            if !context.state.unitText.isEmpty {
                                Spacer()
                                Text(context.state.unitText)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            } else if !context.state.queueText.isEmpty {
                                Spacer()
                                Text(context.state.queueText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: context.state.clippedProgress)
                            .tint(.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
            } compactTrailing: {
                Text(context.state.progressText)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
            }
        }
    }
}

private struct DownloadActivityLockScreenView: View {
    let state: PicaXDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("漫画下载中", systemImage: "arrow.down.circle")
                    .font(.headline)
                Spacer()
                Text(state.progressText)
                    .font(.headline.monospacedDigit())
            }

            Text(state.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack {
                Text(state.detail)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !state.unitText.isEmpty {
                    Spacer()
                    Text(state.unitText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else if !state.queueText.isEmpty {
                    Spacer()
                    Text(state.queueText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: state.clippedProgress)
                .tint(.accentColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

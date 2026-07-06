import SwiftUI

struct HomeReadingDurationHeader: View {
    let service: ComicContentService

    var body: some View {
        HStack {
            Text("阅读时长")
            Spacer()
            NavigationLink {
                ReadingDurationListPage(service: service)
                    .picaxHidesTabBar()
            } label: {
                Image(systemName: "chevron.right.circle")
                    .imageScale(.medium)
            }
            .accessibilityLabel("查看全部阅读时长")
        }
    }
}

struct HomeReadingDurationCard: View {
    let records: [ReadingDurationRecord]
    let todayKey: String
    let todayDurationText: String
    let totalDurationText: String
    let openRecord: (ReadingDurationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ReadingDurationSummaryItem(title: "今日", value: todayDurationText)
                Divider()
                ReadingDurationSummaryItem(title: "累计", value: totalDurationText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if records.isEmpty {
                Text("开始阅读后会在这里显示统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Button {
                            openRecord(record)
                        } label: {
                            ReadingDurationCardItem(record: record, todayKey: todayKey)
                        }
                        .buttonStyle(.plain)

                        if index < records.count - 1 {
                            Divider()
                                .padding(.leading, 70)
                        }
                    }
                }
                .background(AppColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 6)
    }
}

struct HomeReadingDurationEntryLink: View {
    let todayDurationText: String
    let totalDurationText: String
    let service: ComicContentService

    var body: some View {
        NavigationLink {
            ReadingDurationListPage(service: service)
                .picaxHidesTabBar()
        } label: {
            ToolRow(
                title: "阅读时长",
                subtitle: "今日 \(todayDurationText) · 累计 \(totalDurationText)",
                systemImage: "timer"
            )
        }
    }
}

private struct ReadingDurationSummaryItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadingDurationCardItem: View {
    let record: ReadingDurationRecord
    let todayKey: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 56, height: 76)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(record.durationText(for: todayKey), systemImage: "timer")
                    Text("累计 \(record.totalDurationText)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(record.item.accentColor)
                .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

private struct ReadingDurationListPage: View {
    @EnvironmentObject private var readingDuration: ReadingDurationService
    let service: ComicContentService

    var body: some View {
        List {
            Section("总览") {
                LabeledContent("今日", value: readingDuration.todayDurationText)
                LabeledContent("累计", value: readingDuration.totalDurationText)
                LabeledContent("漫画", value: "\(readingDuration.records.count) 部")
            }

            Section("总趋势") {
                ReadingDurationTrendChart(points: totalTrendPoints, accentColor: .accentColor)
                    .frame(height: 180)
                    .padding(.vertical, 8)
            }

            if readingDuration.records.isEmpty {
                ContentUnavailableView("暂无阅读时长", systemImage: "timer", description: Text("开始阅读后会记录到这里"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    LazyLocalForEach(items: readingDuration.records, initialCount: 48, pageSize: 48) { record in
                        NavigationLink {
                            ReadingDurationDetailPage(record: record, service: service)
                                .picaxHidesTabBar()
                        } label: {
                            ReadingDurationRow(record: record, todayKey: readingDuration.todayKey)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                readingDuration.remove(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("左滑可删除单部漫画的阅读时长。")
                }
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .picaxSensitiveImageContent(!readingDuration.records.isEmpty)
        .navigationTitle("阅读时长")
    }

    private var totalTrendPoints: [ReadingDurationTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dailySeconds: [String: TimeInterval] = [:]

        for record in readingDuration.records {
            if record.dailySeconds.isEmpty {
                let key = ReadingDurationService.dayKey(for: record.lastReadAt, calendar: calendar)
                dailySeconds[key, default: 0] += max(record.totalSeconds, 0)
            } else {
                for (key, seconds) in record.dailySeconds {
                    dailySeconds[key, default: 0] += max(seconds, 0)
                }
            }
        }

        return (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = ReadingDurationService.dayKey(for: date, calendar: calendar)
            return ReadingDurationTrendPoint(
                id: key,
                date: date,
                seconds: max(dailySeconds[key] ?? 0, 0)
            )
        }
    }
}

struct ReadingDurationDetailPage: View {
    let record: ReadingDurationRecord
    let service: ComicContentService

    var body: some View {
        List {
            Section("漫画") {
                NavigationLink {
                    ComicDetailPage(item: record.item, service: service)
                        .picaxHidesTabBar()
                } label: {
                    ReadingDurationComicSummaryRow(record: record)
                }
            }

            Section("统计") {
                LabeledContent("累计", value: record.totalDurationText)
                LabeledContent("最近阅读", value: record.lastReadAtText)
            }

            Section("趋势") {
                ReadingDurationTrendChart(points: trendPoints, accentColor: record.item.accentColor)
                    .frame(height: 180)
                    .padding(.vertical, 8)
            }
        }
        .picaxInsetGroupedListStyle()
        .background(AppColor.groupedBackground)
        .picaxSensitiveImageContent(record.item.coverURL != nil)
        .navigationTitle("阅读时长")
        .picaxNavigationBarTitleDisplayModeInline()
    }

    private var trendPoints: [ReadingDurationTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var points: [ReadingDurationTrendPoint] = (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = ReadingDurationService.dayKey(for: date, calendar: calendar)
            return ReadingDurationTrendPoint(
                id: key,
                date: date,
                seconds: max(record.dailySeconds[key] ?? 0, 0)
            )
        }

        if points.allSatisfy({ $0.seconds <= 0 }), record.totalSeconds > 0 {
            let fallbackKey = ReadingDurationService.dayKey(for: record.lastReadAt, calendar: calendar)
            let fallbackIndex = points.firstIndex { $0.id == fallbackKey } ?? points.indices.last
            if let fallbackIndex {
                points[fallbackIndex] = ReadingDurationTrendPoint(
                    id: points[fallbackIndex].id,
                    date: points[fallbackIndex].date,
                    seconds: record.totalSeconds
                )
            }
        }

        return points
    }
}

private struct ReadingDurationComicSummaryRow: View {
    let record: ReadingDurationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 58, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(record.item.platformTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.item.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReadingDurationTrendPoint: Identifiable {
    let id: String
    let date: Date
    let seconds: TimeInterval

    var durationText: String {
        ReadingDurationService.formattedDuration(seconds)
    }
}

private struct ReadingDurationTrendChart: View {
    let points: [ReadingDurationTrendPoint]
    let accentColor: Color

    private var maxSeconds: TimeInterval {
        max(points.map(\.seconds).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points) { point in
                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(point.seconds > 0 ? accentColor : Color.secondary.opacity(0.18))
                                    .frame(height: barHeight(for: point, availableHeight: proxy.size.height))
                            }
                        }
                        .frame(height: 118)

                        Text(label(for: point.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label(for: point.date)) \(point.durationText)")
                }
            }

            Text("近 14 天")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func barHeight(for point: ReadingDurationTrendPoint, availableHeight: CGFloat) -> CGFloat {
        guard point.seconds > 0 else { return 3 }
        return max(6, availableHeight * CGFloat(point.seconds / maxSeconds))
    }

    private func label(for date: Date) -> String {
        Self.labelFormatter.string(from: date)
    }

    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private struct ReadingDurationRow: View {
    let record: ReadingDurationRecord
    let todayKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(url: record.item.coverURL, accentColor: record.item.accentColor, width: 58, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("今日 \(record.durationText(for: todayKey)) · 累计 \(record.totalDurationText)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.item.accentColor)
                    .lineLimit(1)

                Text("最近阅读 \(record.lastReadAtText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

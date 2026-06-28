import Combine
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ReaderSettingsKey {
    static let progressStyle = "settings.reader.progressStyle"
    static let progressPosition = "settings.reader.progressPosition"
    static let showsPageLabel = "settings.reader.showsPageLabel"
    static let progressFollowsUIVisibility = "settings.reader.progressFollowsUIVisibility"
    static let progressTapSelectionEnabled = "settings.reader.progressTapSelectionEnabled"
    static let progressBackgroundOpacity = "settings.reader.progressBackgroundOpacity"
    static let progressBottomInset = "settings.reader.progressBottomInset"
    static let readingMode = "settings.reader.readingMode"
    static let imageSpacing = "settings.reader.imageSpacing"
    static let firstImageTopPadding = "settings.reader.firstImageTopPadding"
    static let lastImageBottomPadding = "settings.reader.lastImageBottomPadding"
    static let preloadImageCount = "settings.reader.preloadImageCount"
    static let pagedPreloadDelay = "settings.reader.pagedPreloadDelay"
    static let imageRetryCount = "settings.reader.imageRetryCount"
    static let imageRetryInterval = "settings.reader.imageRetryInterval"
    static let reducesImageBrightnessInDarkMode = "settings.reader.reducesImageBrightnessInDarkMode"
    static let hidesStatusBar = "settings.reader.hidesStatusBar"
    static let uiToggleMode = "settings.reader.uiToggleMode"
    static let tapPagingEnabled = "settings.reader.tapPagingEnabled"
    static let tapPagingInverted = "settings.reader.tapPagingInverted"
    static let tapPagingEdgePercent = "settings.reader.tapPagingEdgePercent"
    static let tapPagingDistancePercent = "settings.reader.tapPagingDistancePercent"
    static let pinchZoomEnabled = "settings.reader.pinchZoomEnabled"
    static let doubleTapZoomEnabled = "settings.reader.doubleTapZoomEnabled"
    static let doubleTapZoomScale = "settings.reader.doubleTapZoomScale"
    static let longPressZoomEnabled = "settings.reader.longPressZoomEnabled"
    static let longPressZoomScale = "settings.reader.longPressZoomScale"
    static let autoPagingInterval = "settings.reader.autoPagingInterval"
    static let autoPagingDistancePercent = "settings.reader.autoPagingDistancePercent"
    static let autoPagingTurnsChapter = "settings.reader.autoPagingTurnsChapter"
    static let showsChapterCommentsAtEnd = "settings.reader.showsChapterCommentsAtEnd"
    static let showsSystemStatus = "settings.reader.showsSystemStatus"
    static let systemStatusFollowsUIVisibility = "settings.reader.systemStatusFollowsUIVisibility"
    static let systemStatusStyle = "settings.reader.systemStatusStyle"
    static let systemStatusPosition = "settings.reader.systemStatusPosition"
    static let systemStatusBottomInset = "settings.reader.systemStatusBottomInset"
    static let usesProgressGlassBackground = "settings.reader.usesProgressGlassBackground"
    static let usesSystemStatusGlassBackground = "settings.reader.usesSystemStatusGlassBackground"
    static let showsReadingListBookToast = "settings.reader.showsReadingListBookToast"
    static let showsReadingListLoadingToast = "settings.reader.showsReadingListLoadingToast"
    static let readingListAutoAdvancesAtBoundary = "settings.reader.readingListAutoAdvancesAtBoundary"
    static let visibilityDefaultsVersion = "settings.reader.visibilityDefaultsVersion"
}

enum ReaderProgressStyle: String, CaseIterable, Identifiable {
    case circular
    case capsule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circular:
            "圆形"
        case .capsule:
            "胶囊"
        }
    }
}

enum ReaderUIToggleMode: String, CaseIterable, Identifiable {
    case single
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            "单击"
        case .double:
            "双击"
        }
    }
}

enum ReaderReadingMode: String, CaseIterable, Identifiable {
    case topToBottomContinuous
    case topToBottom
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topToBottomContinuous:
            "从上到下（连续）"
        case .topToBottom:
            "从上到下"
        case .leftToRight:
            "从左到右"
        case .rightToLeft:
            "从右到左"
        }
    }

    var description: String {
        switch self {
        case .topToBottomContinuous:
            "竖向连续滚动，所有图片顺序排列。"
        case .topToBottom:
            "单页竖向分页，每次翻到下一张。"
        case .leftToRight:
            "单页横向分页，按左到右方向阅读。"
        case .rightToLeft:
            "单页横向分页，按右到左方向阅读。"
        }
    }
}

enum ReaderProgressPosition: String, CaseIterable, Identifiable, Equatable {
    case leading
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading:
            "左下角"
        case .trailing:
            "右下角"
        }
    }

    var alignment: Alignment {
        switch self {
        case .leading:
            .bottomLeading
        case .trailing:
            .bottomTrailing
        }
    }
}

enum ReaderSystemStatusStyle: String, CaseIterable, Identifiable, Equatable {
    case compact
    case detailed
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            "紧凑"
        case .detailed:
            "详细"
        case .text:
            "文字"
        }
    }

    var bottomClearance: CGFloat {
        switch self {
        case .compact:
            38
        case .detailed:
            48
        case .text:
            28
        }
    }
}

enum ReaderOverlayPosition: String, CaseIterable, Identifiable, Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading:
            "左上角"
        case .topTrailing:
            "右上角"
        case .bottomLeading:
            "左下角"
        case .bottomTrailing:
            "右下角"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading:
            .topLeading
        case .topTrailing:
            .topTrailing
        case .bottomLeading:
            .bottomLeading
        case .bottomTrailing:
            .bottomTrailing
        }
    }

    var edgeInsets: EdgeInsets {
        switch self {
        case .topLeading:
            EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 0)
        case .topTrailing:
            EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 16)
        case .bottomLeading:
            EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 0)
        case .bottomTrailing:
            EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        }
    }

    var isBottom: Bool {
        switch self {
        case .topLeading, .topTrailing:
            false
        case .bottomLeading, .bottomTrailing:
            true
        }
    }
}

struct ReaderProgressOverlay: View {
    let title: String
    let progress: Double
    let style: ReaderProgressStyle
    let showsPageLabel: Bool
    let backgroundOpacity: Double
    let usesGlassBackground: Bool

    @ViewBuilder
    var body: some View {
        switch style {
        case .circular:
            circularBody
        case .capsule:
            capsuleBody
        }
    }

    private var circularBody: some View {
        HStack(spacing: showsPageLabel ? 7 : 0) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(normalizedProgress))
                    .stroke(
                        AngularGradient(
                            colors: [.white.opacity(0.72), .white, .white.opacity(0.86)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(percentText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            if showsPageLabel {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, showsPageLabel ? 10 : 6)
        .padding(.vertical, 5)
        .frame(minWidth: showsPageLabel ? 112 : 44, alignment: .leading)
        .readerCapsuleSurface(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground, fillScale: 0.42)
    }

    private var capsuleBody: some View {
        HStack(spacing: 8) {
            Text(percentText)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)

            if showsPageLabel {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: showsPageLabel ? 158 : 76, alignment: .leading)
        .readerCapsuleSurface(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground, fillScale: 0.38)
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: max(proxy.size.width * CGFloat(normalizedProgress), 8))
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
        }
    }

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentText: String {
        "\(Int((normalizedProgress * 100).rounded()))%"
    }
}

struct ReaderSystemStatusOverlay: View {
    let style: ReaderSystemStatusStyle
    let backgroundOpacity: Double
    let usesGlassBackground: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(date: context.date, battery: ReaderBatterySnapshot.current)
        }
        .onAppear {
            ReaderBatterySnapshot.enableMonitoring()
        }
    }

    @ViewBuilder
    private func content(date: Date, battery: ReaderBatterySnapshot) -> some View {
        switch style {
        case .compact:
            HStack(spacing: 7) {
                Text(timeText(date))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: batteryIcon(battery))
                    .font(.caption2.weight(.semibold))
                Text(batteryText(battery))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .statusBackground(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground)
        case .detailed:
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText(date))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(batteryStateText(battery))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.62))
                }

                batteryRing(battery)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .statusBackground(opacity: backgroundOpacity, usesLiquidGlass: usesGlassBackground)
        case .text:
            Text("\(timeText(date))  \(batteryText(battery))")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 2)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
        }
    }

    private func batteryRing(_ battery: ReaderBatterySnapshot) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(battery.level))
                .stroke(battery.level <= 0.2 ? .red.opacity(0.88) : .white.opacity(0.82), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((battery.level * 100).rounded()))")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(width: 28, height: 28)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func batteryText(_ battery: ReaderBatterySnapshot) -> String {
        "\(Int((battery.level * 100).rounded()))%"
    }

    private func batteryIcon(_ battery: ReaderBatterySnapshot) -> String {
        if battery.state == .charging || battery.state == .full {
            return "battery.100.bolt"
        }
        switch battery.level {
        case ..<0.18:
            return "battery.0"
        case ..<0.42:
            return "battery.25"
        case ..<0.68:
            return "battery.50"
        case ..<0.9:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private func batteryStateText(_ battery: ReaderBatterySnapshot) -> String {
        switch battery.state {
        case .charging:
            return "充电中"
        case .full:
            return "已充满"
        default:
            return "电量"
        }
    }
}

struct ReaderBatterySnapshot {
    let level: Double
    let state: BatteryState

    enum BatteryState: Equatable {
        case unplugged
        case charging
        case full
        case unknown
    }

    static func enableMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    static var current: ReaderBatterySnapshot {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel < 0 ? 1 : Double(rawLevel)
        let state: BatteryState
        switch UIDevice.current.batteryState {
        case .charging:
            state = .charging
        case .full:
            state = .full
        case .unplugged:
            state = .unplugged
        default:
            state = .unknown
        }
        return ReaderBatterySnapshot(level: min(max(level, 0), 1), state: state)
        #else
        return ReaderBatterySnapshot(level: 1, state: .unknown)
        #endif
    }
}

struct ReaderAutoPagingModifier: ViewModifier {
    let isEnabled: Bool
    let interval: Double
    let onTick: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(Timer.publish(every: interval, on: .main, in: .common).autoconnect()) { _ in
                guard isEnabled else { return }
                onTick()
            }
    }
}

struct ReaderProgressSelectionDialog: View {
    @Environment(\.dismiss) private var dismiss

    let context: ReaderProgressSelectionContext
    let onSelect: (Int) -> Void
    @State private var selectedPage: Int

    init(context: ReaderProgressSelectionContext, onSelect: @escaping (Int) -> Void) {
        self.context = context
        self.onSelect = onSelect
        _selectedPage = State(initialValue: min(max(context.pageIndex + 1, 1), max(context.pageCount, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("选择阅读进度", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text(context.chapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Text("\(selectedPage)/\(max(context.pageCount, 1))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if context.pageCount > 1 {
                Slider(value: selectedPageValue, in: 1...Double(context.pageCount), step: 1)
            }

            Stepper(value: $selectedPage, in: 1...max(context.pageCount, 1)) {
                Text("第 \(selectedPage) 页")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("跳转") {
                    onSelect(selectedPage - 1)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var selectedPageValue: Binding<Double> {
        Binding {
            Double(selectedPage)
        } set: { value in
            selectedPage = min(max(Int(value.rounded()), 1), max(context.pageCount, 1))
        }
    }
}

struct ReaderToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .readerToastGlassBackground()
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    }
}

extension View {
    @ViewBuilder
    func readerToastGlassBackground() -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self
                .background(.black.opacity(0.34), in: Capsule(style: .continuous))
                .glassEffect(.regular.tint(.black.opacity(0.28)), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .background(.black.opacity(0.38), in: Capsule(style: .continuous))
        }
    }

    func readerAutoPaging(isEnabled: Bool, interval: Double, onTick: @escaping () -> Void) -> some View {
        modifier(ReaderAutoPagingModifier(isEnabled: isEnabled, interval: interval, onTick: onTick))
    }

    @ViewBuilder
    func readerContinuousZoom(
        configuration: ReaderZoomConfiguration,
        resetID: String
    ) -> some View {
        #if os(iOS)
        if configuration.isZoomEnabled {
            ReaderContinuousZoomHost(
                configuration: configuration,
                resetID: resetID
            ) {
                self
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    func readerInteractionGesture(
        size: CGSize,
        mode: ReaderUIToggleMode,
        tapPagingEnabled: Bool,
        tapPagingEdgePercent: Int,
        tapPagingInverted: Bool,
        doubleTapZoomEnabled: Bool,
        readingMode: ReaderReadingMode,
        toggleUI: @escaping () -> Void,
        turnPage: @escaping (ReaderPageTurnDirection) -> Void
    ) -> some View {
        modifier(ReaderInteractionGestureModifier(
            size: size,
            mode: mode,
            tapPagingEnabled: tapPagingEnabled,
            tapPagingEdgePercent: tapPagingEdgePercent,
            tapPagingInverted: tapPagingInverted,
            doubleTapZoomEnabled: doubleTapZoomEnabled,
            readingMode: readingMode,
            toggleUI: toggleUI,
            turnPage: turnPage
        ))
    }

    @ViewBuilder
    func readerConditionalSimultaneousGesture<G: Gesture>(_ gesture: G, enabled: Bool) -> some View {
        if enabled {
            self.simultaneousGesture(gesture)
        } else {
            self
        }
    }

    @ViewBuilder
    func readerConditionalHighPriorityGesture<G: Gesture>(_ gesture: G, enabled: Bool) -> some View {
        if enabled {
            self.highPriorityGesture(gesture)
        } else {
            self
        }
    }

    @ViewBuilder
    func statusBackground(opacity: Double, usesLiquidGlass: Bool, appliesWhenDisabled: Bool = true) -> some View {
        if appliesWhenDisabled || usesLiquidGlass {
            self
                .readerCapsuleSurface(
                    opacity: opacity,
                    usesLiquidGlass: usesLiquidGlass,
                    fillScale: appliesWhenDisabled ? 0.38 : 0,
                    minimumOpacity: appliesWhenDisabled ? 0.18 : 0,
                    strokeOpacity: appliesWhenDisabled ? 0.14 : 0
                )
        } else {
            self
        }
    }

    @ViewBuilder
    func readerCapsuleSurface(
        opacity: Double,
        usesLiquidGlass: Bool,
        fillScale: Double,
        minimumOpacity: Double = 0.18,
        strokeOpacity: Double = 0.16
    ) -> some View {
        if usesLiquidGlass {
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                self
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(max(opacity * 0.18, 0.08)))
                    }
                    .glassEffect(.regular, in: .capsule)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            } else {
                self
                    .readerCapsuleFallbackSurface(
                        opacity: opacity,
                        fillScale: fillScale,
                        minimumOpacity: minimumOpacity,
                        strokeOpacity: strokeOpacity
                    )
            }
        } else {
            self
                .readerCapsuleFallbackSurface(
                    opacity: opacity,
                    fillScale: fillScale,
                    minimumOpacity: minimumOpacity,
                    strokeOpacity: strokeOpacity
                )
        }
    }

    func readerCapsuleFallbackSurface(
        opacity: Double,
        fillScale: Double,
        minimumOpacity: Double,
        strokeOpacity: Double
    ) -> some View {
        self
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(max(opacity * fillScale, minimumOpacity)))
            }
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
    }
}

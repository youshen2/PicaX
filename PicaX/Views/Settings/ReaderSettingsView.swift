import SwiftUI

struct ReaderSettingsView: View {
    @AppStorage(ReaderSettingsKey.progressStyle) private var progressStyle = ReaderProgressStyle.circular.rawValue
    @AppStorage(ReaderSettingsKey.progressPosition) private var progressPosition = ReaderProgressPosition.trailing.rawValue
    @AppStorage(ReaderSettingsKey.showsPageLabel) private var showsPageLabel = true
    @AppStorage(ReaderSettingsKey.progressFollowsUIVisibility) private var progressFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.progressTapSelectionEnabled) private var progressTapSelectionEnabled = false
    @AppStorage(ReaderSettingsKey.progressBackgroundOpacity) private var progressBackgroundOpacity = 0.78
    @AppStorage(ReaderSettingsKey.progressBottomInset) private var progressBottomInset = 0.0
    @AppStorage(ReaderSettingsKey.readingMode) private var readingMode = ReaderReadingMode.topToBottomContinuous.rawValue
    @AppStorage(ReaderSettingsKey.wholeBookContinuousReading) private var wholeBookContinuousReading = false
    @AppStorage(ReaderSettingsKey.wholeBookContinuesReadingList) private var wholeBookContinuesReadingList = false
    @AppStorage(ReaderSettingsKey.imageSpacing) private var imageSpacing = 0.0
    @AppStorage(ReaderSettingsKey.firstImageTopPadding) private var firstImageTopPadding = 115.0
    @AppStorage(ReaderSettingsKey.lastImageBottomPadding) private var lastImageBottomPadding = 0.0
    @AppStorage(ReaderSettingsKey.preloadImageCount) private var preloadImageCount = 3
    @AppStorage(ReaderSettingsKey.preloadsNextChapterNearEnd) private var preloadsNextChapterNearEnd = false
    @AppStorage(ReaderSettingsKey.chapterEndPageThreshold) private var chapterEndPageThreshold = 3
    @AppStorage(ReaderSettingsKey.pagedPreloadDelay) private var pagedPreloadDelay = 1.2
    @AppStorage(ReaderSettingsKey.imageRetryCount) private var imageRetryCount = 2
    @AppStorage(ReaderSettingsKey.imageRetryInterval) private var imageRetryInterval = 1.0
    @AppStorage(ReaderSettingsKey.reducesImageBrightnessInDarkMode) private var reducesImageBrightnessInDarkMode = false
    @AppStorage(ReaderSettingsKey.hidesStatusBar) private var hidesStatusBar = false
    @AppStorage(ReaderSettingsKey.uiToggleMode) private var uiToggleMode = ReaderUIToggleMode.single.rawValue
    @AppStorage(ReaderSettingsKey.tapPagingEnabled) private var tapPagingEnabled = false
    @AppStorage(ReaderSettingsKey.tapPagingInverted) private var tapPagingInverted = false
    @AppStorage(ReaderSettingsKey.tapPagingEdgePercent) private var tapPagingEdgePercent = 28
    @AppStorage(ReaderSettingsKey.tapPagingDistancePercent) private var tapPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.pinchZoomEnabled) private var pinchZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomEnabled) private var doubleTapZoomEnabled = true
    @AppStorage(ReaderSettingsKey.doubleTapZoomScale) private var doubleTapZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.longPressZoomEnabled) private var longPressZoomEnabled = true
    @AppStorage(ReaderSettingsKey.longPressZoomScale) private var longPressZoomScale = 1.75
    @AppStorage(ReaderSettingsKey.longPressZoomTriggerDuration) private var longPressZoomTriggerDuration = ReaderZoomConfiguration.defaultLongPressTriggerDuration
    @AppStorage(ReaderSettingsKey.autoPagingInterval) private var autoPagingInterval = 6.0
    @AppStorage(ReaderSettingsKey.autoPagingDistancePercent) private var autoPagingDistancePercent = 85
    @AppStorage(ReaderSettingsKey.smoothContinuousAutoPaging) private var smoothContinuousAutoPaging = false
    @AppStorage(ReaderSettingsKey.autoPagingTurnsChapter) private var autoPagingTurnsChapter = true
    @AppStorage(ReaderSettingsKey.showsNextChapterButtonAtEnd) private var showsNextChapterButtonAtEnd = false
    @AppStorage(ReaderSettingsKey.chapterEndButtonPosition) private var chapterEndButtonPosition = ReaderOverlayPosition.bottomTrailing.rawValue
    @AppStorage(ReaderSettingsKey.chapterEndButtonHorizontalInset) private var chapterEndButtonHorizontalInset = 20.0
    @AppStorage(ReaderSettingsKey.chapterEndButtonVerticalInset) private var chapterEndButtonVerticalInset = 24.0
    @AppStorage(ReaderSettingsKey.nextChapterButtonSwitchesBooks) private var nextChapterButtonSwitchesBooks = false
    @AppStorage(ReaderSettingsKey.showsChapterCommentsAtEnd) private var showsChapterCommentsAtEnd = false
    @AppStorage(ReaderSettingsKey.showsSystemStatus) private var showsSystemStatus = false
    @AppStorage(ReaderSettingsKey.systemStatusFollowsUIVisibility) private var systemStatusFollowsUIVisibility = false
    @AppStorage(ReaderSettingsKey.systemStatusStyle) private var systemStatusStyle = ReaderSystemStatusStyle.compact.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusPosition) private var systemStatusPosition = ReaderOverlayPosition.bottomLeading.rawValue
    @AppStorage(ReaderSettingsKey.systemStatusBottomInset) private var systemStatusBottomInset = 0.0
    @AppStorage(ReaderSettingsKey.usesProgressGlassBackground) private var usesProgressGlassBackground = false
    @AppStorage(ReaderSettingsKey.usesSystemStatusGlassBackground) private var usesSystemStatusGlassBackground = false
    @AppStorage(ReaderSettingsKey.showsReadingListBookToast) private var showsReadingListBookToast = true
    @AppStorage(ReaderSettingsKey.showsReadingListLoadingToast) private var showsReadingListLoadingToast = true
    @AppStorage(ReaderSettingsKey.readingListAutoAdvancesAtBoundary) private var readingListAutoAdvancesAtBoundary = true

    var body: some View {
        List {
            Section("预览") {
                ReaderSettingsPreview(
                    style: selectedStyle,
                    position: selectedPosition,
                    showsPageLabel: showsPageLabel,
                    backgroundOpacity: progressBackgroundOpacity,
                    progressBottomInset: progressBottomInset,
                    imageSpacing: imageSpacing,
                    firstImageTopPadding: firstImageTopPadding,
                    lastImageBottomPadding: lastImageBottomPadding,
                    showsSystemStatus: showsSystemStatus,
                    systemStatusStyle: selectedSystemStatusStyle,
                    systemStatusPosition: selectedSystemStatusPosition,
                    systemStatusBottomInset: systemStatusBottomInset,
                    usesProgressGlassBackground: effectiveUsesProgressGlassBackground,
                    usesSystemStatusGlassBackground: effectiveUsesSystemStatusGlassBackground
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            Section("状态栏") {
                Toggle("隐藏状态栏", isOn: $hidesStatusBar)
            }

            Section {
                Picker("阅读方式", selection: $readingMode) {
                    ForEach(ReaderReadingMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }

                Toggle("整卷连续阅读", isOn: $wholeBookContinuousReading)
                    .disabled(selectedReadingMode == .pageCurl)
                Toggle("自动连续下一本书", isOn: $wholeBookContinuesReadingList)
                    .disabled(!wholeBookContinuousReading || selectedReadingMode == .pageCurl)
                Toggle("深色模式下降低图片亮度", isOn: $reducesImageBrightnessInDarkMode)
            } header: {
                Text("阅读")
            } footer: {
                Text(readingFooter)
            }

            Section {
                IntegerSettingsInputRow(
                    title: "预加载图片",
                    value: $preloadImageCount,
                    unit: "张",
                    lowerBound: 0,
                    upperBound: 15
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("预加载延迟 \(pagedPreloadDelay, specifier: "%.1f") 秒")
                    Slider(value: $pagedPreloadDelay, in: 0...5, step: 0.1)
                }

                Toggle("接近章节末尾时预加载下一章", isOn: $preloadsNextChapterNearEnd)
            } header: {
                Text("预加载")
            } footer: {
                Text("将预加载图片设为 0 可关闭图片预加载。开启下一章预加载后，会按照“章节末尾”分区设置的范围提前获取下一章图片列表，并按设置数量加载开头图片。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("翻页间隔 \(autoPagingInterval, specifier: "%.0f") 秒")
                    Slider(value: $autoPagingInterval, in: 1...30, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("翻页距离 \(autoPagingDistancePercent)% 屏幕高度")
                    Slider(value: autoPagingDistancePercentBinding, in: 10...120, step: 5)
                }
                .disabled(selectedReadingMode != .topToBottomContinuous)

                Toggle("平滑持续滚动", isOn: $smoothContinuousAutoPaging)
                    .disabled(selectedReadingMode != .topToBottomContinuous)

                Toggle("自动进入下一章", isOn: $autoPagingTurnsChapter)
                    .disabled(wholeBookContinuousReading && selectedReadingMode != .pageCurl)
            } header: {
                Text("自动翻页")
            } footer: {
                Text(autoPagingFooter)
            }

            Section {
                IntegerSettingsInputRow(
                    title: "章节末尾范围",
                    value: $chapterEndPageThreshold,
                    unit: "页",
                    lowerBound: 1,
                    upperBound: 30
                )

                Toggle("显示下一章浮动按钮", isOn: $showsNextChapterButtonAtEnd)

                if showsNextChapterButtonAtEnd {
                    Picker("浮动按钮位置", selection: $chapterEndButtonPosition) {
                        ForEach(ReaderOverlayPosition.allCases) { position in
                            Text(position.title)
                                .tag(position.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("水平边距 \(Int(chapterEndButtonHorizontalInset))")
                        Slider(value: $chapterEndButtonHorizontalInset, in: 0...120, step: 2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("垂直边距 \(Int(chapterEndButtonVerticalInset))")
                        Slider(value: $chapterEndButtonVerticalInset, in: 0...120, step: 2)
                    }

                    Toggle("批量阅读时用于切换书籍", isOn: $nextChapterButtonSwitchesBooks)
                }

                Toggle("章节末尾显示评论", isOn: $showsChapterCommentsAtEnd)
            } header: {
                Text("章节末尾")
            } footer: {
                Text("最后 \(boundedChapterEndPageThreshold) 页会视为章节末尾，并同时用于下一章预加载和浮动按钮。按钮边距从所选角落的屏幕边缘开始计算，控制栏显示时会自动避让。存在下一章时显示“下一章”；开启批量阅读切换后，最后一章存在下一本书时显示“下一本”。")
            }

            Section {
                Picker("切换 UI 显隐方式", selection: $uiToggleMode) {
                    ForEach(ReaderUIToggleMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("点按翻页", isOn: $tapPagingEnabled)

                if tapPagingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("点按识别范围 \(tapPagingEdgePercent)%")
                        Slider(value: tapPagingEdgePercentBinding, in: 5...45, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻页距离 \(tapPagingDistancePercent)% 屏幕高度")
                        Slider(value: tapPagingDistancePercentBinding, in: 10...120, step: 5)
                    }
                    .disabled(selectedReadingMode != .topToBottomContinuous)

                    Toggle("反转点按翻页", isOn: $tapPagingInverted)
                }

                Toggle("阅读进度跟随控制栏隐藏", isOn: $progressFollowsUIVisibility)

                Toggle("时间电量跟随控制栏隐藏", isOn: $systemStatusFollowsUIVisibility)
                    .disabled(!showsSystemStatus)
            } header: {
                Text("交互")
            } footer: {
                Text(interactionFooter)
            }

            Section {
                Toggle("切换时显示加载提示", isOn: $showsReadingListLoadingToast)

                Toggle("切换完成后显示书名", isOn: $showsReadingListBookToast)

                Toggle("按章节阅读时自动切换书籍", isOn: $readingListAutoAdvancesAtBoundary)
            } header: {
                Text("批量阅读")
            } footer: {
                Text("批量阅读切换书籍时会保留当前阅读器并显示加载提示，加载完成后再切换内容。此开关用于按章节阅读；整卷连续阅读使用“阅读”分区中的独立开关。关闭后，底栏上一章/下一章按钮仍可在书籍边界手动切换。")
            }

            Section {
                Toggle("两指缩放", isOn: $pinchZoomEnabled)

                Toggle("双击缩放", isOn: $doubleTapZoomEnabled)
                    .disabled(selectedUIToggleMode == .double)

                if doubleTapZoomEnabled && selectedUIToggleMode != .double {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("双击放大 \(doubleTapZoomScale, specifier: "%.1f")x")
                        Slider(value: $doubleTapZoomScale, in: 1.2...5, step: 0.1)
                    }
                }

                Toggle("长按缩放", isOn: $longPressZoomEnabled)

                if longPressZoomEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("长按触发时间 \(longPressZoomTriggerDuration, specifier: "%.1f") 秒")
                        Slider(
                            value: $longPressZoomTriggerDuration,
                            in: ReaderZoomConfiguration.longPressTriggerDurationRange,
                            step: 0.1
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("长按放大 \(longPressZoomScale, specifier: "%.1f")x")
                        Slider(value: $longPressZoomScale, in: 1.2...5, step: 0.1)
                    }
                }
            } header: {
                Text("缩放")
            } footer: {
                Text("长按缩放为按住临时放大，松开恢复。双击缩放与“双击切换 UI”互斥。")
            }

            Section("时间与电量") {
                Toggle("显示时间与电量", isOn: $showsSystemStatus)

                if showsSystemStatus {
                    Picker("状态样式", selection: $systemStatusStyle) {
                        ForEach(ReaderSystemStatusStyle.allCases) { style in
                            Text(style.title)
                                .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("状态位置", selection: $systemStatusPosition) {
                        ForEach(ReaderOverlayPosition.allCases) { position in
                            Text(position.title)
                                .tag(position.rawValue)
                        }
                    }

                    if supportsLiquidGlassBackground, selectedSystemStatusStyle != .text {
                        Toggle("液体玻璃背景", isOn: $usesSystemStatusGlassBackground)
                    }

                    if selectedSystemStatusPosition.isBottom {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("底部距离 \(Int(systemStatusBottomInset))")
                            Slider(value: $systemStatusBottomInset, in: 0...96, step: 2)
                        }
                    }
                }
            }

            Section("进度") {
                Picker("样式", selection: $progressStyle) {
                    ForEach(ReaderProgressStyle.allCases) { style in
                        Text(style.title)
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("显示位置", selection: $progressPosition) {
                    ForEach(ReaderProgressPosition.allCases) { position in
                        Text(position.title)
                            .tag(position.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("显示页码", isOn: $showsPageLabel)

                Toggle("点击进度选择页码", isOn: $progressTapSelectionEnabled)

                if supportsLiquidGlassBackground {
                    Toggle("液体玻璃背景", isOn: $usesProgressGlassBackground)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("底部距离 \(Int(progressBottomInset))")
                    Slider(value: $progressBottomInset, in: 0...120, step: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("浮层透明度 \(Int(progressBackgroundOpacity * 100))%")
                    Slider(value: $progressBackgroundOpacity, in: 0.45...0.95, step: 0.05)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("图片间距 \(Int(imageSpacing))")
                    Slider(value: $imageSpacing, in: 0...24, step: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("首图顶部留白 \(Int(firstImageTopPadding))")
                    Slider(value: $firstImageTopPadding, in: 0...160, step: 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("末图底部留白 \(Int(lastImageBottomPadding))")
                    Slider(value: $lastImageBottomPadding, in: 0...160, step: 4)
                }

                IntegerSettingsInputRow(title: "图片重试次数", value: $imageRetryCount, unit: "次", lowerBound: 0, upperBound: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("重试间隔 \(imageRetryInterval, specifier: "%.1f") 秒")
                    Slider(value: $imageRetryInterval, in: 0.2...10, step: 0.2)
                }
            } header: {
                Text("图片")
            }
        }
        .picaxInsetGroupedListStyle()
        .navigationTitle("阅读器")
        .picaxHidesTabBar()
    }

    private var selectedStyle: ReaderProgressStyle {
        ReaderProgressStyle(rawValue: progressStyle) ?? .circular
    }

    private var readingFooter: String {
        var descriptions = [selectedReadingMode.description]
        if selectedReadingMode == .pageCurl {
            descriptions.append("仿真翻页按章节阅读，不支持整卷连续阅读。")
        } else if wholeBookContinuousReading {
            descriptions.append("下一章会提前追加到当前章节末尾，直到全书结束。")
            if wholeBookContinuesReadingList {
                descriptions.append("从阅读列表进入时，读完全书后会自动打开下一本书。")
            }
        }
        return descriptions.joined(separator: "\n")
    }

    private var autoPagingFooter: String {
        guard selectedReadingMode == .topToBottomContinuous else {
            return "当前阅读方式会按页切换；自动翻页距离和平滑持续滚动只在连续滚动中生效。"
        }
        guard smoothContinuousAutoPaging else {
            return "翻页距离决定每次自动滚动的距离。"
        }
        return "翻页距离会均匀分布在翻页间隔内，以恒定速度持续滚动。"
    }

    private var interactionFooter: String {
        var description = "“单击切换 UI”或“双击切换 UI”只控制阅读器顶部与底部控制栏的显示或隐藏，不影响“隐藏状态栏”设置。点按翻页开启后，边缘区域翻页，中间区域按所选方式切换 UI。关闭跟随后，对应浮层会在控制栏隐藏时继续显示。"
        if tapPagingEnabled, selectedReadingMode != .topToBottomContinuous {
            description += " 当前阅读方式会直接切页，点按翻页距离不生效。"
        }
        return description
    }

    private var boundedChapterEndPageThreshold: Int {
        min(max(chapterEndPageThreshold, 1), 30)
    }

    private var selectedPosition: ReaderProgressPosition {
        ReaderProgressPosition(rawValue: progressPosition) ?? .trailing
    }

    private var selectedReadingMode: ReaderReadingMode {
        ReaderReadingMode(rawValue: readingMode) ?? .topToBottomContinuous
    }

    private var selectedUIToggleMode: ReaderUIToggleMode {
        ReaderUIToggleMode(rawValue: uiToggleMode) ?? .single
    }

    private var selectedSystemStatusStyle: ReaderSystemStatusStyle {
        ReaderSystemStatusStyle(rawValue: systemStatusStyle) ?? .compact
    }

    private var selectedSystemStatusPosition: ReaderOverlayPosition {
        ReaderOverlayPosition(rawValue: systemStatusPosition) ?? .bottomLeading
    }

    private var effectiveUsesProgressGlassBackground: Bool {
        supportsLiquidGlassBackground && usesProgressGlassBackground
    }

    private var effectiveUsesSystemStatusGlassBackground: Bool {
        supportsLiquidGlassBackground && usesSystemStatusGlassBackground
    }

    private var supportsLiquidGlassBackground: Bool {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            return true
        } else {
            return false
        }
    }

    private var tapPagingEdgePercentBinding: Binding<Double> {
        Binding {
            Double(tapPagingEdgePercent)
        } set: { value in
            tapPagingEdgePercent = min(max(Int(value.rounded()), 5), 45)
        }
    }

    private var autoPagingDistancePercentBinding: Binding<Double> {
        Binding {
            Double(autoPagingDistancePercent)
        } set: { value in
            autoPagingDistancePercent = min(max(Int(value.rounded()), 10), 120)
        }
    }

    private var tapPagingDistancePercentBinding: Binding<Double> {
        Binding {
            Double(tapPagingDistancePercent)
        } set: { value in
            tapPagingDistancePercent = min(max(Int(value.rounded()), 10), 120)
        }
    }

}

private struct ReaderSettingsPreview: View {
    let style: ReaderProgressStyle
    let position: ReaderProgressPosition
    let showsPageLabel: Bool
    let backgroundOpacity: Double
    let progressBottomInset: Double
    let imageSpacing: Double
    let firstImageTopPadding: Double
    let lastImageBottomPadding: Double
    let showsSystemStatus: Bool
    let systemStatusStyle: ReaderSystemStatusStyle
    let systemStatusPosition: ReaderOverlayPosition
    let systemStatusBottomInset: Double
    let usesProgressGlassBackground: Bool
    let usesSystemStatusGlassBackground: Bool

    var body: some View {
        ZStack(alignment: position.alignment) {
            VStack(spacing: CGFloat(imageSpacing)) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(height: 118)
                    .padding(.top, CGFloat(firstImageTopPadding * 0.22))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: 86)
                    .padding(.bottom, CGFloat(lastImageBottomPadding * 0.22))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 22, height: 22)
                Spacer()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .frame(width: 86, height: 14)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .frame(maxHeight: .infinity, alignment: .top)

            ReaderProgressOverlay(
                title: "E1/3 · P12/28",
                progress: 0.42,
                style: style,
                showsPageLabel: showsPageLabel,
                backgroundOpacity: backgroundOpacity,
                usesGlassBackground: usesProgressGlassBackground
            )
            .padding(.horizontal, 16)
            .padding(.bottom, progressBottomPadding)

            if showsSystemStatus {
                ReaderSystemStatusOverlay(
                    style: systemStatusStyle,
                    backgroundOpacity: backgroundOpacity,
                    usesGlassBackground: usesSystemStatusGlassBackground
                )
                    .padding(systemStatusInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: systemStatusPosition.alignment)
                    .allowsHitTesting(false)
            }
        }
    }

    private var progressBottomPadding: CGFloat {
        let baseInset = CGFloat(progressBottomInset)
        guard showsSystemStatus else { return baseInset }
        switch (position, systemStatusPosition) {
        case (.leading, .bottomLeading), (.trailing, .bottomTrailing):
            return max(baseInset, CGFloat(systemStatusBottomInset) + systemStatusStyle.bottomClearance)
        default:
            return baseInset
        }
    }

    private var systemStatusInsets: EdgeInsets {
        var insets = systemStatusPosition.edgeInsets
        switch systemStatusPosition {
        case .topLeading, .topTrailing:
            insets.top = 58
        case .bottomLeading, .bottomTrailing:
            break
        }
        switch systemStatusPosition {
        case .topLeading, .topTrailing:
            break
        case .bottomLeading, .bottomTrailing:
            insets.bottom = CGFloat(systemStatusBottomInset)
        }
        return insets
    }
}

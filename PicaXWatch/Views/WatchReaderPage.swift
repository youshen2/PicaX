import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchReaderPage: View {
    @EnvironmentObject private var accountSyncStore: WatchAccountSyncStore
    @EnvironmentObject private var downloadService: WatchDownloadService
    @StateObject private var viewModel = WatchReaderViewModel()
    @AppStorage(WatchSettingsKey.readerReadingMode) private var readingModeRawValue = WatchReaderReadingMode.continuousVertical.rawValue
    @AppStorage(WatchSettingsKey.readerImageSpacing) private var imageSpacing = 0
    @AppStorage(WatchSettingsKey.readerFirstImageTopPadding) private var firstImageTopPadding = 24
    @AppStorage(WatchSettingsKey.readerLastImageBottomPadding) private var lastImageBottomPadding = 24
    @AppStorage(WatchSettingsKey.readerRetryCount) private var retryCount = 2
    @AppStorage(WatchSettingsKey.readerRetryIntervalSeconds) private var retryIntervalSeconds = 1
    @AppStorage(WatchSettingsKey.readerShowsProgress) private var showsProgress = true
    @AppStorage(WatchSettingsKey.readerProgressPosition) private var progressPositionRawValue = WatchReaderOverlayPosition.bottomLeading.rawValue
    @AppStorage(WatchSettingsKey.readerProgressEdgeInset) private var progressEdgeInset = 8
    @AppStorage(WatchSettingsKey.readerProgressBottomInset) private var progressBottomInset = 3
    @AppStorage(WatchSettingsKey.readerUsesProgressGlassBackground) private var usesProgressGlassBackground = true
    @AppStorage(WatchSettingsKey.readerShowsSystemStatus) private var showsSystemStatus = true
    @AppStorage(WatchSettingsKey.readerSystemStatusPosition) private var systemStatusPositionRawValue = WatchReaderOverlayPosition.bottomTrailing.rawValue
    @AppStorage(WatchSettingsKey.readerSystemStatusEdgeInset) private var systemStatusEdgeInset = 8
    @AppStorage(WatchSettingsKey.readerSystemStatusBottomInset) private var systemStatusBottomInset = 3
    @AppStorage(WatchSettingsKey.readerUsesSystemStatusGlassBackground) private var usesSystemStatusGlassBackground = true
    @State private var currentPageIndex = 0
    @State private var currentPageCount = 0
    @State private var currentChapter: WatchChapterItem
    @State private var currentChapterIndex: Int
    @State private var currentChapterPosition: Int
    @State private var initialPageIndex: Int
    @State private var presentsReaderMenu = false
    @State private var hidesReaderUI = false

    let item: WatchComicItem
    let totalChapters: Int
    let downloadedRecord: WatchDownloadRecord?
    private let availableChapters: [WatchChapterItem]
    private let availableChapterIndexes: [Int]

    init(
        item: WatchComicItem,
        chapter: WatchChapterItem,
        chapterIndex: Int = 0,
        totalChapters: Int = 1,
        initialPageIndex: Int = 0,
        downloadedRecord: WatchDownloadRecord? = nil,
        chapters: [WatchChapterItem] = [],
        chapterIndexes: [Int]? = nil
    ) {
        let normalizedChapters = chapters.isEmpty ? [chapter] : chapters
        let normalizedIndexes: [Int]
        if let chapterIndexes, chapterIndexes.count == normalizedChapters.count {
            normalizedIndexes = chapterIndexes
        } else if chapters.isEmpty {
            normalizedIndexes = [chapterIndex]
        } else {
            normalizedIndexes = Array(normalizedChapters.indices)
        }
        let initialPosition = normalizedIndexes.firstIndex(of: chapterIndex)
            ?? min(max(chapterIndex, 0), max(normalizedChapters.count - 1, 0))

        self.item = item
        self.totalChapters = max(max(totalChapters, normalizedIndexes.max().map { $0 + 1 } ?? 1), 1)
        self.downloadedRecord = downloadedRecord
        self.availableChapters = normalizedChapters
        self.availableChapterIndexes = normalizedIndexes
        _currentChapter = State(initialValue: normalizedChapters[initialPosition])
        _currentChapterIndex = State(initialValue: normalizedIndexes[initialPosition])
        _currentChapterPosition = State(initialValue: initialPosition)
        _initialPageIndex = State(initialValue: initialPageIndex)
    }

    var body: some View {
        readerContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if canToggleReaderUI {
                    toggleReaderUI()
                }
            }
        )
        .overlay {
            overlayLayer
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        }
        .navigationTitle(currentChapter.title)
        .toolbar {
            if !hidesReaderUI {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentsReaderMenu = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .watchReaderToolbarButtonSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("更多")
                }
            }
        }
        .toolbar(hidesReaderUI ? .hidden : .visible, for: .navigationBar)
        .animation(.easeInOut(duration: 0.18), value: hidesReaderUI)
        .sheet(isPresented: $presentsReaderMenu) {
            WatchReaderMenuSheet(
                chapters: availableChapters,
                chapterIndexes: availableChapterIndexes,
                currentChapterPosition: currentChapterPosition,
                canSwitchPreviousChapter: canSwitchPreviousChapter,
                canSwitchNextChapter: canSwitchNextChapter,
                chapterTitle: chapterMenuTitle(for:at:),
                onSwitchPreviousChapter: {
                    switchChapter(offset: -1)
                },
                onSwitchNextChapter: {
                    switchChapter(offset: 1)
                },
                onSelectChapter: { position in
                    switchChapter(to: position)
                }
            )
        }
        .task {
            await load()
        }
        .onDisappear {
            persistCurrentProgress()
        }
    }

    private var overlayLayer: some View {
        ZStack {
            if !hidesReaderUI, showsProgress, currentPageCount > 0 {
                WatchReaderProgressCapsule(
                    pageIndex: currentPageIndex,
                    pageCount: currentPageCount,
                    chapterIndex: currentChapterIndex,
                    chapterCount: totalChapters,
                    usesGlassBackground: usesProgressGlassBackground
                )
                .padding(capsuleInsets(position: progressPosition, edgeInset: progressEdgeInset, bottomInset: progressBottomInset))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: progressPosition.alignment)
            }

            if !hidesReaderUI, showsSystemStatus {
                WatchReaderSystemStatusCapsule(usesGlassBackground: usesSystemStatusGlassBackground)
                    .padding(capsuleInsets(position: effectiveSystemStatusPosition, edgeInset: systemStatusEdgeInset, bottomInset: systemStatusBottomInset))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: effectiveSystemStatusPosition.alignment)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .padding(.top, 24)
        case .failed(let message):
            List {
                Section {
                    WatchValueRow(title: "加载失败", subtitle: message, systemImage: "exclamationmark.triangle", tint: .orange)
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                }
            }
        case .loaded(let images):
            if images.isEmpty {
                List {
                    Section {
                        WatchEmptyRow(title: "没有可阅读图片", systemImage: "photo")
                    }
                }
            } else {
                switch readingMode {
                case .continuousVertical:
                    continuousContent(images)
                case .pagedVertical:
                    pagedContent(images, axis: .vertical)
                case .pagedHorizontal:
                    pagedContent(images, axis: .horizontal)
                }
            }
        }
    }

    private func continuousContent(_ images: [WatchChapterImage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: CGFloat(validatedImageSpacing)) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        readerImage(image, index: index, total: images.count)
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollToInitialPage(with: proxy, images: images)
            }
        }
    }

    private func pagedContent(_ images: [WatchChapterImage], axis: Axis.Set) -> some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(axis) {
                    if axis == .horizontal {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                                readerImage(image, index: index, total: images.count)
                                    .frame(width: geometry.size.width)
                                    .frame(minHeight: geometry.size.height)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                                readerImage(image, index: index, total: images.count)
                                    .frame(width: geometry.size.width)
                                    .frame(minHeight: geometry.size.height)
                            }
                        }
                    }
                }
            }
            .onAppear {
                scrollToInitialPage(with: proxy, images: images)
            }
        }
    }

    private func readerImage(_ image: WatchChapterImage, index: Int, total: Int) -> some View {
        WatchReaderImageView(
            image: image,
            retryCount: validatedRetryCount,
            retryIntervalSeconds: validatedRetryIntervalSeconds
        )
        .padding(.top, index == 0 ? CGFloat(validatedFirstImageTopPadding) : 0)
        .padding(.bottom, index == total - 1 ? CGFloat(validatedLastImageBottomPadding) : 0)
        .id(image.id)
        .onAppear {
            currentPageIndex = index
            currentPageCount = total
            recordProgress(pageIndex: index, totalPages: total)
            Task { await viewModel.prefetch(around: index) }
        }
    }

    private func load(force: Bool = false) async {
        if let downloadedRecord {
            let images = await downloadService.localChapterImages(for: downloadedRecord, chapterIndex: currentChapterIndex)
            await viewModel.loadLocalImages(images, force: force)
        } else {
            await viewModel.load(
                item: item,
                chapter: currentChapter,
                account: accountSyncStore.snapshot.account(for: item.platform),
                force: force
            )
        }
        if initialPageIndex > 0 {
            currentPageIndex = initialPageIndex
        }
        persistCurrentProgress()
    }

    private func recordProgress(pageIndex: Int, totalPages: Int) {
        WatchReadingHistoryStore().record(
            item: item,
            chapterIndex: currentChapterIndex,
            pageIndex: pageIndex,
            totalPages: totalPages,
            totalChapters: totalChapters
        )
    }

    private func persistCurrentProgress() {
        let totalPages: Int
        if currentPageCount > 0 {
            totalPages = currentPageCount
        } else if case .loaded(let images) = viewModel.state {
            totalPages = images.count
        } else {
            totalPages = 0
        }
        let pageIndex = totalPages > 0 ? min(currentPageIndex, totalPages - 1) : currentPageIndex
        recordProgress(pageIndex: pageIndex, totalPages: totalPages)
    }

    private func scrollToInitialPage(with proxy: ScrollViewProxy, images: [WatchChapterImage]) {
        guard images.indices.contains(initialPageIndex) else { return }
        let targetID = images[initialPageIndex].id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            proxy.scrollTo(targetID, anchor: .top)
        }
    }

    private var canSwitchNextChapter: Bool {
        availableChapters.indices.contains(currentChapterPosition + 1)
    }

    private var canSwitchPreviousChapter: Bool {
        availableChapters.indices.contains(currentChapterPosition - 1)
    }

    private func switchChapter(offset: Int) {
        switchChapter(to: currentChapterPosition + offset)
    }

    private func switchChapter(to position: Int) {
        guard position != currentChapterPosition,
              availableChapters.indices.contains(position),
              availableChapterIndexes.indices.contains(position) else {
            return
        }
        currentChapterPosition = position
        currentChapter = availableChapters[position]
        currentChapterIndex = availableChapterIndexes[position]
        currentPageIndex = 0
        currentPageCount = 0
        initialPageIndex = 0
        persistCurrentProgress()
        Task { await load(force: true) }
    }

    private func chapterMenuTitle(for chapter: WatchChapterItem, at position: Int) -> String {
        let chapterNumber = availableChapterIndexes.indices.contains(position)
            ? availableChapterIndexes[position] + 1
            : position + 1
        return "第 \(chapterNumber) 章 · \(chapter.title)"
    }

    private var canToggleReaderUI: Bool {
        if case .loaded(let images) = viewModel.state {
            return !images.isEmpty
        }
        return false
    }

    private func toggleReaderUI() {
        hidesReaderUI.toggle()
        if hidesReaderUI {
            presentsReaderMenu = false
        }
    }

    private var readingMode: WatchReaderReadingMode {
        WatchReaderReadingMode(rawValue: readingModeRawValue) ?? .continuousVertical
    }

    private var validatedRetryCount: Int {
        min(max(retryCount, 0), 8)
    }

    private var validatedRetryIntervalSeconds: Int {
        min(max(retryIntervalSeconds, 0), 10)
    }

    private var validatedImageSpacing: Int {
        min(max(imageSpacing, 0), 24)
    }

    private var validatedFirstImageTopPadding: Int {
        min(max(firstImageTopPadding, 0), 160)
    }

    private var validatedLastImageBottomPadding: Int {
        min(max(lastImageBottomPadding, 0), 160)
    }

    private var progressPosition: WatchReaderOverlayPosition {
        WatchReaderOverlayPosition(rawValue: progressPositionRawValue) ?? .bottomLeading
    }

    private var systemStatusPosition: WatchReaderOverlayPosition {
        WatchReaderOverlayPosition(rawValue: systemStatusPositionRawValue) ?? .bottomTrailing
    }

    private var effectiveSystemStatusPosition: WatchReaderOverlayPosition {
        guard showsProgress else { return systemStatusPosition }
        guard systemStatusPosition == progressPosition else { return systemStatusPosition }
        switch progressPosition {
        case .topLeading:
            return .topTrailing
        case .topTrailing:
            return .topLeading
        case .bottomLeading:
            return .bottomTrailing
        case .bottomTrailing:
            return .bottomLeading
        }
    }

    private func capsuleInsets(position: WatchReaderOverlayPosition, edgeInset: Int, bottomInset: Int) -> EdgeInsets {
        let edge = CGFloat(min(max(edgeInset, 0), 60))
        let bottom = CGFloat(min(max(bottomInset, 0), 80))
        switch position {
        case .topLeading:
            return EdgeInsets(top: edge, leading: edge, bottom: 0, trailing: 0)
        case .topTrailing:
            return EdgeInsets(top: edge, leading: 0, bottom: 0, trailing: edge)
        case .bottomLeading:
            return EdgeInsets(top: 0, leading: edge, bottom: bottom, trailing: 0)
        case .bottomTrailing:
            return EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: edge)
        }
    }
}

private struct WatchReaderMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    let chapters: [WatchChapterItem]
    let chapterIndexes: [Int]
    let currentChapterPosition: Int
    let canSwitchPreviousChapter: Bool
    let canSwitchNextChapter: Bool
    let chapterTitle: (WatchChapterItem, Int) -> String
    let onSwitchPreviousChapter: () -> Void
    let onSwitchNextChapter: () -> Void
    let onSelectChapter: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        onSwitchPreviousChapter()
                    } label: {
                        Label("上一章", systemImage: "chevron.up")
                    }
                    .disabled(!canSwitchPreviousChapter)

                    Button {
                        dismiss()
                        onSwitchNextChapter()
                    } label: {
                        Label("下一章", systemImage: "chevron.down")
                    }
                    .disabled(!canSwitchNextChapter)
                }

                Section("章节列表") {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { position, chapter in
                        Button {
                            dismiss()
                            onSelectChapter(position)
                        } label: {
                            HStack(spacing: 6) {
                                Text(chapterTitle(chapter, position))
                                    .lineLimit(2)
                                Spacer(minLength: 4)
                                if position == currentChapterPosition {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        .disabled(position == currentChapterPosition || !chapterIndexes.indices.contains(position))
                    }
                }
            }
            .navigationTitle("更多")
        }
    }
}

struct WatchReaderImageView: View {
    let image: WatchChapterImage
    var retryCount: Int = 2
    var retryIntervalSeconds: Int = 1

    @State private var displayURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadToken = UUID()
    @State private var didRetryDisplayFailure = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let displayURL {
                AsyncImage(url: displayURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    case .success(let value):
                        value
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    case .failure:
                        if didRetryDisplayFailure {
                            failureContent("图片显示失败")
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .task(id: displayURL.absoluteString) {
                                    await reloadAfterDisplayFailure()
                                }
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorMessage {
                failureContent(errorMessage)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(.horizontal, 4)
        .task(id: loadToken) {
            await loadImage()
        }
        .onChange(of: image.urlString) { _ in
            loadToken = UUID()
        }
    }

    private func failureContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchValueRow(title: "图片加载失败", subtitle: message, systemImage: "photo.badge.exclamationmark", tint: .orange)
            Button {
                loadToken = UUID()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadImage() async {
        didRetryDisplayFailure = false
        if let localURL = WatchImageCacheService.localCachedURL(for: image.urlString) {
            displayURL = localURL
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let attempts = retryCount + 1
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                displayURL = try await WatchImageCacheService.cachedFileURL(for: image.urlString)
                errorMessage = nil
                return
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                if retryIntervalSeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(retryIntervalSeconds) * 1_000_000_000)
                }
            }
        }
        errorMessage = lastError?.localizedDescription ?? image.urlString
    }

    private func reloadAfterDisplayFailure() async {
        guard !didRetryDisplayFailure else { return }
        didRetryDisplayFailure = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let attempts = retryCount + 1
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                displayURL = try await WatchImageCacheService.cachedFileURL(for: image.urlString, forceRefresh: true)
                errorMessage = nil
                return
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                if retryIntervalSeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(retryIntervalSeconds) * 1_000_000_000)
                }
            }
        }
        displayURL = nil
        errorMessage = lastError?.localizedDescription ?? image.urlString
    }
}

private struct WatchReaderProgressCapsule: View {
    let pageIndex: Int
    let pageCount: Int
    let chapterIndex: Int
    let chapterCount: Int
    let usesGlassBackground: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(percentText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(pageIndex + 1)/\(max(pageCount, 1))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .watchReaderCapsuleSurface(usesLiquidGlass: usesGlassBackground)
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(width: max(proxy.size.width * CGFloat(progress), 6))
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
        }
        .accessibilityLabel("阅读进度 \(percentText)")
    }

    private var progress: Double {
        guard pageCount > 0 else { return 0 }
        return min(max(Double(pageIndex + 1) / Double(pageCount), 0), 1)
    }

    private var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

private struct WatchReaderSystemStatusCapsule: View {
    let usesGlassBackground: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 4) {
                Text(context.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: batteryIcon)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text(batteryText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .watchReaderCapsuleSurface(usesLiquidGlass: usesGlassBackground)
        }
        .onAppear {
            #if os(watchOS)
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            #endif
        }
        .accessibilityLabel("时间和电量")
    }

    private var batteryLevel: Double {
        #if os(watchOS)
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let rawLevel = WKInterfaceDevice.current().batteryLevel
        return rawLevel < 0 ? 1 : Double(min(max(rawLevel, 0), 1))
        #else
        return 1
        #endif
    }

    private var batteryText: String {
        "\(Int((batteryLevel * 100).rounded()))%"
    }

    private var batteryIcon: String {
        #if os(watchOS)
        let state = WKInterfaceDevice.current().batteryState
        if state == .charging || state == .full {
            return "battery.100.bolt"
        }
        #endif
        switch batteryLevel {
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
}

private extension View {
    @ViewBuilder
    func watchReaderToolbarButtonSurface() -> some View {
        if #available(watchOS 26.0, *) {
            self
                .background {
                    Circle()
                        .fill(.black.opacity(0.12))
                }
                .glassEffect(.regular.tint(.white.opacity(0.16)).interactive(), in: .circle)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        } else {
            self.watchReaderToolbarButtonFallbackSurface()
        }
    }

    func watchReaderToolbarButtonFallbackSurface() -> some View {
        self
            .background(.black.opacity(0.56), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }

    @ViewBuilder
    func watchReaderCapsuleSurface(usesLiquidGlass: Bool) -> some View {
        if usesLiquidGlass {
            if #available(watchOS 26.0, *) {
                self
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.12))
                    }
                    .glassEffect(.regular, in: .capsule)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            } else {
                self.watchReaderCapsuleFallbackSurface()
            }
        } else {
            self.watchReaderCapsuleFallbackSurface()
        }
    }

    func watchReaderCapsuleFallbackSurface() -> some View {
        self
            .background(.black.opacity(0.56), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

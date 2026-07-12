import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ReaderScrollTargetLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetLayout()
        } else {
            content
        }
    }
}

struct ReaderPagingScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetBehavior(.paging)
        } else {
            content
        }
    }
}

enum ReaderPageTurnDirection {
    case previous
    case next

    var inverted: ReaderPageTurnDirection {
        switch self {
        case .previous:
            .next
        case .next:
            .previous
        }
    }
}

struct ReaderScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat

    init(offsetY: CGFloat, contentHeight: CGFloat, visibleHeight: CGFloat) {
        self.offsetY = max(offsetY, 0)
        self.contentHeight = max(contentHeight, 0)
        self.visibleHeight = max(visibleHeight, 0)
    }
}

struct ReaderContinuousScrollSnapshot {
    let chapterIndex: Int
    let scrollY: CGFloat
}

@MainActor
final class ReaderContinuousScrollBridge {
    #if os(iOS)
    private weak var scrollView: UIScrollView?
    private var pendingScroll: (y: CGFloat, animated: Bool)?

    func attach(scrollView: UIScrollView?) {
        self.scrollView = scrollView
        guard scrollView != nil, let pendingScroll else { return }
        self.pendingScroll = nil
        _ = self.scroll(toY: pendingScroll.y, animated: pendingScroll.animated)
    }
    #endif

    func scroll(toY y: CGFloat, animated: Bool) -> Bool {
        #if os(iOS)
        guard let scrollView else {
            pendingScroll = (y, animated)
            return false
        }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom,
            minY
        )
        let targetY = min(max(y, minY), maxY)
        guard targetY.isFinite else { return false }

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: animated
        )
        return true
        #else
        return false
        #endif
    }
}

@MainActor
final class ReaderContinuousScrollTracker {
    private static let verticalPadding: CGFloat = 10
    private static let defaultAspectRatio: Double = 1.42

    private(set) var scrollY: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0
    private(set) var visibleHeight: CGFloat = 0
    private var isReady = false
    private var aspectRatios: [Int: Double] = [:]
    private var lastReportedPageIndex: Int?

    var hasContentMetrics: Bool {
        contentHeight > 0 && visibleHeight > 0
    }

    func reset() {
        scrollY = 0
        contentHeight = 0
        visibleHeight = 0
        isReady = false
        aspectRatios.removeAll(keepingCapacity: true)
        lastReportedPageIndex = nil
    }

    func setReady() {
        isReady = true
    }

    func updateMetrics(_ metrics: ReaderScrollMetrics) {
        scrollY = metrics.offsetY
        contentHeight = metrics.contentHeight
        visibleHeight = metrics.visibleHeight
    }

    func updateScrollY(_ value: CGFloat) {
        scrollY = max(value, 0)
    }

    @discardableResult
    func effectiveScrollY(fallback: CGFloat?) -> CGFloat {
        if let fallback {
            updateScrollY(fallback)
        }
        return scrollY
    }

    @discardableResult
    func updateAspectRatio(
        _ aspectRatio: Double,
        for index: Int,
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat? {
        guard images.indices.contains(index),
              displayWidth.isFinite,
              displayWidth > 0,
              aspectRatio.isFinite,
              aspectRatio > 0 else {
            if index >= 0, aspectRatio.isFinite, aspectRatio > 0 {
                aspectRatios[index] = aspectRatio
            }
            return nil
        }

        let oldAspectRatio = self.aspectRatio(for: index, image: images[index])
        guard abs(oldAspectRatio - aspectRatio) > 0.001 else {
            aspectRatios[index] = aspectRatio
            return nil
        }

        let oldPageTop = pageTop(
            for: index,
            images: images,
            displayWidth: displayWidth,
            imageSpacing: imageSpacing,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )
        let oldPageHeight = pageHeight(
            for: index,
            imageCount: images.count,
            displayWidth: displayWidth,
            aspectRatio: oldAspectRatio,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )
        aspectRatios[index] = aspectRatio
        let newPageHeight = pageHeight(
            for: index,
            imageCount: images.count,
            displayWidth: displayWidth,
            aspectRatio: aspectRatio,
            firstImageTopPadding: firstImageTopPadding,
            lastImageBottomPadding: lastImageBottomPadding
        )

        guard isReady,
              oldPageTop.isFinite,
              oldPageHeight.isFinite,
              newPageHeight.isFinite else {
            return nil
        }

        let heightDelta = newPageHeight - oldPageHeight
        guard abs(heightDelta) > 0.5 else { return nil }

        let oldPageBottom = oldPageTop + oldPageHeight
        let adjustedY: CGFloat?
        if oldPageBottom <= scrollY + 1 {
            adjustedY = scrollY + heightDelta
        } else if oldPageTop < scrollY {
            let progressInsidePage = min(max((scrollY - oldPageTop) / max(oldPageHeight, 1), 0), 1)
            adjustedY = scrollY + heightDelta * progressInsidePage
        } else {
            adjustedY = nil
        }

        guard let adjustedY else { return nil }
        scrollY = max(adjustedY, 0)
        return scrollY
    }

    func maxScrollY(fallbackViewportHeight: CGFloat) -> CGFloat {
        max(contentHeight - max(visibleHeight, fallbackViewportHeight, 1), 0)
    }

    func visiblePageIndices(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
        fallbackViewportHeight: CGFloat
    ) -> Set<Int> {
        guard isReady, !images.isEmpty, displayWidth.isFinite, displayWidth > 0 else {
            return []
        }

        let viewportHeight = max(visibleHeight > 0 ? visibleHeight : fallbackViewportHeight, 0)
        guard viewportHeight > 0 else { return [] }

        let viewportPadding: CGFloat = 8
        let viewportTop = max(scrollY - viewportPadding, 0)
        let viewportBottom = scrollY + viewportHeight + viewportPadding
        var visibleIndices = Set<Int>()
        var pageTop = Self.verticalPadding

        for index in images.indices {
            let pageHeight = pageHeight(
                for: index,
                imageCount: images.count,
                displayWidth: displayWidth,
                aspectRatio: aspectRatio(for: index, image: images[index]),
                firstImageTopPadding: firstImageTopPadding,
                lastImageBottomPadding: lastImageBottomPadding
            )
            let pageBottom = pageTop + pageHeight
            if pageBottom >= viewportTop, pageTop <= viewportBottom {
                visibleIndices.insert(index)
            } else if pageTop > viewportBottom {
                break
            }

            pageTop = pageBottom
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }

        return visibleIndices
    }

    func visiblePageIndex(
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat,
        fallbackViewportHeight: CGFloat
    ) -> Int? {
        guard isReady, !images.isEmpty, displayWidth.isFinite, displayWidth > 0 else {
            return nil
        }

        let viewportHeight = max(visibleHeight > 0 ? visibleHeight : fallbackViewportHeight, 0)
        guard viewportHeight > 0 else { return nil }

        let viewportTop = scrollY
        let viewportBottom = viewportTop + viewportHeight
        let viewportCenterY = viewportTop + viewportHeight / 2
        var bestIndex: Int?
        var bestVisibleHeight: CGFloat = 0
        var bestDistanceFromCenter = CGFloat.greatestFiniteMagnitude
        var pageTop = Self.verticalPadding

        for index in images.indices {
            let topPadding = index == images.startIndex ? max(firstImageTopPadding, 0) : 0
            let bottomPadding = index == images.index(before: images.endIndex) ? max(lastImageBottomPadding, 0) : 0
            let imageHeight = displayWidth * CGFloat(aspectRatio(for: index, image: images[index]))
            let pageHeight = topPadding + max(imageHeight, 120) + bottomPadding
            let pageBottom = pageTop + pageHeight
            let visibleTop = max(pageTop, viewportTop)
            let visibleBottom = min(pageBottom, viewportBottom)
            let visibleHeight = max(visibleBottom - visibleTop, 0)

            if visibleHeight > 1 {
                let distanceFromCenter = abs((pageTop + pageBottom) / 2 - viewportCenterY)
                if visibleHeight > bestVisibleHeight + 1
                    || (abs(visibleHeight - bestVisibleHeight) <= 1 && distanceFromCenter < bestDistanceFromCenter) {
                    bestIndex = index
                    bestVisibleHeight = visibleHeight
                    bestDistanceFromCenter = distanceFromCenter
                }
            }

            pageTop = pageBottom
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }

        guard let bestIndex, bestIndex != lastReportedPageIndex else {
            return nil
        }
        lastReportedPageIndex = bestIndex
        return bestIndex
    }

    private func aspectRatio(for index: Int, image: ComicChapterImage) -> Double {
        if let aspectRatio = aspectRatios[index] {
            return aspectRatio
        }
        if let cached = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) {
            aspectRatios[index] = cached
            return cached
        }
        return Self.defaultAspectRatio
    }

    private func pageTop(
        for targetIndex: Int,
        images: [ComicChapterImage],
        displayWidth: CGFloat,
        imageSpacing: CGFloat,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat {
        var pageTop = Self.verticalPadding
        for index in images.indices {
            if index == targetIndex {
                return pageTop
            }
            let pageHeight = pageHeight(
                for: index,
                imageCount: images.count,
                displayWidth: displayWidth,
                aspectRatio: aspectRatio(for: index, image: images[index]),
                firstImageTopPadding: firstImageTopPadding,
                lastImageBottomPadding: lastImageBottomPadding
            )
            pageTop += pageHeight
            if index != images.index(before: images.endIndex) {
                pageTop += max(imageSpacing, 0)
            }
        }
        return pageTop
    }

    private func pageHeight(
        for index: Int,
        imageCount: Int,
        displayWidth: CGFloat,
        aspectRatio: Double,
        firstImageTopPadding: CGFloat,
        lastImageBottomPadding: CGFloat
    ) -> CGFloat {
        let topPadding = index == 0 ? max(firstImageTopPadding, 0) : 0
        let bottomPadding = index == imageCount - 1 ? max(lastImageBottomPadding, 0) : 0
        let imageHeight = displayWidth * CGFloat(aspectRatio)
        return topPadding + max(imageHeight, 120) + bottomPadding
    }
}

extension View {
    @ViewBuilder
    func readerContinuousScrollBridge(
        _ bridge: ReaderContinuousScrollBridge,
        onMetricsChange: ((ReaderScrollMetrics) -> Void)? = nil
    ) -> some View {
        #if os(iOS)
        background {
            ReaderScrollViewResolver(
                bridge: bridge,
                onMetricsChange: onMetricsChange,
                offsetAxis: nil,
                onOffsetChange: nil
            )
                .frame(width: 0, height: 0)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func readerScrollOffsetObserver(
        axis: Axis,
        onChange: @escaping (_ oldValue: CGFloat, _ newValue: CGFloat) -> Void
    ) -> some View {
        #if os(iOS)
        background {
            ReaderScrollViewResolver(
                bridge: nil,
                onMetricsChange: nil,
                offsetAxis: axis,
                onOffsetChange: onChange
            )
                .frame(width: 0, height: 0)
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct ReaderScrollViewResolver: UIViewRepresentable {
    let bridge: ReaderContinuousScrollBridge?
    let onMetricsChange: ((ReaderScrollMetrics) -> Void)?
    let offsetAxis: Axis?
    let onOffsetChange: ((_ oldValue: CGFloat, _ newValue: CGFloat) -> Void)?

    func makeUIView(context: Context) -> ReaderScrollViewResolverView {
        let view = ReaderScrollViewResolverView()
        view.update(
            bridge: bridge,
            onMetricsChange: onMetricsChange,
            offsetAxis: offsetAxis,
            onOffsetChange: onOffsetChange
        )
        return view
    }

    func updateUIView(_ uiView: ReaderScrollViewResolverView, context: Context) {
        uiView.update(
            bridge: bridge,
            onMetricsChange: onMetricsChange,
            offsetAxis: offsetAxis,
            onOffsetChange: onOffsetChange
        )
    }

    static func dismantleUIView(_ uiView: ReaderScrollViewResolverView, coordinator: ()) {
        uiView.update(bridge: nil, onMetricsChange: nil, offsetAxis: nil, onOffsetChange: nil)
    }
}

private final class ReaderScrollViewResolverView: UIView {
    private weak var bridge: ReaderContinuousScrollBridge?
    private weak var observedScrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var onMetricsChange: ((ReaderScrollMetrics) -> Void)?
    private var offsetAxis: Axis?
    private var onOffsetChange: ((_ oldValue: CGFloat, _ newValue: CGFloat) -> Void)?
    private var lastMetrics: ReaderScrollMetrics?
    private var lastOffset: CGFloat?

    func update(
        bridge: ReaderContinuousScrollBridge?,
        onMetricsChange: ((ReaderScrollMetrics) -> Void)?,
        offsetAxis: Axis?,
        onOffsetChange: ((_ oldValue: CGFloat, _ newValue: CGFloat) -> Void)?
    ) {
        self.bridge = bridge
        self.onMetricsChange = onMetricsChange
        self.offsetAxis = offsetAxis
        self.onOffsetChange = onOffsetChange
        resolveScrollView()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveScrollView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveScrollView()
    }

    private func resolveScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            attach(to: nearestScrollView())
        }
    }

    private func attach(to scrollView: UIScrollView?) {
        if observedScrollView === scrollView {
            reportScrollState()
            return
        }

        observations.removeAll()
        observedScrollView = scrollView
        lastMetrics = nil
        lastOffset = nil
        bridge?.attach(scrollView: scrollView)

        guard let scrollView else { return }
        observations = [
            scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                self?.reportScrollState()
            },
            scrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
                self?.reportScrollState()
            },
            scrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
                self?.reportScrollState()
            }
        ]
    }

    private func reportScrollState() {
        guard let scrollView = observedScrollView else { return }

        let metrics = ReaderScrollMetrics(
            offsetY: scrollView.contentOffset.y,
            contentHeight: scrollView.contentSize.height,
            visibleHeight: scrollView.bounds.height
        )
        if metrics != lastMetrics {
            lastMetrics = metrics
            onMetricsChange?(metrics)
        }

        guard let offsetAxis, let onOffsetChange else { return }
        let offset = offsetAxis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        if let lastOffset, abs(lastOffset - offset) > 0.25 {
            onOffsetChange(lastOffset, offset)
        }
        lastOffset = offset
    }

    private func nearestScrollView() -> UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
#endif

import Foundation
import SwiftUI

struct ReaderZoomConfiguration: Equatable {
    let pinchEnabled: Bool
    let doubleTapEnabled: Bool
    let doubleTapScale: CGFloat
    let longPressEnabled: Bool
    let longPressScale: CGFloat

    var normalizedDoubleTapScale: CGFloat {
        min(max(doubleTapScale, 1.2), 5)
    }

    var normalizedLongPressScale: CGFloat {
        min(max(longPressScale, 1.2), 5)
    }

    var isZoomEnabled: Bool {
        pinchEnabled || doubleTapEnabled || longPressEnabled
    }
}

struct ReaderInteractionGestureModifier: ViewModifier {
    private static let delayedSingleTapNanoseconds: UInt64 = 260_000_000
    private static let doubleTapSuppressionDuration: TimeInterval = 0.45

    let size: CGSize
    let mode: ReaderUIToggleMode
    let tapPagingEnabled: Bool
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let doubleTapZoomEnabled: Bool
    let readingMode: ReaderReadingMode
    let toggleUI: () -> Void
    let turnPage: (ReaderPageTurnDirection) -> Void
    @State private var delayedTapTask: Task<Void, Never>?
    @State private var tapSuppressionUntil = Date.distantPast

    func body(content: Content) -> some View {
        let content = content
            .contentShape(Rectangle())
            .simultaneousGesture(tapMovementSuppressionGesture)

        switch mode {
        case .single:
            if doubleTapZoomEnabled {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                content
                    .simultaneousGesture(singleTapGesture)
            }
        case .double:
            if doubleTapZoomEnabled {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                content
                    .simultaneousGesture(singleTapGesture)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { _ in toggleUI() })
            }
        }
    }

    private var tapMovementSuppressionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if shouldSuppressTap(for: value.translation) {
                    suppressTapForCurrentMovement()
                }
            }
            .onEnded { value in
                if shouldSuppressTap(for: value.translation) {
                    suppressTapForCurrentMovement()
                }
            }
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { value in
                handleSingleTap(at: value.location)
            }
    }

    private var doubleTapCancellationGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                suppressTapAfterDoubleTap()
            }
    }

    private func scheduleDelayedTap(at location: CGPoint) {
        delayedTapTask?.cancel()
        delayedTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.delayedSingleTapNanoseconds)
            guard !Task.isCancelled else { return }
            handleTap(at: location)
            delayedTapTask = nil
        }
    }

    private func handleSingleTap(at location: CGPoint) {
        guard !isTapSuppressed else { return }

        if doubleTapZoomEnabled {
            scheduleDelayedTap(at: location)
        } else {
            handleTap(at: location)
        }
    }

    private func handleTap(at location: CGPoint) {
        guard !isTapSuppressed else {
            return
        }

        if tapPagingEnabled, let direction = tapPageDirection(at: location) {
            turnPage(tapPagingInverted ? direction.inverted : direction)
            return
        }

        if mode == .single {
            toggleUI()
        }
    }

    private var isTapSuppressed: Bool {
        ReaderZoomTapSuppressor.shouldSuppressTap || Date() < tapSuppressionUntil
    }

    private func tapPageDirection(at location: CGPoint) -> ReaderPageTurnDirection? {
        let ratio = CGFloat(min(max(tapPagingEdgePercent, 5), 45)) / 100
        guard size.width > 0, size.height > 0 else { return nil }

        switch readingMode {
        case .leftToRight:
            if location.x >= size.width * (1 - ratio) { return .next }
            if location.x <= size.width * ratio { return .previous }
        case .rightToLeft:
            if location.x >= size.width * (1 - ratio) { return .previous }
            if location.x <= size.width * ratio { return .next }
        case .topToBottom, .topToBottomContinuous:
            if location.y >= size.height * (1 - ratio) { return .next }
            if location.y <= size.height * ratio { return .previous }
        }

        return nil
    }

    private func shouldSuppressTap(for translation: CGSize) -> Bool {
        let distance = hypot(translation.width, translation.height)
        return distance > 6
    }

    private func suppressTapForCurrentMovement() {
        delayedTapTask?.cancel()
        delayedTapTask = nil
        tapSuppressionUntil = Date().addingTimeInterval(0.25)
    }

    private func suppressTapAfterDoubleTap() {
        delayedTapTask?.cancel()
        delayedTapTask = nil
        tapSuppressionUntil = Date().addingTimeInterval(Self.doubleTapSuppressionDuration)
        ReaderZoomTapSuppressor.suppressTap(for: Self.doubleTapSuppressionDuration)
    }
}

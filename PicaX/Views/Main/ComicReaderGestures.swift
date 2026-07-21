import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ReaderZoomConfiguration: Equatable {
    static let defaultLongPressTriggerDuration: TimeInterval = 0.3
    static let longPressTriggerDurationRange: ClosedRange<TimeInterval> = 0.1...1.0

    let pinchEnabled: Bool
    let doubleTapEnabled: Bool
    let doubleTapScale: CGFloat
    let longPressEnabled: Bool
    let longPressScale: CGFloat
    let longPressTriggerDuration: TimeInterval

    var normalizedDoubleTapScale: CGFloat {
        min(max(doubleTapScale, 1.2), 5)
    }

    var normalizedLongPressScale: CGFloat {
        min(max(longPressScale, 1.2), 5)
    }

    var normalizedLongPressTriggerDuration: TimeInterval {
        min(
            max(longPressTriggerDuration, Self.longPressTriggerDurationRange.lowerBound),
            Self.longPressTriggerDurationRange.upperBound
        )
    }

    var isZoomEnabled: Bool {
        pinchEnabled || doubleTapEnabled || longPressEnabled
    }

    var interactionDisabled: ReaderZoomConfiguration {
        ReaderZoomConfiguration(
            pinchEnabled: false,
            doubleTapEnabled: false,
            doubleTapScale: doubleTapScale,
            longPressEnabled: false,
            longPressScale: longPressScale,
            longPressTriggerDuration: longPressTriggerDuration
        )
    }
}

@MainActor
private final class ReaderInteractionGestureState {
    var delayedTapTask: Task<Void, Never>?
    var tapSuppressionUntil = Date.distantPast
}

struct ReaderInteractionGestureModifier: ViewModifier {
    private static let delayedSingleTapNanoseconds: UInt64 = 230_000_000
    private static let doubleTapSuppressionDuration: TimeInterval = 0.45
    private static let movementTapSuppressionDuration: TimeInterval = 0.25

    let size: CGSize
    let mode: ReaderUIToggleMode
    let tapPagingEnabled: Bool
    let tapPagingEdgePercent: Int
    let tapPagingInverted: Bool
    let doubleTapZoomEnabled: Bool
    let readingMode: ReaderReadingMode
    let toggleUI: () -> Void
    let turnPage: (ReaderPageTurnDirection) -> Void
    @State private var interactionState = ReaderInteractionGestureState()

    func body(content: Content) -> some View {
        let baseContent = content
            .contentShape(Rectangle())

        #if os(iOS)
        if #available(iOS 17.0, *) {
            gestureContent(baseContent.simultaneousGesture(tapMovementSuppressionGesture))
        } else {
            gestureContent(baseContent)
        }
        #else
        gestureContent(baseContent.simultaneousGesture(tapMovementSuppressionGesture))
        #endif
    }

    @ViewBuilder
    private func gestureContent<GestureContent: View>(_ content: GestureContent) -> some View {
        switch mode {
        case .single:
            if doubleTapZoomEnabled {
                singleTapContent(content)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                singleTapContent(content)
            }
        case .double:
            if doubleTapZoomEnabled {
                singleTapContent(content)
                    .simultaneousGesture(doubleTapCancellationGesture)
            } else {
                singleTapContent(content)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { _ in toggleUI() })
            }
        }
    }

    @ViewBuilder
    private func singleTapContent<GestureContent: View>(_ content: GestureContent) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            content.simultaneousGesture(singleTapGesture)
        } else {
            content.background {
                ReaderLegacyTapGestureInstaller { location in
                    handleSingleTap(at: location)
                }
            }
        }
        #else
        content.simultaneousGesture(singleTapGesture)
        #endif
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

    @available(iOS 16.0, macOS 13.0, *)
    private var singleTapGesture: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { value in
                handleSingleTap(at: value.location)
            }
    }

    private func handleSingleTap(at location: CGPoint) {
        if doubleTapZoomEnabled {
            scheduleDelayedTap(at: location)
        } else {
            handleTap(at: location)
        }
    }

    private var doubleTapCancellationGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                suppressTapAfterDoubleTap()
            }
    }

    private func scheduleDelayedTap(at location: CGPoint) {
        interactionState.delayedTapTask?.cancel()
        interactionState.delayedTapTask = Task { @MainActor [interactionState] in
            try? await Task.sleep(nanoseconds: Self.delayedSingleTapNanoseconds)
            guard !Task.isCancelled else { return }
            handleTap(at: location)
            interactionState.delayedTapTask = nil
        }
    }

    private func handleTap(at location: CGPoint) {
        guard !ReaderZoomTapSuppressor.shouldSuppressTap,
              Date() >= interactionState.tapSuppressionUntil else {
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
        interactionState.delayedTapTask?.cancel()
        interactionState.delayedTapTask = nil
        interactionState.tapSuppressionUntil = Date().addingTimeInterval(Self.movementTapSuppressionDuration)
    }

    private func suppressTapAfterDoubleTap() {
        interactionState.delayedTapTask?.cancel()
        interactionState.delayedTapTask = nil
        interactionState.tapSuppressionUntil = Date().addingTimeInterval(Self.doubleTapSuppressionDuration)
        ReaderZoomTapSuppressor.suppressTap(for: Self.doubleTapSuppressionDuration)
    }
}

#if os(iOS)
private struct ReaderLegacyTapGestureInstaller: UIViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> ReaderLegacyTapGestureAttachmentView {
        let view = ReaderLegacyTapGestureAttachmentView()
        view.update(onTap: onTap)
        return view
    }

    func updateUIView(_ uiView: ReaderLegacyTapGestureAttachmentView, context: Context) {
        uiView.update(onTap: onTap)
        uiView.attachRecognizerIfNeeded()
    }

    static func dismantleUIView(_ uiView: ReaderLegacyTapGestureAttachmentView, coordinator: ()) {
        uiView.detachRecognizer()
    }
}

private final class ReaderLegacyTapGestureAttachmentView: UIView, UIGestureRecognizerDelegate {
    private weak var recognitionView: UIView?
    private var onTap: ((CGPoint) -> Void)?

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachRecognizerIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachRecognizerIfNeeded()
    }

    func update(onTap: @escaping (CGPoint) -> Void) {
        self.onTap = onTap
    }

    func attachRecognizerIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            let targetView = nearestScrollView() ?? superview
            guard recognitionView !== targetView else { return }
            detachRecognizer()
            targetView?.addGestureRecognizer(tapRecognizer)
            recognitionView = targetView
        }
    }

    func detachRecognizer() {
        recognitionView?.removeGestureRecognizer(tapRecognizer)
        recognitionView = nil
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        guard bounds.contains(location) else { return }
        onTap?(location)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
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

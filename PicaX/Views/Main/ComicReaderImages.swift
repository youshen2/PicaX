import CryptoKit
import Foundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReaderImageView: View {
    let image: ComicChapterImage
    let retryCount: Int
    let retryInterval: Double
    let targetPixelWidth: Int?
    var displayWidth: CGFloat? = nil
    var containerSize: CGSize? = nil
    var isLoadAllowed = true
    let zoomConfiguration: ReaderZoomConfiguration
    let dimsImage: Bool
    var onAspectRatioResolved: ((Double) -> Void)? = nil
    @State private var retryID = 0
    @State private var loadState: ReaderImageLoadState = .loading
    @State private var knownAspectRatio: Double?
    @State private var layoutAspectRatio: Double?
    @State private var reportedLayoutAspectRatio: Double?

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ReaderImagePlaceholder(height: reservedHeight)
            case .loaded(let image):
                ReaderZoomableImage(
                    image: image,
                    imageID: self.image.urlString,
                    displayWidth: displayWidth,
                    containerSize: containerSize,
                    configuration: zoomConfiguration,
                    layoutAspectRatio: currentLayoutAspectRatio,
                    dimsImage: dimsImage
                )
            case .failed:
                ReaderImageFailure(height: reservedHeight) {
                    retryID += 1
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .picaxSensitiveImageContent(image.url != nil)
        .task(id: "\(image.urlString)-\(targetPixelWidth ?? 0)-\(retryID)-\(isLoadAllowed)") {
            guard isLoadAllowed else {
                loadCachedAspectRatio()
                return
            }
            await loadImage()
        }
        .onChange(of: image.urlString) { _, _ in
            resetLocalImageState()
        }
    }

    private var reservedHeight: CGFloat? {
        guard let displayWidth, displayWidth > 0 else {
            return nil
        }
        let aspectRatio = currentLayoutAspectRatio
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return max(displayWidth * 1.42, 120)
        }
        return max(displayWidth * CGFloat(aspectRatio), 120)
    }

    private var currentLayoutAspectRatio: Double {
        let aspectRatio = layoutAspectRatio
            ?? knownAspectRatio
            ?? ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString)
            ?? 1.42
        return aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.42
    }

    @MainActor
    private func loadCachedAspectRatio() {
        guard knownAspectRatio == nil,
              let cachedAspectRatio = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) else {
            return
        }
        receiveAspectRatio(cachedAspectRatio, storesInCache: false)
    }

    @MainActor
    private func loadImage() async {
        guard let url = image.url else {
            loadState = .failed
            return
        }

        if let cachedAspectRatio = ReaderImageAspectRatioCache.shared.aspectRatio(for: image.urlString) {
            receiveAspectRatio(cachedAspectRatio, storesInCache: false)
        }
        loadState = .loading
        let attempts = max(retryCount, 0) + 1
        for attempt in 0..<attempts {
            do {
                let decodedImage = try await ReaderImageDecoder.image(
                    url: url,
                    targetPixelWidth: targetPixelWidth,
                    onAspectRatioResolved: { aspectRatio in
                        guard !Task.isCancelled else { return }
                        receiveAspectRatio(aspectRatio)
                    }
                )
                guard !Task.isCancelled else { return }
                receiveAspectRatio(decodedImage.aspectRatio)
                loadState = .loaded(decodedImage.image)
                return
            } catch {
                guard attempt < attempts - 1 else {
                    loadState = .failed
                    return
                }
                let delay = UInt64(max(retryInterval, 0.2) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
        }
    }

    @MainActor
    private func receiveAspectRatio(_ aspectRatio: Double, storesInCache: Bool = true) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        knownAspectRatio = aspectRatio
        if storesInCache {
            ReaderImageAspectRatioCache.shared.store(aspectRatio, for: image.urlString)
        }
        applyLayoutAspectRatio(aspectRatio)
    }

    @MainActor
    private func applyLayoutAspectRatio(_ aspectRatio: Double) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        layoutAspectRatio = aspectRatio
        guard reportedLayoutAspectRatio.map({ abs($0 - aspectRatio) > 0.001 }) ?? true else {
            return
        }
        reportedLayoutAspectRatio = aspectRatio
        onAspectRatioResolved?(aspectRatio)
    }

    @MainActor
    private func resetLocalImageState() {
        retryID = 0
        loadState = .loading
        knownAspectRatio = nil
        layoutAspectRatio = nil
        reportedLayoutAspectRatio = nil
    }
}

struct ReaderZoomableImage: View {
    let image: PicaXPlatformImage
    let imageID: String
    let displayWidth: CGFloat?
    let containerSize: CGSize?
    let configuration: ReaderZoomConfiguration
    let layoutAspectRatio: Double?
    let dimsImage: Bool

    var body: some View {
        Group {
            if displayWidth != nil {
                Image(picaxImage: image)
                    .resizable()
                    .scaledToFit()
                    .readerImageBrightnessReduction(dimsImage)
            } else {
                ReaderPhotoViewImage(
                    image: image,
                    imageID: imageID,
                    configuration: configuration,
                    dimsImage: dimsImage
                )
                .id(imageID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: reservedDisplayHeight)
    }

    private var reservedDisplayHeight: CGFloat? {
        guard let displayWidth, displayWidth > 0 else { return nil }
        if let layoutAspectRatio, layoutAspectRatio.isFinite, layoutAspectRatio > 0 {
            return max(displayWidth * CGFloat(layoutAspectRatio), 120)
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return displayWidth * size.height / size.width
    }
}

@MainActor
enum ReaderZoomTapSuppressor {
    private static var suppressUntil = Date.distantPast

    static var shouldSuppressTap: Bool {
        Date() < suppressUntil
    }

    static func suppressTap(for duration: TimeInterval = 0.36) {
        suppressUntil = Date().addingTimeInterval(duration)
    }
}

extension View {
    @ViewBuilder
    func readerImageBrightnessReduction(_ isEnabled: Bool) -> some View {
        if isEnabled {
            overlay {
                Color.black
                    .opacity(0.2)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

#if os(iOS)
struct ReaderContinuousZoomHost<Content: View>: UIViewRepresentable {
    let configuration: ReaderZoomConfiguration
    let resetID: String
    let content: Content

    init(
        configuration: ReaderZoomConfiguration,
        resetID: String,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.resetID = resetID
        self.content = content()
    }

    func makeUIView(context: Context) -> ReaderContinuousZoomUIView<Content> {
        ReaderContinuousZoomUIView(rootView: content)
    }

    func updateUIView(_ uiView: ReaderContinuousZoomUIView<Content>, context: Context) {
        uiView.update(rootView: content, configuration: configuration, resetID: resetID)
    }

    static func dismantleUIView(_ uiView: ReaderContinuousZoomUIView<Content>, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

final class ReaderContinuousZoomUIView<Content: View>: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let hostingController: UIHostingController<Content>
    private var resetID = ""
    private var lastBoundsSize: CGSize = .zero
    private var configuration = ReaderZoomConfiguration(
        pinchEnabled: true,
        doubleTapEnabled: true,
        doubleTapScale: 1.75,
        longPressEnabled: true,
        longPressScale: 1.75
    )
    private var longPressStartedZoom = false

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

	    func update(rootView: Content, configuration: ReaderZoomConfiguration, resetID: String) {
	        hostingController.rootView = rootView
	        hostingController.view.invalidateIntrinsicContentSize()
	        hostingController.view.setNeedsLayout()
	        let wasZoomEnabled = self.configuration.isZoomEnabled
	        self.configuration = configuration
	        let shouldReset = self.resetID != resetID
        self.resetID = resetID
        configureGestures()
        configureZoomLimits()
        if shouldReset || (wasZoomEnabled && !configuration.isZoomEnabled) {
            resetZoom(animated: false)
        }
        setNeedsLayout()
    }

    func prepareForReuse() {
        resetZoom(animated: false)
        resetID = ""
    }

    override func layoutSubviews() {
        super.layoutSubviews()
	        guard bounds.width > 0, bounds.height > 0 else { return }
	        scrollView.frame = bounds
	        let didChangeSize = lastBoundsSize != bounds.size
	        lastBoundsSize = bounds.size
	        if didChangeSize {
	            resetZoom(animated: false)
	        }
	        layoutHostedViewForCurrentZoomScale()
	        updateContentInsets()
	        updateInteractionState()
	    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInsets()
        updateInteractionState()
    }

	    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
	        layoutHostedViewForCurrentZoomScale()
	        updateInteractionState()
	    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.isEnabled = false

        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = bounds

        addSubview(scrollView)
        scrollView.addSubview(hostingController.view)
        configureGestures()
        configureZoomLimits()
    }

    private func configureGestures() {
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchEnabled
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousDoubleTapZoom" }) != true {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.name = "reader.continuousDoubleTapZoom"
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.continuousLongPressZoom" }) != true {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = 0.30
            recognizer.allowableMovement = 12
            recognizer.name = "reader.continuousLongPressZoom"
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        scrollView.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "reader.continuousDoubleTapZoom" {
                recognizer.isEnabled = configuration.doubleTapEnabled
            } else if recognizer.name == "reader.continuousLongPressZoom" {
                recognizer.isEnabled = configuration.longPressEnabled
            }
        }
    }

    private func configureZoomLimits() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(2.5, configuration.normalizedDoubleTapScale, configuration.normalizedLongPressScale)
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
        updateInteractionState()
    }

	    private func resetZoom(animated: Bool) {
	        longPressStartedZoom = false
	        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
	        scrollView.contentOffset = .zero
	        if !animated {
	            scrollView.contentSize = bounds.size
	            hostingController.view.transform = .identity
	            hostingController.view.frame = CGRect(origin: .zero, size: bounds.size)
	        }
	        updateContentInsets()
	        updateInteractionState()
	    }

	    private func layoutHostedViewForCurrentZoomScale() {
	        guard bounds.width > 0, bounds.height > 0 else { return }

	        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
	            hostingController.view.transform = .identity
	            hostingController.view.frame = CGRect(origin: .zero, size: bounds.size)
	            scrollView.contentSize = bounds.size
	            return
	        }

	        let oldOffset = scrollView.contentOffset
	        hostingController.view.bounds = CGRect(origin: .zero, size: bounds.size)
	        scrollView.contentSize = CGSize(
	            width: bounds.width * scrollView.zoomScale,
	            height: bounds.height * scrollView.zoomScale
	        )
	        hostingController.view.center = CGPoint(
	            x: scrollView.contentSize.width * 0.5,
	            y: scrollView.contentSize.height * 0.5
	        )
	        scrollView.contentOffset = clampedContentOffset(oldOffset)
	    }

	    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
	        CGPoint(
	            x: min(max(offset.x, 0), max(scrollView.contentSize.width - bounds.width, 0)),
	            y: min(max(offset.y, 0), max(scrollView.contentSize.height - bounds.height, 0))
	        )
	    }

	    private func updateContentInsets() {
        let contentSize = scrollView.contentSize
        let insetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let insetY = max((bounds.height - contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func updateInteractionState() {
        let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        scrollView.panGestureRecognizer.isEnabled = isZoomed
        hostingController.view.isUserInteractionEnabled = !isZoomed
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration.doubleTapEnabled, recognizer.state == .ended else { return }
        ReaderZoomTapSuppressor.suppressTap()
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            resetZoom(animated: true)
            return
        }

        zoom(to: configuration.normalizedDoubleTapScale, at: recognizer.location(in: hostingController.view), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard configuration.longPressEnabled else { return }
        switch recognizer.state {
        case .began:
            ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                longPressStartedZoom = false
                return
            }
            longPressStartedZoom = true
            zoom(to: configuration.normalizedLongPressScale, at: recognizer.location(in: hostingController.view), animated: true)
        case .changed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            }
        case .ended, .cancelled, .failed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap()
                resetZoom(animated: true)
            }
            longPressStartedZoom = false
        default:
            break
        }
    }

    private func zoom(to multiplier: CGFloat, at location: CGPoint, animated: Bool) {
        let targetScale = min(max(scrollView.minimumZoomScale * multiplier, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: location.x - size.width * 0.5,
            y: location.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

struct ReaderPhotoViewImage: UIViewRepresentable {
    let image: UIImage
    let imageID: String
    let configuration: ReaderZoomConfiguration
    let dimsImage: Bool

    func makeUIView(context: Context) -> ReaderPhotoZoomView {
        ReaderPhotoZoomView()
    }

    func updateUIView(_ uiView: ReaderPhotoZoomView, context: Context) {
        uiView.update(image: image, imageID: imageID, configuration: configuration, dimsImage: dimsImage)
    }

    static func dismantleUIView(_ uiView: ReaderPhotoZoomView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

final class ReaderPhotoZoomView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var imageID = ""
    private var dimsImage = false
    private var configuration = ReaderZoomConfiguration(
        pinchEnabled: true,
        doubleTapEnabled: true,
        doubleTapScale: 1.75,
        longPressEnabled: true,
        longPressScale: 1.75
    )
    private var longPressStartedZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(image: UIImage, imageID: String, configuration: ReaderZoomConfiguration, dimsImage: Bool) {
        self.configuration = configuration
        self.dimsImage = dimsImage
        let didChangeImage = self.imageID != imageID
        self.imageID = imageID
        if didChangeImage {
            resetZoom(animated: false)
        }
        if imageView.image !== image {
            imageView.image = image
        }
        imageView.alpha = dimsImage ? 0.8 : 1
        configureGestures()
        configureZoomLimits()
        if didChangeImage {
            setNeedsLayout()
        }
    }

    func prepareForReuse() {
        resetZoom(animated: false)
        imageID = ""
        dimsImage = false
        imageView.alpha = 1
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        scrollView.frame = bounds
        layoutImageView(resetZoomIfNeeded: scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
        updatePanState()
    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.isEnabled = false

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        addSubview(scrollView)
        scrollView.addSubview(imageView)
        configureGestures()
        configureZoomLimits()
    }

    private func configureGestures() {
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchEnabled
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.doubleTapZoom" }) != true {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.name = "reader.doubleTapZoom"
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        if scrollView.gestureRecognizers?.contains(where: { $0.name == "reader.longPressZoom" }) != true {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = 0.30
            recognizer.allowableMovement = 1
            recognizer.name = "reader.longPressZoom"
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        scrollView.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "reader.doubleTapZoom" {
                recognizer.isEnabled = configuration.doubleTapEnabled
            } else if recognizer.name == "reader.longPressZoom" {
                recognizer.isEnabled = configuration.longPressEnabled
            }
        }
    }

    private func configureZoomLimits() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(2.5, configuration.normalizedDoubleTapScale, configuration.normalizedLongPressScale)
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
        updatePanState()
    }

    private func resetZoom(animated: Bool) {
        longPressStartedZoom = false
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        scrollView.contentOffset = .zero
        updatePanState()
    }

    private func layoutImageView(resetZoomIfNeeded: Bool) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = bounds
            scrollView.contentSize = bounds.size
            return
        }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        if resetZoomIfNeeded {
            scrollView.zoomScale = scrollView.minimumZoomScale
            imageView.bounds = CGRect(origin: .zero, size: fittedSize)
            scrollView.contentSize = fittedSize
        }
        centerImageView()
    }

    private func centerImageView() {
        let contentSize = scrollView.contentSize
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(
            x: contentSize.width * 0.5 + offsetX,
            y: contentSize.height * 0.5 + offsetY
        )
    }

    private func updatePanState() {
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard configuration.doubleTapEnabled, recognizer.state == .ended else { return }
        ReaderZoomTapSuppressor.suppressTap()
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        zoom(to: configuration.normalizedDoubleTapScale, at: recognizer.location(in: imageView), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard configuration.longPressEnabled else { return }
        switch recognizer.state {
        case .began:
            ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                longPressStartedZoom = false
                return
            }
            longPressStartedZoom = true
            zoom(to: configuration.normalizedLongPressScale, at: recognizer.location(in: imageView), animated: true)
        case .changed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap(for: 0.5)
            }
        case .ended, .cancelled, .failed:
            if longPressStartedZoom {
                ReaderZoomTapSuppressor.suppressTap()
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            }
            longPressStartedZoom = false
        default:
            break
        }
    }

    private func zoom(to multiplier: CGFloat, at imageLocation: CGPoint, animated: Bool) {
        let targetScale = min(max(scrollView.minimumZoomScale * multiplier, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: imageLocation.x - size.width * 0.5,
            y: imageLocation.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: zoomRect, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
#else
struct ReaderPhotoViewImage: View {
    let image: PicaXPlatformImage
    let imageID: String
    let configuration: ReaderZoomConfiguration
    let dimsImage: Bool

    var body: some View {
        Image(picaxImage: image)
            .resizable()
            .scaledToFit()
            .readerImageBrightnessReduction(dimsImage)
            .background(Color.black)
    }
}
#endif

func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}

struct ReaderDecodedImage: @unchecked Sendable {
    let image: PicaXPlatformImage

    var aspectRatio: Double {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1.4 }
        return Double(size.height / size.width)
    }
}

struct ReaderHistoryRecordSnapshot: Equatable {
    let item: ComicListItem
    let chapterIndex: Int
    let pageIndex: Int
    let totalPages: Int
    let totalChapters: Int
}

struct ReaderProgressSelectionContext: Identifiable, Equatable {
    let id = UUID()
    let chapterIndex: Int
    let chapterTitle: String
    let pageIndex: Int
    let pageCount: Int
}

struct ReaderProgressJumpRequest: Equatable {
    let id = UUID()
    let chapterIndex: Int
    let pageIndex: Int
}

enum ReaderImageMemoryCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, PicaXPlatformImage> = {
        let cache = NSCache<NSString, PicaXPlatformImage>()
        cache.countLimit = 18
        cache.totalCostLimit = 112 * 1024 * 1024
        return cache
    }()

    nonisolated static func image(for key: String) -> ReaderDecodedImage? {
        guard let image = cache.object(forKey: key as NSString) else {
            return nil
        }
        return ReaderDecodedImage(image: image)
    }

    nonisolated static func store(_ decodedImage: ReaderDecodedImage, key: String) {
        cache.setObject(decodedImage.image, forKey: key as NSString, cost: decodedImage.image.picaxEstimatedMemoryCost)
    }
}

final class ReaderImageAspectRatioCache: @unchecked Sendable {
    static let shared = ReaderImageAspectRatioCache()

    private let lock = NSLock()
    private var aspectRatios: [String: Double] = [:]

    private init() {}

    func aspectRatio(for key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return aspectRatios[key]
    }

    func store(_ aspectRatio: Double, for key: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        aspectRatios[key] = aspectRatio
        if aspectRatios.count > 800 {
            aspectRatios.removeValue(forKey: aspectRatios.keys.first ?? key)
        }
    }
}

enum ReaderImageDecoder {
    nonisolated static func image(
        url: URL,
        targetPixelWidth: Int?,
        decodePriority: TaskPriority = .userInitiated,
        onAspectRatioResolved: (@MainActor (Double) -> Void)? = nil
    ) async throws -> ReaderDecodedImage {
        let usesMemoryCache = url.picaxLocalFileURL == nil
        let cacheKey = cacheKey(url: url, targetPixelWidth: targetPixelWidth)
        if usesMemoryCache, let cached = ReaderImageMemoryCache.image(for: cacheKey) {
            return cached
        }

        var data = try await ImageCacheService.data(for: url)
        guard !Task.isCancelled else { throw CancellationError() }
        if let aspectRatio = encodedAspectRatio(data: data) {
            await onAspectRatioResolved?(aspectRatio)
        }
        let decoded: ReaderDecodedImage
        do {
            decoded = try await decode(data: data, url: url, targetPixelWidth: targetPixelWidth, priority: decodePriority)
        } catch {
            ImageCacheService.removeCachedImageData(for: url)
            data = try await ImageCacheService.data(for: url, storesInCache: false)
            guard !Task.isCancelled else { throw CancellationError() }
            if let aspectRatio = encodedAspectRatio(data: data) {
                await onAspectRatioResolved?(aspectRatio)
            }
            decoded = try await decode(data: data, url: url, targetPixelWidth: targetPixelWidth, priority: decodePriority)
        }
        ImageCacheService.storeDecodedImageData(data, for: url)
        if usesMemoryCache {
            ReaderImageMemoryCache.store(decoded, key: cacheKey)
        }
        return decoded
    }

    nonisolated static func preload(urlStrings: [String], targetPixelWidth: Int?) async {
        for urlString in urlStrings {
            guard !Task.isCancelled,
                  let url = URL.picaxResolved(from: urlString),
                  url.picaxLocalFileURL == nil,
                  ReaderImageMemoryCache.image(for: cacheKey(url: url, targetPixelWidth: targetPixelWidth)) == nil else {
                continue
            }

            _ = try? await image(url: url, targetPixelWidth: targetPixelWidth, decodePriority: .utility)
        }
    }

    private nonisolated static func decode(data: Data, url: URL, targetPixelWidth: Int?, priority: TaskPriority) async throws -> ReaderDecodedImage {
        try await Task.detached(priority: priority) {
            if Task.isCancelled {
                throw CancellationError()
            }

            let image = JmImageScrambler.decodedImage(
                data: data,
                url: url,
                targetPixelWidth: targetPixelWidth
            ) ?? downsampledImage(data: data, targetPixelWidth: targetPixelWidth) ?? PicaXPlatformImage.picaxImage(data: data)

            guard let image else {
                throw URLError(.cannotDecodeContentData)
            }
            return ReaderDecodedImage(image: image)
        }.value
    }

    nonisolated static func downsampledImage(data: Data, targetPixelWidth: Int?) -> PicaXPlatformImage? {
        guard let targetPixelWidth,
              targetPixelWidth > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let sourceHeightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              sourceWidthNumber.doubleValue > 0,
              sourceHeightNumber.doubleValue > 0 else {
            return nil
        }

        let sourceWidth = CGFloat(sourceWidthNumber.doubleValue)
        let sourceHeight = CGFloat(sourceHeightNumber.doubleValue)
        let outputWidth = min(CGFloat(targetPixelWidth), sourceWidth)
        let scale = outputWidth / sourceWidth
        let maxPixelSize = max(Int((sourceHeight * scale).rounded(.up)), Int(outputWidth.rounded(.up)), 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return PicaXPlatformImage.picaxImage(cgImage: cgImage)
    }

    private nonisolated static func encodedAspectRatio(data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              widthNumber.doubleValue > 0,
              heightNumber.doubleValue > 0 else {
            return nil
        }
        let aspectRatio = heightNumber.doubleValue / widthNumber.doubleValue
        return aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : nil
    }

    private nonisolated static func cacheKey(url: URL, targetPixelWidth: Int?) -> String {
        "\(url.absoluteString)#\(targetPixelWidth ?? 0)"
    }
}

enum JmImageScrambler {
    private nonisolated static let scrambleID = 220_980

    nonisolated static func decodedImage(data: Data, url: URL, targetPixelWidth: Int?) -> PicaXPlatformImage? {
        guard let info = imageInfo(from: url),
              let segmentCount = segmentCount(epsID: info.epsID, pictureName: info.pictureName),
              segmentCount > 1,
              let cgImage = originalCGImage(data: data) else {
            return nil
        }

        guard let rendered = reorderedImage(cgImage: cgImage, segmentCount: segmentCount) else {
            return PicaXPlatformImage.picaxImage(cgImage: cgImage)
        }
        let finalImage = scaledImageIfNeeded(cgImage: rendered, targetPixelWidth: targetPixelWidth) ?? rendered
        return PicaXPlatformImage.picaxImage(cgImage: finalImage)
    }

    private nonisolated static func imageInfo(from url: URL) -> (epsID: Int, pictureName: String)? {
        let components = url.pathComponents
        guard let photosIndex = components.lastIndex(of: "photos"),
              components.indices.contains(photosIndex + 2),
              let epsID = Int(components[photosIndex + 1]) else {
            return nil
        }

        let pictureName = (components[photosIndex + 2] as NSString).deletingPathExtension
        guard !pictureName.isEmpty else { return nil }
        return (epsID, pictureName)
    }

    private nonisolated static func segmentCount(epsID: Int, pictureName: String) -> Int? {
        if epsID < scrambleID {
            return 0
        }
        if epsID < 268_850 {
            return 10
        }

        let hashInput = "\(epsID)\(pictureName)"
        let digest = Insecure.MD5.hash(data: Data(hashInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let last = digest.utf8.last else { return nil }

        let divisor = epsID > 421_926 ? 8 : 10
        return Int(last % UInt8(divisor)) * 2 + 2
    }

    private nonisolated static func originalCGImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private nonisolated static func reorderedImage(cgImage: CGImage, segmentCount: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let blockHeight = height / segmentCount
        let remainder = height % segmentCount
        guard width > 0, height > 0, blockHeight > 0 else { return cgImage }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = width * 4
        var sourcePixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let didDrawSource = sourcePixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard didDrawSource else { return nil }

        var destinationPixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        sourcePixels.withUnsafeBytes { sourceBuffer in
            destinationPixels.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBase = sourceBuffer.baseAddress,
                      let destinationBase = destinationBuffer.baseAddress else {
                    return
                }

                var destinationY = 0
                for index in stride(from: segmentCount - 1, through: 0, by: -1) {
                    let sourceY = index * blockHeight
                    let currentHeight = blockHeight + (index == segmentCount - 1 ? remainder : 0)

                    for row in 0..<currentHeight {
                        let sourceOffset = (sourceY + row) * bytesPerRow
                        let destinationOffset = (destinationY + row) * bytesPerRow
                        destinationBase
                            .advanced(by: destinationOffset)
                            .copyMemory(from: sourceBase.advanced(by: sourceOffset), byteCount: bytesPerRow)
                    }

                    destinationY += currentHeight
                }
            }
        }

        let data = Data(destinationPixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private nonisolated static func scaledImageIfNeeded(cgImage: CGImage, targetPixelWidth: Int?) -> CGImage? {
        guard let targetPixelWidth,
              targetPixelWidth > 0,
              cgImage.width > targetPixelWidth,
              cgImage.width > 0,
              cgImage.height > 0 else {
            return cgImage
        }

        let scale = CGFloat(targetPixelWidth) / CGFloat(cgImage.width)
        let targetHeight = max(Int((CGFloat(cgImage.height) * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetPixelWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetPixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(targetPixelWidth), height: CGFloat(targetHeight)))
        return context.makeImage()
    }
}

enum ReaderImageLoadState {
    case loading
    case loaded(PicaXPlatformImage)
    case failed
}

struct ReaderImagePlaceholder: View {
    var height: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
            ProgressView()
                .tint(.white.opacity(0.72))
        }
        .frame(height: height ?? 280)
        .padding(.horizontal, 10)
    }
}

struct ReaderImageFailure: View {
    var height: CGFloat? = nil
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
            Text("图片加载失败")
                .font(.footnote)
            Button {
                retry()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .frame(height: height ?? 240)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }
}

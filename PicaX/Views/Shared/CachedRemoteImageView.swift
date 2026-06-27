import ImageIO
import SwiftUI

struct CachedRemoteImageView: View {
    let url: URL?
    let accentColor: Color
    var contentMode: ContentMode = .fill
    var storesInCache = true
    var maxPixelSize: Int? = nil
    var placeholderSystemImage = "photo"

    @State private var loadState: CachedRemoteImageLoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                placeholder
            case .loaded(let image):
                Image(picaxImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failed:
                placeholder
            }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(maxPixelSize ?? 0)-\(storesInCache)") {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            loadState = .failed
            return
        }

        if let cached = CachedRemoteImageDecoder.cachedImage(
            url: url,
            storesInCache: storesInCache,
            maxPixelSize: maxPixelSize
        ) {
            loadState = .loaded(cached.image)
            return
        }

        loadState = .loading
        do {
            let decodedImage = try await CachedRemoteImageDecoder.image(
                url: url,
                storesInCache: storesInCache,
                maxPixelSize: maxPixelSize
            )
            guard !Task.isCancelled else { return }
            loadState = .loaded(decodedImage.image)
        } catch {
            loadState = .failed
        }
    }

    private var placeholder: some View {
        ZStack {
            accentColor.opacity(0.12)
            Image(systemName: placeholderSystemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accentColor)
        }
    }
}

private enum CachedRemoteImageLoadState {
    case loading
    case loaded(PicaXPlatformImage)
    case failed
}

private struct CachedDecodedRemoteImage: @unchecked Sendable {
    let image: PicaXPlatformImage
}

private enum CachedRemoteImageMemoryCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, PicaXPlatformImage> = {
        let cache = NSCache<NSString, PicaXPlatformImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    nonisolated static func image(for key: String) -> CachedDecodedRemoteImage? {
        guard let image = cache.object(forKey: key as NSString) else {
            return nil
        }
        return CachedDecodedRemoteImage(image: image)
    }

    nonisolated static func store(_ decodedImage: CachedDecodedRemoteImage, key: String) {
        cache.setObject(decodedImage.image, forKey: key as NSString, cost: decodedImage.image.picaxEstimatedMemoryCost)
    }
}

private enum CachedRemoteImageDecoder {
    nonisolated static func cachedImage(url: URL, storesInCache: Bool, maxPixelSize: Int?) -> CachedDecodedRemoteImage? {
        CachedRemoteImageMemoryCache.image(for: cacheKey(url: url, storesInCache: storesInCache, maxPixelSize: maxPixelSize))
    }

    nonisolated static func image(url: URL, storesInCache: Bool, maxPixelSize: Int?) async throws -> CachedDecodedRemoteImage {
        let cacheKey = cacheKey(url: url, storesInCache: storesInCache, maxPixelSize: maxPixelSize)
        if let cached = CachedRemoteImageMemoryCache.image(for: cacheKey) {
            return cached
        }

        let data = try await ImageCacheService.data(for: url, storesInCache: storesInCache)
        guard !Task.isCancelled else { throw CancellationError() }
        let decoded = try await decode(data: data, maxPixelSize: maxPixelSize)
        CachedRemoteImageMemoryCache.store(decoded, key: cacheKey)
        return decoded
    }

    private nonisolated static func decode(data: Data, maxPixelSize: Int?) async throws -> CachedDecodedRemoteImage {
        try await Task.detached(priority: .utility) {
            let image = downsampledImage(data: data, maxPixelSize: maxPixelSize) ?? PicaXPlatformImage.picaxImage(data: data)
            guard let image else {
                throw URLError(.cannotDecodeContentData)
            }
            return CachedDecodedRemoteImage(image: image)
        }.value
    }

    private nonisolated static func downsampledImage(data: Data, maxPixelSize: Int?) -> PicaXPlatformImage? {
        guard let maxPixelSize,
              maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

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

    private nonisolated static func cacheKey(url: URL, storesInCache: Bool, maxPixelSize: Int?) -> String {
        "\(url.absoluteString)#\(storesInCache ? "cached" : "fresh")#\(maxPixelSize ?? 0)"
    }
}

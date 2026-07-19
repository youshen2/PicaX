import Foundation
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

enum CoverColorSampler {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CachedCoverColor> = {
        let cache = NSCache<NSString, CachedCoverColor>()
        cache.countLimit = 256
        return cache
    }()

    nonisolated static func averageColor(url: URL?) async -> Color? {
        guard let url else { return nil }
        let key = url.absoluteString as NSString
        if let cachedColor = cache.object(forKey: key) {
            return color(from: cachedColor)
        }

        do {
            let data = try await ImageCacheService.data(for: url)
            guard let sample = await sampleComponents(data: data) else {
                return nil
            }
            let sampledColor = boostedAccentComponents(from: sample)
            cache.setObject(sampledColor, forKey: key)
            return color(from: sampledColor)
        } catch {
            return nil
        }
    }

    private nonisolated static func sampleComponents(data: Data) async -> CoverRGBSample? {
        await Task.detached(priority: .utility) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 48
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return nil
            }

            let width = image.width
            let height = image.height
            let bytesPerRow = width * 4
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var weight = 0.0
            for pixelIndex in 0..<(width * height) {
                if pixelIndex.isMultiple(of: 256), Task.isCancelled {
                    return nil
                }
                let offset = pixelIndex * 4
                let alpha = Double(bytes[offset + 3]) / 255.0
                guard alpha > 0.05 else { continue }
                red += Double(bytes[offset])
                green += Double(bytes[offset + 1])
                blue += Double(bytes[offset + 2])
                weight += alpha
            }

            guard weight > 0 else { return nil }
            return CoverRGBSample(
                red: min(max(red / weight / 255.0, 0), 1),
                green: min(max(green / weight / 255.0, 0), 1),
                blue: min(max(blue / weight / 255.0, 0), 1)
            )
        }.value
    }

    private nonisolated static func boostedAccentComponents(from sample: CoverRGBSample) -> CachedCoverColor {
        let maximum = max(sample.red, sample.green, sample.blue)
        let minimum = min(sample.red, sample.green, sample.blue)
        let delta = maximum - minimum

        guard delta > 0 else {
            return CachedCoverColor(hue: 0, saturation: 0, brightness: maximum)
        }

        let rawHue: Double
        if maximum == sample.red {
            rawHue = ((sample.green - sample.blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == sample.green {
            rawHue = ((sample.blue - sample.red) / delta) + 2
        } else {
            rawHue = ((sample.red - sample.green) / delta) + 4
        }

        let hue = rawHue < 0 ? (rawHue / 6) + 1 : rawHue / 6
        let saturation = maximum == 0 ? 0 : delta / maximum
        return CachedCoverColor(
            hue: hue,
            saturation: min(max(saturation * 1.85, 0.48), 0.96),
            brightness: min(max(maximum * 1.16, 0.68), 0.88)
        )
    }

    private nonisolated static func color(from cachedColor: CachedCoverColor) -> Color {
        Color(
            hue: cachedColor.hue,
            saturation: cachedColor.saturation,
            brightness: cachedColor.brightness
        )
    }
}

private struct CoverRGBSample: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

private final class CachedCoverColor: NSObject, @unchecked Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    nonisolated init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
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
        guard usesMemoryCache(url: url, storesInCache: storesInCache) else { return nil }
        return CachedRemoteImageMemoryCache.image(for: cacheKey(url: url, storesInCache: storesInCache, maxPixelSize: maxPixelSize))
    }

    nonisolated static func image(url: URL, storesInCache: Bool, maxPixelSize: Int?) async throws -> CachedDecodedRemoteImage {
        let usesMemoryCache = usesMemoryCache(url: url, storesInCache: storesInCache)
        let cacheKey = cacheKey(url: url, storesInCache: storesInCache, maxPixelSize: maxPixelSize)
        if usesMemoryCache, let cached = CachedRemoteImageMemoryCache.image(for: cacheKey) {
            return cached
        }

        var data = try await ImageCacheService.data(for: url, storesInCache: storesInCache)
        guard !Task.isCancelled else { throw CancellationError() }
        let decoded: CachedDecodedRemoteImage
        do {
            decoded = try await decode(data: data, maxPixelSize: maxPixelSize)
        } catch {
            guard storesInCache else { throw error }
            ImageCacheService.removeCachedImageData(for: url)
            data = try await ImageCacheService.data(for: url, storesInCache: false)
            guard !Task.isCancelled else { throw CancellationError() }
            decoded = try await decode(data: data, maxPixelSize: maxPixelSize)
        }
        if storesInCache {
            ImageCacheService.storeDecodedImageData(data, for: url)
        }
        if usesMemoryCache {
            CachedRemoteImageMemoryCache.store(decoded, key: cacheKey)
        }
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

    private nonisolated static func usesMemoryCache(url: URL, storesInCache: Bool) -> Bool {
        storesInCache && url.picaxLocalFileURL == nil
    }
}

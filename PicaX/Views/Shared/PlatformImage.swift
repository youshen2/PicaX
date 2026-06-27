import SwiftUI

#if os(iOS)
import UIKit

typealias PicaXPlatformImage = UIImage
#elseif os(macOS)
import AppKit

typealias PicaXPlatformImage = NSImage
#endif

extension Image {
    init(picaxImage image: PicaXPlatformImage) {
        #if os(iOS)
        self.init(uiImage: image)
        #elseif os(macOS)
        self.init(nsImage: image)
        #endif
    }
}

extension PicaXPlatformImage {
    nonisolated static func picaxImage(data: Data) -> PicaXPlatformImage? {
        #if os(iOS)
        UIImage(data: data)
        #elseif os(macOS)
        NSImage(data: data)
        #endif
    }

    nonisolated static func picaxImage(cgImage: CGImage) -> PicaXPlatformImage {
        #if os(iOS)
        UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        #elseif os(macOS)
        NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        #endif
    }

    nonisolated var picaxCGImage: CGImage? {
        #if os(iOS)
        cgImage
        #elseif os(macOS)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    nonisolated var picaxEstimatedMemoryCost: Int {
        guard let cgImage = picaxCGImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

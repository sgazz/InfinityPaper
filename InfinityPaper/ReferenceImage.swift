import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ReferenceImage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let imageData: Data
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var opacity: CGFloat = 0.5
    var isVisible = true
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    func validate() throws {
        let limit = CanvasGeometry.coordinateLimit
        guard [x, y, width, height, opacity].allSatisfy(\.isFinite), width > 0, height > 0,
              abs(x) <= limit, abs(y) <= limit, abs(x + width) <= limit, abs(y + height) <= limit,
              (0...1).contains(opacity) else { throw CocoaError(.fileReadCorruptFile) }
        try ReferenceImageData.validate(imageData)
    }

    mutating func fit(in viewport: CGRect, imageSize: CGSize? = nil) {
        let aspect = imageSize.map { $0.width / $0.height } ?? width / height
        let size = CGSize(width: max(1, min(viewport.width * 0.75, 1_000_000)),
                          height: max(1, min(viewport.height * 0.75, 1_000_000)))
        width = min(size.width, size.height * aspect)
        height = width / aspect
        center(at: CGPoint(x: viewport.midX, y: viewport.midY))
    }

    mutating func center(at point: CGPoint) {
        let limit = CanvasGeometry.coordinateLimit
        x = min(limit - width, max(-limit, point.x - width / 2))
        y = min(limit - height, max(-limit, point.y - height / 2))
    }

    mutating func resize(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(1_000_000 / max(width, height), max(1 / min(width, height), factor))
        width *= scale; height *= scale
        self.center(at: center)
    }
}

/// Bounded, oriented PNG data; no dependency on the original file after import.
nonisolated enum ReferenceImageData {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumPixels = 2048

    static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maximumPixels).contains(w), (1...maximumPixels).contains(h),
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1] as CFDictionary) != nil else { throw CocoaError(.fileReadCorruptFile) }
    }

    static func prepare(url: URL) throws -> (Data, CGSize) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000, height <= 40_000,
              Double(width) * Double(height) <= 100_000_000 else { throw CocoaError(.fileReadTooLarge) }
        for size in [maximumPixels, 1024] {
            let image = try thumbnail(source: source, size: size)
            let data = try png(image)
            if data.count <= maximumBytes { return (data, CGSize(width: image.width, height: image.height)) }
        }
        throw CocoaError(.fileReadTooLarge)
    }

    static func preview(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = try? thumbnail(source: source, size: 256) else { return nil }
        return try? png(image)
    }

    private static func thumbnail(source: CGImageSource, size: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

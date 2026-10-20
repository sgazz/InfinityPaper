import CoreGraphics

/// Coordinate and bitmap sizing rules shared by on-screen drawing and export.
nonisolated enum CanvasGeometry {
    static let coordinateLimit: CGFloat = 10_000_000
    static let minimumZoom: CGFloat = 0.00001

    static func zoomChangeThreshold(for scale: CGFloat) -> CGFloat {
        max(1e-12, scale * 0.0001)
    }

    static func viewportTransform(offset: CGPoint, zoom: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom,
                          tx: -offset.x * zoom, ty: -offset.y * zoom)
    }

    static func exportScale(size: CGSize, requested: CGFloat, maxPixelSide: CGFloat = 8192) -> CGFloat {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return requested }
        return min(requested, maxPixelSide / longestSide)
    }
}

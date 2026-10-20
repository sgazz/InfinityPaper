import CoreGraphics

/// Pure world/view geometry. UIKit decides when to animate or redraw these changes.
struct CanvasViewport: Equatable {
    var offset: CGPoint = .zero
    var zoom: CGFloat = 1
    private let normalMinimumZoom: CGFloat = 0.5
    private let maximumZoom: CGFloat = 2.5
    private let coordinateLimit = CanvasGeometry.coordinateLimit

    func worldPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(coordinateLimit, max(-coordinateLimit, point.x / zoom + offset.x)),
                y: min(coordinateLimit, max(-coordinateLimit, point.y / zoom + offset.y)))
    }

    func worldRect(for size: CGSize) -> CGRect {
        CGRect(origin: offset, size: CGSize(width: size.width / zoom, height: size.height / zoom))
    }

    mutating func clamp() {
        offset.x = max(-coordinateLimit, min(offset.x, coordinateLimit))
        offset.y = max(-coordinateLimit, min(offset.y, coordinateLimit))
    }

    mutating func pan(by translation: CGPoint) {
        offset.x -= translation.x / zoom
        offset.y -= translation.y / zoom
        clamp()
    }

    @discardableResult
    mutating func zoom(by factor: CGFloat, at focalPoint: CGPoint) -> Bool {
        let scale = min(max(min(normalMinimumZoom, zoom), zoom * factor), maximumZoom)
        guard abs(scale - zoom) > CanvasGeometry.zoomChangeThreshold(for: zoom) else { return false }
        let world = CGPoint(x: focalPoint.x / zoom + offset.x, y: focalPoint.y / zoom + offset.y)
        zoom = scale
        offset = CGPoint(x: world.x - focalPoint.x / scale, y: world.y - focalPoint.y / scale)
        clamp()
        return true
    }

    mutating func center(on rect: CGRect?, in size: CGSize) {
        if let rect {
            offset = CGPoint(x: rect.midX - size.width / zoom * 0.5,
                             y: rect.midY - size.height / zoom * 0.5)
        } else { offset = .zero }
        clamp()
    }

    mutating func fit(_ rect: CGRect, in size: CGSize, padding: CGFloat = 24) {
        let target = min((size.width - 2 * padding) / rect.width, (size.height - 2 * padding) / rect.height)
        zoom = min(max(CanvasGeometry.minimumZoom, target), maximumZoom)
        center(on: rect, in: size)
    }
}

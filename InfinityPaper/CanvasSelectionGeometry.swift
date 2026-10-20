import CoreGraphics

nonisolated enum CanvasTool: String {
    case pen, eraser, lasso
}

nonisolated enum CanvasSelectionGeometry {
    static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var a = polygon[polygon.count - 1]
        for b in polygon {
            if CanvasStrokeHitTesting.intersects(points: [a, b], from: point, to: point, radius: 1e-7) { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            a = b
        }
        return inside
    }

    /// Select whole strokes touching or crossing the loop, including dots and segments crossing the boundary.
    static func intersects(points: [CGPoint], polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        if points.contains(where: { contains($0, polygon: polygon) }) { return true }
        var a = polygon[polygon.count - 1]
        for b in polygon {
            if CanvasStrokeHitTesting.intersects(points: points, from: a, to: b, radius: 0) { return true }
            a = b
        }
        return false
    }

    static func clampedTranslation(_ proposed: CGPoint, bounds: CGRect) -> CGPoint {
        guard proposed.x.isFinite, proposed.y.isFinite else { return .zero }
        let limit = CanvasGeometry.coordinateLimit
        return CGPoint(x: min(limit - bounds.maxX, max(-limit - bounds.minX, proposed.x)),
                       y: min(limit - bounds.maxY, max(-limit - bounds.minY, proposed.y)))
    }
}

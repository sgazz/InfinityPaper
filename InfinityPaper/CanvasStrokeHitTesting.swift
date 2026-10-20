import CoreGraphics

nonisolated enum CanvasStrokeHitTesting {
    static func intersects(points: [CGPoint], from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 { return distanceSquared(first, to: start, end) <= radius * radius }
        for (a, b) in zip(points, points.dropFirst()) {
            if segmentsIntersect(a, b, start, end) { return true }
            let distance = min(distanceSquared(a, to: start, end), distanceSquared(b, to: start, end),
                               distanceSquared(start, to: a, b), distanceSquared(end, to: a, b))
            if distance <= radius * radius { return true }
        }
        return false
    }

    private static func distanceSquared(_ point: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
        let x = point.x - a.x - t * dx, y = point.y - a.y - t * dy
        return x * x + y * y
    }

    private static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let x = cross(a, b, c), y = cross(a, b, d), z = cross(c, d, a), w = cross(c, d, b)
        // Collinear/degenerate segments are handled by endpoint distances instead.
        return ((x < 0 && y > 0) || (x > 0 && y < 0)) && ((z < 0 && w > 0) || (z > 0 && w < 0))
    }
}

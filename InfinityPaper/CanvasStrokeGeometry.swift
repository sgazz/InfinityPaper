import CoreGraphics

/// Shared centerline used for both rendering and eraser hit testing.
nonisolated enum CanvasStrokeGeometry {
    /// Smooths points using a simple averaging filter.
    /// - Parameters:
    ///   - points: The points to smooth
    ///   - passes: Number of smoothing passes
    /// - Returns: Smoothed points
    static func smoothedPoints(for points: [CGPoint], passes: Int) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var current = points
        for _ in 0..<passes {
            var next = current
            for i in 1..<(current.count - 1) {
                let prev = current[i - 1]
                let curr = current[i]
                let nextPoint = current[i + 1]
                next[i] = CGPoint(
                    x: prev.x * 0.25 + curr.x * 0.5 + nextPoint.x * 0.25,
                    y: prev.y * 0.25 + curr.y * 0.5 + nextPoint.y * 0.25
                )
            }
            current = next
        }
        if current.count >= 3 {
            let w = 0.08
            var eased = current
            eased[0] = CGPoint(
                x: eased[0].x * (1 - w) + eased[1].x * w,
                y: eased[0].y * (1 - w) + eased[1].y * w
            )
            let li = eased.count - 1
            eased[li] = CGPoint(
                x: eased[li].x * (1 - w) + eased[li - 1].x * w,
                y: eased[li].y * (1 - w) + eased[li - 1].y * w
            )
            return eased
        }
        return current
    }

}

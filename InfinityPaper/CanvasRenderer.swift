//
//  CanvasRenderer.swift
//  InfinityPaper
//
//  Provides rendering utilities for drawing strokes and noise texture.
//

import UIKit

/// Stroke structure for rendering.
struct RenderStroke {
    var points: [CGPoint]
    var times: [TimeInterval]
    var color: UIColor
    var lineWidth: CGFloat
    var widthScales: [CGFloat] = []
    var lineStyle: CanvasLineStyle = .solid
}

struct PreparedRenderStrokeSegment {
    var start: CGPoint
    var end: CGPoint
    var width: CGFloat
}

struct PreparedRenderStroke {
    var color: UIColor
    var segments: [PreparedRenderStrokeSegment]
}

/// Provides rendering utilities for canvas drawing operations.
final class CanvasRenderer {
    private enum Layout {
        /// Slightly higher than before so line width eases with speed changes instead of ticking.
        static let strokeSmoothingAlpha: CGFloat = 0.2
        static let noiseTileSize: CGFloat = 96
    }
    
    /// Draws a stroke in world coordinates (no transform).
    /// - Parameters:
    ///   - stroke: The stroke to draw
    ///   - context: The graphics context
    static func drawStrokeWorld(
        _ stroke: RenderStroke,
        in context: CGContext
    ) {
        guard let prepared = prepareStroke(stroke) else { return }
        drawPreparedStrokeWorld(prepared, in: context)
    }

    static func prepareStroke(_ stroke: RenderStroke) -> PreparedRenderStroke? {
        if let point = stroke.points.first, stroke.points.count == 1 {
            return PreparedRenderStroke(color: stroke.color, segments: [
                PreparedRenderStrokeSegment(start: point, end: CGPoint(x: point.x + 0.01, y: point.y), width: stroke.lineWidth * PencilStrokeWidth.scale(at: 0, in: stroke.widthScales))
            ])
        }
        guard stroke.points.count > 1 else { return nil }
        let smoothed = CanvasStrokeGeometry.smoothedPoints(for: stroke.points, passes: 2)
        guard smoothed.count > 1 else { return nil }
        let segments = patternedSegments(makeSegments(stroke, smoothedPoints: smoothed),
                                         style: stroke.lineStyle, baseWidth: stroke.lineWidth)
        guard !segments.isEmpty else { return nil }
        return PreparedRenderStroke(color: stroke.color, segments: segments)
    }

    static func drawPreparedStrokeWorld(
        _ prepared: PreparedRenderStroke,
        in context: CGContext
    ) {
        guard !prepared.segments.isEmpty else { return }
        context.setStrokeColor(prepared.color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setMiterLimit(4)
        for segment in prepared.segments {
            context.setLineWidth(segment.width)
            context.beginPath()
            context.move(to: segment.start)
            context.addLine(to: segment.end)
            context.strokePath()
        }
    }
    
    /// Builds precomputed stroke segments with smoothing, width scaling, and tail effects.
    private static func makeSegments(
        _ stroke: RenderStroke,
        smoothedPoints smoothed: [CGPoint]
    ) -> [PreparedRenderStrokeSegment] {
        guard smoothed.count > 1 else { return [] }
        
        let tailCount = min(20, max(0, smoothed.count - 1))
        let tailStart = max(0, smoothed.count - 1 - tailCount)
        let minScale: CGFloat = 0.15
        
        var filteredScale = PencilStrokeWidth.scale(at: 0, in: stroke.widthScales)
        let smoothingAlpha = Layout.strokeSmoothingAlpha
        var segments: [PreparedRenderStrokeSegment] = []
        segments.reserveCapacity(smoothed.count - 1)
        for i in 1..<smoothed.count {
            let start = smoothed[i - 1]
            let end = smoothed[i]
            let targetScale = targetWidthScale(for: stroke, index: i) * PencilStrokeWidth.scale(at: i, in: stroke.widthScales)
            filteredScale = filteredScale + (targetScale - filteredScale) * smoothingAlpha
            let width = stroke.lineWidth * filteredScale
            let tailScale: CGFloat
            if i >= tailStart && tailCount > 0 {
                let t = CGFloat(smoothed.count - 1 - i) / CGFloat(tailCount)
                let eased = t * t * (3 - 2 * t)
                tailScale = max(minScale, eased * eased)
            } else {
                tailScale = 1.0
            }
            segments.append(
                PreparedRenderStrokeSegment(
                    start: start,
                    end: end,
                    width: max(0.4, width * tailScale)
                )
            )
        }
        return segments
    }
    
    /// Calculates width scale based on drawing speed.
    /// - Parameters:
    ///   - stroke: The stroke
    ///   - index: The point index
    /// - Returns: Width scale factor (0.6 to 1.15)
    private static func targetWidthScale(for stroke: RenderStroke, index: Int) -> CGFloat {
        guard stroke.times.count > index else { return 1.0 }
        let rawDt = stroke.times[index] - stroke.times[index - 1]
        // Floor dt so two samples in the same frame do not imply absurd speed (thin spikes).
        let dt = max(1.0 / 720.0, rawDt)
        let p0 = stroke.points[index - 1]
        let p1 = stroke.points[index]
        let distance = hypot(p1.x - p0.x, p1.y - p0.y)
        let speed = distance / CGFloat(dt)
        let minSpeed: CGFloat = 38
        let maxSpeed: CGFloat = 1050
        let normalized = min(1, max(0, (speed - minSpeed) / (maxSpeed - minSpeed)))
        let thick = 1.15
        let thin = 0.6
        return thick - (thick - thin) * normalized
    }
    
    /// Splits prepared geometry by arc length so preview, cached drawing and exports agree.
    static func patternedSegments(_ segments: [PreparedRenderStrokeSegment], style: CanvasLineStyle,
                                  baseWidth: CGFloat) -> [PreparedRenderStrokeSegment] {
        let pattern = style.dashLengths(width: baseWidth)
        guard !pattern.isEmpty else { return segments }
        var result: [PreparedRenderStrokeSegment] = []
        var phase = 0
        var remaining = pattern[0]
        for segment in segments {
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            var distance: CGFloat = 0
            while distance < length {
                let step = min(remaining, length - distance)
                if phase % 2 == 0 {
                    let start = CGPoint(x: segment.start.x + dx * distance / length,
                                        y: segment.start.y + dy * distance / length)
                    let endDistance = distance + step
                    let end = CGPoint(x: segment.start.x + dx * endDistance / length,
                                      y: segment.start.y + dy * endDistance / length)
                    result.append(PreparedRenderStrokeSegment(start: start, end: end, width: segment.width))
                }
                distance += step
                remaining -= step
                if remaining < 0.000001 {
                    phase = (phase + 1) % pattern.count
                    remaining = pattern[phase]
                }
            }
        }
        return result
    }

    /// Draws noise texture in the specified rect.
    /// - Parameters:
    ///   - context: The graphics context
    ///   - rect: The rectangle to fill with noise
    ///   - noiseTile: The cached noise tile image (will be created if nil)
    ///   - backgroundColor: Background color for noise generation
    ///   - traitCollection: Trait collection for dark mode detection
    /// - Returns: Updated noise tile (for caching)
    static func drawNoise(
        in context: CGContext,
        rect: CGRect,
        noiseTile: UIImage?,
        backgroundColor: UIColor,
        noiseProfile: PaperNoiseProfile,
        traitCollection: UITraitCollection
    ) -> UIImage? {
        let tile = noiseTile ?? makeNoiseTile(
            size: Layout.noiseTileSize,
            backgroundColor: backgroundColor,
            noiseProfile: noiseProfile,
            traitCollection: traitCollection
        )
        UIColor(patternImage: tile).setFill()
        context.fill(rect)
        return tile
    }
    
    /// Creates a noise tile image.
    /// - Parameters:
    ///   - size: Tile size
    ///   - backgroundColor: Background color
    ///   - traitCollection: Trait collection for dark mode detection
    /// - Returns: Noise tile image
    static func makeNoiseTile(
        size: CGFloat,
        backgroundColor: UIColor,
        noiseProfile: PaperNoiseProfile,
        traitCollection: UITraitCollection
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let resolvedBg = backgroundColor.resolvedColor(with: traitCollection)
        let isDark = traitCollection.userInterfaceStyle == .dark
        return renderer.image { ctx in
            // Opaque paper base so tiled pattern is seamless with the canvas fill.
            resolvedBg.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Subtle grain only: low count, alpha ~0.012–0.032 (stays under ~0.04; no visible “texture photo”).
            for _ in 0..<noiseProfile.dotCount {
                let x = CGFloat.random(in: 0..<size)
                let y = CGFloat.random(in: 0..<size)
                let alpha = CGFloat.random(in: noiseProfile.alphaMin...noiseProfile.alphaMax)
                let dotColor = isDark
                    ? UIColor(white: 1.0, alpha: alpha)
                    : UIColor(white: 0.0, alpha: alpha)
                ctx.cgContext.setFillColor(dotColor.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 0.85, height: 0.85))
            }
        }
    }
}

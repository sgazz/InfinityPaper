import OSLog
import UIKit

/// Drawing caches, invalidation and frame diagnostics; no touch or persistence behavior.
final class CanvasRenderState {
    var needsRedraw = true
    private var contentRevision: UInt64 = 1
    private var lastRenderedRevision: UInt64 = 0
    private var lastOffset: CGPoint = .zero
    private var lastZoom: CGFloat = 1
    private var noiseTile: UIImage?
    private var preparedStrokes: [UUID: PreparedRenderStroke] = [:]
#if DEBUG
    private static let logger = Logger(subsystem: "com.infinitypaper", category: "CanvasFPS")
    private var fpsWindowStart: CFTimeInterval = 0
    private var fpsFrameCount = 0
#endif

    func invalidateStrokes() { preparedStrokes.removeAll(keepingCapacity: true) }
    func invalidatePaper() { noiseTile = nil }
    func contentChanged() { contentRevision &+= 1 }

    func requiresDisplay(viewport: CanvasViewport, force: Bool = false) -> Bool {
        force || abs(viewport.offset.x - lastOffset.x) > 0.0001 || abs(viewport.offset.y - lastOffset.y) > 0.0001
            || abs(viewport.zoom - lastZoom) > CanvasGeometry.zoomChangeThreshold(for: lastZoom) || contentRevision != lastRenderedRevision
    }

    func didDraw(viewport: CanvasViewport) {
        needsRedraw = false
        lastOffset = viewport.offset
        lastZoom = viewport.zoom
        lastRenderedRevision = contentRevision
#if DEBUG
        let now = CACurrentMediaTime()
        if fpsWindowStart == 0 { fpsWindowStart = now }
        fpsFrameCount += 1
        let elapsed = now - fpsWindowStart
        if elapsed >= 1 {
            let fps = Double(fpsFrameCount) / elapsed
            Self.logger.debug("canvas fps=\(fps, format: .fixed(precision: 1))")
            fpsWindowStart = now
            fpsFrameCount = 0
        }
#endif
    }

    func drawPaper(in context: CGContext, rect: CGRect, background: UIColor,
                   surface: PaperSurface, traits: UITraitCollection) {
        noiseTile = CanvasRenderer.drawNoise(in: context, rect: rect, noiseTile: noiseTile,
                                             backgroundColor: background, noiseProfile: surface.noiseProfile,
                                             traitCollection: traits)
    }

    func drawStrokes(in context: CGContext, session: TapeCanvasSessionState,
                     currentStroke: TapeSessionStroke?, viewport: CanvasViewport,
                     size: CGSize, visibleOnly: Bool, movingIDs: Set<UUID> = [], translation: CGPoint = .zero) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let strokes = visibleOnly ? session.visibleStrokes(in: viewport.worldRect(for: size), including: movingIDs) : session.orderedStrokes
        for stroke in strokes {
            context.saveGState()
            if movingIDs.contains(stroke.id) { context.translateBy(x: translation.x, y: translation.y) }
            if let prepared = preparedStroke(for: stroke) { CanvasRenderer.drawPreparedStrokeWorld(prepared, in: context) }
            context.restoreGState()
        }
        if let stroke = currentStroke { CanvasRenderer.drawStrokeWorld(renderStroke(stroke), in: context) }
    }

    private func preparedStroke(for stroke: TapeSessionStroke) -> PreparedRenderStroke? {
        if let cached = preparedStrokes[stroke.id] { return cached }
        guard let prepared = CanvasRenderer.prepareStroke(renderStroke(stroke)) else { return nil }
        if preparedStrokes.count >= 256 { preparedStrokes.removeAll(keepingCapacity: true) }
        preparedStrokes[stroke.id] = prepared
        return prepared
    }

    private func renderStroke(_ stroke: TapeSessionStroke) -> RenderStroke {
        RenderStroke(points: stroke.points, times: stroke.times, color: stroke.color, lineWidth: stroke.lineWidth, widthScales: stroke.widthScales)
    }
}

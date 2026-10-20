import UIKit

enum CanvasSelectionRenderer {
    static func draw(_ selection: CanvasSelectionController, in context: CGContext, zoom: CGFloat) {
        guard selection.isEnabled else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.06).cgColor)
        context.setLineWidth(1.5 / zoom)
        context.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
        if let first = selection.lasso.first {
            context.beginPath()
            context.move(to: first)
            for point in selection.lasso.dropFirst() { context.addLine(to: point) }
            context.closePath()
            context.drawPath(using: .eoFillStroke)
        } else if let bounds = selection.bounds {
            let preview = bounds.offsetBy(dx: selection.translation.x, dy: selection.translation.y)
            context.fill(preview)
            context.stroke(preview)
        }
    }
}

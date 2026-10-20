import UIKit

/// Guides are anchored in world coordinates, so they follow the drawing when panning/zooming.
enum PaperPatternRenderer {
    static func draw(in context: CGContext, rect: CGRect, pattern: PaperPattern,
                     spacing: CGFloat, zoom: CGFloat, traits: UITraitCollection) {
        guard pattern != .plain, rect.width > 0, rect.height > 0 else { return }
        let step = PaperPatternLayout.visibleSpacing(spacing, zoom: zoom, extent: max(rect.width, rect.height))
        let startX = floor(rect.minX / step) * step
        let startY = floor(rect.minY / step) * step
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        let color = (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black).withAlphaComponent(0.14)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(0.6 / zoom)
        if pattern == .dots {
            let radius = 0.8 / zoom
            for x in stride(from: startX, through: rect.maxX, by: step) {
                for y in stride(from: startY, through: rect.maxY, by: step) {
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            }
        } else {
            for y in stride(from: startY, through: rect.maxY, by: step) {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            if pattern == .grid {
                for x in stride(from: startX, through: rect.maxX, by: step) {
                    context.move(to: CGPoint(x: x, y: rect.minY))
                    context.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
            }
            context.strokePath()
        }
    }
}

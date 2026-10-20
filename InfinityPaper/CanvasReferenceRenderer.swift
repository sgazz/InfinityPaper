import UIKit

final class CanvasReferenceRenderer {
    private var cachedID: UUID?
    private var image: UIImage?

    func draw(_ reference: ReferenceImage?, in context: CGContext) {
        guard let reference, reference.isVisible, reference.opacity > 0 else { return }
        if cachedID != reference.id {
            cachedID = reference.id
            image = UIImage(data: reference.imageData)
        }
        guard let image else { return }
        context.saveGState()
        defer { context.restoreGState() }
        UIGraphicsPushContext(context)
        image.draw(in: reference.rect, blendMode: .normal, alpha: reference.opacity)
        UIGraphicsPopContext()
    }
}

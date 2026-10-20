import Foundation
import CoreGraphics

nonisolated struct PencilResponse {
    let pressureEnabled: Bool
    let tiltEnabled: Bool
    let sensitivity: CGFloat

    func scale(force: CGFloat, maximumForce: CGFloat, altitude: CGFloat) -> CGFloat {
        var scale: CGFloat = 1
        if pressureEnabled, force.isFinite, maximumForce.isFinite, maximumForce > 0 {
            // UIKit defines 1 as average force. Preserve that normal width even for
            // input mechanisms reporting a constant force of 1 without pressure variation.
            let value = min(maximumForce, max(0, force))
            let response = sensitivity.isFinite ? min(1, max(0, sensitivity)) : 0.5
            scale = pow(value, 1.6 - response)
        }
        if tiltEnabled, altitude.isFinite, (0...CGFloat.pi / 2).contains(altitude) {
            scale *= 1 + 0.5 * (1 - sin(altitude))
        }
        return min(PencilStrokeWidth.scaleRange.upperBound, max(PencilStrokeWidth.scaleRange.lowerBound, scale))
    }
}

nonisolated enum PencilStrokeWidth {
    static let scaleRange: ClosedRange<CGFloat> = 0.35...2

    static func scale(at index: Int, in scales: [CGFloat]) -> CGFloat {
        scales.indices.contains(index) ? scales[index] : 1
    }

    static func maximumScale(_ scales: [CGFloat]) -> CGFloat { max(1, scales.max() ?? 1) }
    static func radius(lineWidth: CGFloat, scales: [CGFloat]) -> CGFloat { lineWidth * 0.75 * maximumScale(scales) }
}

nonisolated enum CanvasInputPolicy {
    static func pencilOnly(requested: Bool, supportsPencil: Bool) -> Bool { requested && supportsPencil }
    static func acceptsDrawing(isPencil: Bool, pencilOnly: Bool) -> Bool { isPencil || !pencilOnly }
    static func panTouchCount(pencilOnly: Bool) -> Int { pencilOnly ? 1 : 2 }
}

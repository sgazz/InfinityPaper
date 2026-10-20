import UIKit

/// Tracks the actual drawing touch, independently from fingers used for navigation.
final class CanvasInputController: NSObject, UIGestureRecognizerDelegate {
    private var activeTouch: UITouch?
    private var response = PencilResponse(pressureEnabled: true, tiltEnabled: false, sensitivity: 0.5)
    var isPencilActive: Bool { activeTouch?.type == .pencil }
    var capturesWidthProfile: Bool { isPencilActive && (response.pressureEnabled || response.tiltEnabled) }
    var pencilOnly: Bool {
        CanvasInputPolicy.pencilOnly(requested: AppSettings.defaults.bool(forKey: AppSettings.pencilOnly),
                                     supportsPencil: UIDevice.current.userInterfaceIdiom == .pad)
    }

    func configure(pan: UIPanGestureRecognizer, pinch: UIPinchGestureRecognizer, reset: UITapGestureRecognizer) {
        pan.minimumNumberOfTouches = CanvasInputPolicy.panTouchCount(pencilOnly: pencilOnly)
        for recognizer in [pan, pinch, reset] as [UIGestureRecognizer] {
            recognizer.allowedTouchTypes = [UITouch.TouchType.direct, .indirectPointer].map { NSNumber(value: $0.rawValue) }
            recognizer.requiresExclusiveTouchType = true
            recognizer.delegate = self
        }
    }

    func begin(_ touches: Set<UITouch>, event: UIEvent?) -> UITouch? {
        guard activeTouch == nil else { return nil }
        let candidate = touches.first(where: { $0.type == .pencil }) ?? touches.first
        guard let touch = candidate, CanvasInputPolicy.acceptsDrawing(isPencil: touch.type == .pencil, pencilOnly: pencilOnly) else { return nil }
        if touch.type != .pencil {
            let active = (event?.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }
            guard active.count == 1 else { return nil }
        }
        let defaults = AppSettings.defaults
        response = PencilResponse(pressureEnabled: defaults.bool(forKey: AppSettings.pencilPressure),
            tiltEnabled: defaults.bool(forKey: AppSettings.pencilTilt), sensitivity: CGFloat(defaults.double(forKey: AppSettings.pencilSensitivity)))
        activeTouch = touch
        return touch
    }

    func tracked(in touches: Set<UITouch>) -> UITouch? { touches.first { $0 === activeTouch } }
    func finish() { activeTouch = nil }

    func widthScale(for sample: UITouch) -> CGFloat {
        guard sample.type == .pencil else { return 1 }
        return response.scale(force: sample.force, maximumForce: sample.maximumPossibleForce, altitude: sample.altitudeAngle)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { !isPencilActive }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
            || (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
    }
}

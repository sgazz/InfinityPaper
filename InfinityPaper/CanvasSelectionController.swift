import Foundation
import CoreGraphics

/// Transient lasso/drag preview. Document coordinates change only when a drag is committed.
final class CanvasSelectionController {
    private let state: TapeCanvasSessionState
    private(set) var isEnabled = false
    private(set) var selectedIDs: Set<UUID> = []
    private(set) var lasso: [CGPoint] = []
    private(set) var translation: CGPoint = .zero
    var onChange: ((Bool) -> Void)?
    private var dragOrigin: CGPoint?
    private var dragBounds: CGRect?
    private var sampleDistance: CGFloat = 1
    var bounds: CGRect? { state.selectionBounds(for: selectedIDs) }

    init(state: TapeCanvasSessionState) { self.state = state }

    func setEnabled(_ enabled: Bool) {
        finishGesture()
        isEnabled = enabled
        if !enabled { clear() }
        onChange?(false)
    }

    func clear() {
        selectedIDs.removeAll()
        resetGesture()
        onChange?(false)
    }

    func begin(at point: CGPoint, zoom: CGFloat) {
        finishGesture()
        sampleDistance = 2 / zoom
        if let bounds, bounds.insetBy(dx: -8 / zoom, dy: -8 / zoom).contains(point) {
            dragOrigin = point
            dragBounds = state.selectionCoordinateBounds(for: selectedIDs)
        } else {
            selectedIDs.removeAll()
            lasso = [point]
        }
        onChange?(false)
    }

    func move(to point: CGPoint) {
        if let origin = dragOrigin, let bounds = dragBounds {
            translation = CanvasSelectionGeometry.clampedTranslation(CGPoint(x: point.x - origin.x, y: point.y - origin.y), bounds: bounds)
        } else if let last = lasso.last, hypot(point.x - last.x, point.y - last.y) >= sampleDistance {
            lasso.append(point)
            if lasso.count > 1024 {
                lasso = stride(from: 0, to: lasso.count, by: 2).map { lasso[$0] }
                lasso.append(point)
            }
        }
        onChange?(false)
    }

    func finishGesture(cancelled: Bool = false) {
        var changed = false
        if !cancelled {
            if dragOrigin != nil {
                changed = state.moveSelection(selectedIDs, by: translation)
            } else if lasso.count >= 3 {
                selectedIDs = state.strokesIntersectingLasso(lasso)
            } else if let point = lasso.first {
                let nearby = state.stroke(at: point, radius: sampleDistance * 3)
                selectedIDs = nearby.map { [$0] } ?? []
            }
        }
        resetGesture()
        onChange?(changed)
    }

    func duplicate(offset: CGPoint) {
        finishGesture()
        let copies = state.duplicateSelection(selectedIDs, offset: offset)
        guard !copies.isEmpty else { return }
        selectedIDs = copies
        onChange?(true)
    }

    func delete() {
        finishGesture()
        let changed = state.deleteSelection(selectedIDs)
        selectedIDs.removeAll()
        onChange?(changed)
    }

    private func resetGesture() {
        lasso.removeAll()
        translation = .zero
        dragOrigin = nil
        dragBounds = nil
    }
}

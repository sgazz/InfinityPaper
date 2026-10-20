import UIKit

/// Frame scheduling and inertia; the view applies deltas to its own viewport.
final class CanvasMotionController {
    var onDecelerationStep: ((CGPoint) -> Void)?
    var onAutoScrollStep: ((CGFloat) -> Void)?
    private var decelerationLink: CADisplayLink?
    private var autoScrollLink: CADisplayLink?
    private var velocity: CGPoint = .zero

    /// CADisplayLink retains its target. Keep the target's reference back to the controller weak.
    private final class Target: NSObject {
        weak var owner: CanvasMotionController?
        let autoScroll: Bool
        init(owner: CanvasMotionController, autoScroll: Bool) { self.owner = owner; self.autoScroll = autoScroll }
        @objc func fire(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link, autoScroll: autoScroll)
        }
    }

    func startDeceleration(velocity: CGPoint) {
        self.velocity = velocity
        if decelerationLink == nil { decelerationLink = makeLink(autoScroll: false) }
    }

    func stopDeceleration() {
        decelerationLink?.invalidate()
        decelerationLink = nil
        velocity = .zero
    }

    func startAutoScroll() {
        if autoScrollLink == nil { autoScrollLink = makeLink(autoScroll: true) }
    }

    func stopAutoScroll() { autoScrollLink?.invalidate(); autoScrollLink = nil }
    func stop() { stopDeceleration(); stopAutoScroll() }

    private func makeLink(autoScroll: Bool) -> CADisplayLink {
        let target = Target(owner: self, autoScroll: autoScroll)
        let link = CADisplayLink(target: target, selector: #selector(Target.fire(_:)))
        link.add(to: .main, forMode: .common)
        return link
    }

    private func tick(_ link: CADisplayLink, autoScroll: Bool) {
        let dt = CGFloat(link.duration)
        if autoScroll { onAutoScrollStep?(dt); return }
        guard hypot(velocity.x, velocity.y) >= 12 else { stopDeceleration(); return }
        onDecelerationStep?(CGPoint(x: velocity.x * dt, y: velocity.y * dt))
        let decay = pow(0.92, dt * 60)
        velocity.x *= decay
        velocity.y *= decay
    }

    deinit { decelerationLink?.invalidate(); autoScrollLink?.invalidate() }
}

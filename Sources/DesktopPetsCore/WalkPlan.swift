import CoreGraphics
import Foundation

/// Decides where the pet goes, which way it faces, how far it moves this tick, and how long it
/// rests — horizontally *and* vertically.
///
/// Stateless apart from its tuning values, so every method is directly testable. Randomness is
/// injected as a `RandomNumberGenerator` so tests can seed it.
public struct WalkPlan: Equatable {
    /// Horizontal speed in points per second.
    public var speed: Double
    /// Vertical speed while climbing, in points per second.
    ///
    /// Deliberately brisk. Nothing is drawn to explain a climb any more, so the pet is simply out
    /// of action for as long as it takes — at the old 28pt/s a typical 233pt climb held it for
    /// eight seconds. It also reads better: one 8-frame cycle at 8fps covers a second, so at
    /// 90pt/s a cycle spans 90pt of travel instead of 28pt of near-standing-still.
    public var climbSpeed: Double
    /// How far the pet keeps its centre from the screen's visible edges.
    public var edgeInset: Double
    /// Bounds on the idle pause between activities, in seconds.
    public var minPause: Double
    public var maxPause: Double
    /// A walk must cover at least this much ground to be worth starting; avoids twitchy micro-steps.
    public var minTravel: Double
    /// A climb must change height by at least this much to be worth starting.
    public var minClimb: Double

    public init(
        speed: Double = 42,
        climbSpeed: Double = 90,
        edgeInset: Double = 24,
        minPause: Double = 2.5,
        maxPause: Double = 7,
        minTravel: Double = 48,
        minClimb: Double = 90
    ) {
        self.speed = speed
        self.climbSpeed = climbSpeed
        self.edgeInset = edgeInset
        self.minTravel = minTravel
        self.minClimb = minClimb
        // Keep the ranges sane even if a config value arrives out of order.
        self.minPause = Swift.min(minPause, maxPause)
        self.maxPause = Swift.max(minPause, maxPause)
    }

    // MARK: Where the pet may be

    /// The rectangle the pet's hotspot may occupy, keeping the whole sprite inside `visibleFrame`.
    ///
    /// Each axis collapses to its midpoint when the sprite cannot fit, so callers never have to
    /// deal with an inverted range.
    public func walkableArea(in visibleFrame: CGRect, petSize: CGSize) -> CGRect {
        let horizontal = Self.insetRange(
            lower: visibleFrame.minX, upper: visibleFrame.maxX,
            inset: edgeInset, extent: petSize.width
        )
        let vertical = Self.insetRange(
            lower: visibleFrame.minY, upper: visibleFrame.maxY,
            inset: edgeInset, extent: petSize.height
        )
        return CGRect(
            x: horizontal.lowerBound,
            y: vertical.lowerBound,
            width: horizontal.upperBound - horizontal.lowerBound,
            height: vertical.upperBound - vertical.lowerBound
        )
    }

    private static func insetRange(
        lower: Double,
        upper: Double,
        inset: Double,
        extent: Double
    ) -> ClosedRange<Double> {
        let low = lower + inset + extent / 2
        let high = upper - inset - extent / 2
        guard high > low else {
            let middle = (lower + upper) / 2
            return middle...middle
        }
        return low...high
    }

    // MARK: Choosing what to do

    /// A new x on the pet's *current* line. Walking never changes height; that is what climbing is
    /// for, and keeping them separate means a walk target can never imply a diagonal drift.
    public func chooseWalkTarget<R: RandomNumberGenerator>(
        in area: CGRect,
        from current: CGPoint,
        using rng: inout R
    ) -> CGPoint {
        let x = chooseX(in: area.minX...area.maxX, from: current.x, using: &rng)
        return CGPoint(x: x, y: current.y)
    }

    /// A different height to climb to, or nil when there is not enough room to bother.
    ///
    /// The result is always inside `area` and always differs from `currentY`, so a climb can never
    /// be a no-op that plays the animation while standing still.
    public func chooseClimbTarget<R: RandomNumberGenerator>(
        in area: CGRect,
        from currentY: Double,
        using rng: inout R
    ) -> Double? {
        let lower = area.minY
        let upper = area.maxY
        guard upper - lower >= minClimb else { return nil }

        for _ in 0..<8 {
            let candidate = Double.random(in: lower...upper, using: &rng)
            if abs(candidate - currentY) >= minClimb { return candidate }
        }

        // Fall back to whichever end is further away. The span check above guarantees that is a
        // real move, just possibly a shorter one.
        return abs(lower - currentY) > abs(upper - currentY) ? lower : upper
    }

    private func chooseX<R: RandomNumberGenerator>(
        in range: ClosedRange<Double>,
        from currentX: Double,
        using rng: inout R
    ) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }

        let span = range.upperBound - range.lowerBound
        // Give up after a few tries; a short walk is better than an infinite loop.
        let effectiveMinTravel = Swift.min(minTravel, span / 2)
        for _ in 0..<8 {
            let candidate = Double.random(in: range, using: &rng)
            if abs(candidate - currentX) >= effectiveMinTravel { return candidate }
        }
        // Fall back to the far end of the range from where we are.
        let lowerIsFurther = abs(range.lowerBound - currentX) >= abs(range.upperBound - currentX)
        return lowerIsFurther ? range.lowerBound : range.upperBound
    }

    public func facing(fromX: Double, toX: Double) -> Facing {
        Facing(fromX: fromX, toX: toX)
    }

    // MARK: Moving

    /// One integration step toward `target`, at `speed` points per second.
    ///
    /// Returns the new position and whether the target was reached this tick. Clamps exactly onto
    /// the target rather than overshooting, so the pet never jitters around its destination.
    public func step(
        from current: CGPoint,
        to target: CGPoint,
        dt: Double,
        speed: Double
    ) -> (position: CGPoint, arrived: Bool) {
        let delta = CGPoint(x: target.x - current.x, y: target.y - current.y)
        let distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()

        guard dt > 0, distance > .ulpOfOne else {
            return (distance <= .ulpOfOne ? target : current, distance <= .ulpOfOne)
        }

        let maxStep = max(speed, 0) * dt
        guard distance > maxStep else { return (target, true) }

        let scale = maxStep / distance
        return (CGPoint(x: current.x + delta.x * scale, y: current.y + delta.y * scale), false)
    }

    /// How long to stand still before the next activity.
    public func pause<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        guard maxPause > minPause else { return minPause }
        return Double.random(in: minPause...maxPause, using: &rng)
    }
}

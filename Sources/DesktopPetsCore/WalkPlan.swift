import CoreGraphics
import Foundation

/// Which way the sprite faces. Left-facing frames are drawn by flipping the right-facing art.
public enum Facing: String, Equatable {
    case left
    case right

    public var isFlipped: Bool { self == .left }

    public init(fromX: Double, toX: Double) {
        self = toX < fromX ? .left : .right
    }
}

/// Decides where to walk, which way to face, how far to move this tick, and how long to rest.
///
/// Stateless apart from its tuning values, so every method is directly testable. Randomness is
/// injected as a `RandomNumberGenerator` so tests can seed it.
public struct WalkPlan: Equatable {
    /// Horizontal speed in points per second.
    public var speed: Double
    /// How far the pet keeps its centre from the screen's visible edges.
    public var edgeInset: Double
    /// Bounds on the idle pause between walks, in seconds.
    public var minPause: Double
    public var maxPause: Double
    /// Target must be at least this far away to be worth walking to; avoids twitchy micro-steps.
    public var minTravel: Double

    public init(
        speed: Double = 42,
        edgeInset: Double = 24,
        minPause: Double = 2.5,
        maxPause: Double = 7,
        minTravel: Double = 48
    ) {
        self.speed = speed
        self.edgeInset = edgeInset
        self.minTravel = minTravel
        // Keep the ranges sane even if a config value arrives out of order.
        self.minPause = Swift.min(minPause, maxPause)
        self.maxPause = Swift.max(minPause, maxPause)
    }

    /// The x range the hotspot may occupy, keeping the whole sprite inside `visibleFrame`.
    ///
    /// Collapses to the horizontal midpoint when the sprite cannot fit, so callers never have
    /// to deal with an inverted range.
    public func walkableRange(in visibleFrame: CGRect, petWidth: Double) -> ClosedRange<Double> {
        let lower = visibleFrame.minX + edgeInset + petWidth / 2
        let upper = visibleFrame.maxX - edgeInset - petWidth / 2
        if upper < lower {
            let middle = visibleFrame.midX
            return middle...middle
        }
        return lower...upper
    }

    /// A random destination, re-rolled (bounded) until it is at least ``minTravel`` away.
    public func chooseTarget<R: RandomNumberGenerator>(
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

    /// One integration step. Returns the new x and whether the target was reached this tick.
    ///
    /// Clamps exactly onto the target rather than overshooting, so the pet never jitters around
    /// its destination.
    public func step(fromX: Double, toX: Double, dt: Double) -> (x: Double, arrived: Bool) {
        guard dt > 0 else { return (fromX, abs(toX - fromX) < .ulpOfOne) }
        let delta = toX - fromX
        let distance = abs(delta)
        let maxStep = max(speed, 0) * dt
        if distance <= maxStep { return (toX, true) }
        return (fromX + (delta < 0 ? -maxStep : maxStep), false)
    }

    /// How long to stand still before the next walk.
    public func pause<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        guard maxPause > minPause else { return minPause }
        return Double.random(in: minPause...maxPause, using: &rng)
    }
}

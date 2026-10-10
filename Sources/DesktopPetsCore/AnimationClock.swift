import Foundation

/// Turns elapsed time into a frame index for one animation state.
///
/// Frame selection is derived from accumulated time rather than incremented per tick, so a
/// dropped timer tick don't slow the animation down.
public struct AnimationClock: Equatable {
    public let frameCount: Int
    public let fps: Double
    public let loops: Bool
    /// Time accumulated within the current playback, in seconds.
    public private(set) var elapsed: Double

    public init(frameCount: Int, fps: Double, loops: Bool) {
        self.frameCount = Swift.max(0, frameCount)
        self.fps = fps
        self.loops = loops
        self.elapsed = 0
    }

    /// Index of the frame to draw right now. Always a valid index for `frameCount > 0`.
    public var frameIndex: Int {
        guard frameCount > 0, fps > 0 else { return 0 }
        let raw = Int(elapsed * fps)
        if loops {
            return raw % frameCount
        }
        return Swift.min(raw, frameCount - 1)
    }

    /// True once a non-looping animation has shown its last frame.
    public var isFinished: Bool {
        guard !loops, frameCount > 0, fps > 0 else { return false }
        return Int(elapsed * fps) >= frameCount
    }

    /// Total duration of one pass, in seconds. `nil` when the animation cannot advance.
    public var duration: Double? {
        guard frameCount > 0, fps > 0 else { return nil }
        return Double(frameCount) / fps
    }

    /// Progress through one pass in `0...1`, for callers that want to blend or fade.
    public var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        if loops {
            return (elapsed.truncatingRemainder(dividingBy: duration)) / duration
        }
        return Swift.min(elapsed / duration, 1)
    }

    public mutating func advance(by dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        elapsed += dt
        wrapIfLooping()
    }

    public mutating func reset() {
        elapsed = 0
    }

    /// Keeps `elapsed` bounded so long runs can't overflow `Int(elapsed * fps)`.
    private mutating func wrapIfLooping() {
        guard loops, let duration, duration > 0 else { return }
        if elapsed >= duration {
            elapsed = elapsed.truncatingRemainder(dividingBy: duration)
        }
    }
}

import CoreGraphics

/// Everything the view needs in order to draw the current animation frame.
///
/// Comparable so the caller can skip re-drawing when nothing about it changed. The tick runs at
/// 30Hz while the sprite only advances at 3-12fps, so without this most ticks repaint a byte-identical
/// image — which measured as a flat ~3% of a core whether the pet was walking or asleep.
public struct SpriteFrameToken: Equatable {
    public let state: String
    public let frameIndex: Int

    public init(state: String, frameIndex: Int) {
        self.state = state
        self.frameIndex = frameIndex
    }
}

/// Maps "which animation is playing" plus elapsed time onto "which frame to draw".
///
/// The frame index comes from `AnimationClock` rather than an incrementing counter, so a dropped
/// tick does not slow the animation down.
///
/// Lives in Core rather than the app target so the decision of *when a redraw is needed* can be
/// unit tested. Getting that wrong does not look like a bug — it looks like an animation that has
/// stopped — which is exactly the kind of thing you cannot catch by watching it.
public final class AnimationController {
    public private(set) var state: String = ""
    public private(set) var frame: CGImage?
    /// Index of `frame` within the current animation.
    public private(set) var frameIndex: Int = 0

    private var animation: SpriteAnimation?
    private var clock = AnimationClock(frameCount: 0, fps: 1, loops: true)

    public init() {}

    /// True once a non-looping animation has finished playing.
    public var isFinished: Bool { clock.isFinished }

    public var frameCount: Int { animation?.frameCount ?? 0 }

    /// What the view would need to draw right now. Compare against the last drawn token to decide
    /// whether a redraw is warranted.
    public var token: SpriteFrameToken {
        SpriteFrameToken(state: state, frameIndex: frameIndex)
    }

    /// Switches to `animation`. Restarting the same state is a no-op, so a looping animation is
    /// not reset on every tick.
    public func play(_ animation: SpriteAnimation?) {
        guard let animation else {
            state = ""
            self.animation = nil
            frame = nil
            frameIndex = 0
            return
        }

        guard state != animation.state || self.animation == nil else { return }

        state = animation.state
        self.animation = animation
        clock = AnimationClock(
            frameCount: animation.frameCount,
            fps: animation.spec.fps,
            loops: animation.spec.loop
        )
        refresh()
    }

    /// Replays the current animation from the start.
    public func restart() {
        clock.reset()
        refresh()
    }

    public func advance(by dt: Double) {
        guard animation != nil else { return }
        clock.advance(by: dt)
        refresh()
    }

    private func refresh() {
        guard let animation, !animation.frames.isEmpty else {
            frame = nil
            frameIndex = 0
            return
        }
        let index = min(max(clock.frameIndex, 0), animation.frames.count - 1)
        frameIndex = index
        frame = animation.frames[index]
    }
}

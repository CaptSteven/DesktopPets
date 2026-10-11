import CoreGraphics
import DesktopPetsCore

/// Maps "which animation is playing" plus elapsed time onto "which frame to draw".
///
/// The frame index comes from `AnimationClock` rather than an incrementing counter, so a dropped
/// tick does not slow the animation down.
final class AnimationController {
    private(set) var state: String = ""
    private(set) var frame: CGImage?

    private var animation: SpriteAnimation?
    private var clock = AnimationClock(frameCount: 0, fps: 1, loops: true)

    /// True once a non-looping animation has finished playing.
    var isFinished: Bool { clock.isFinished }

    var frameCount: Int { animation?.frameCount ?? 0 }

    /// Switches to `animation`. Restarting the same state is a no-op, so a looping animation is
    /// not reset on every tick.
    func play(_ animation: SpriteAnimation?) {
        guard let animation else {
            state = ""
            self.animation = nil
            frame = nil
            return
        }

        guard state != animation.state || self.animation == nil else { return }

        // Logged on change only. Which animation is playing is otherwise invisible from outside the
        // process, which is what made "it still looks asleep after I clicked it" hard to pin down:
        // the state machine had moved on, but nothing was re-drawing the sprite.
        if state != animation.state {
            Log.sprite.notice("animation -> \(animation.state, privacy: .public)")
        }

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
    func restart() {
        clock.reset()
        refresh()
    }

    func advance(by dt: Double) {
        guard animation != nil else { return }
        clock.advance(by: dt)
        refresh()
    }

    private func refresh() {
        guard let animation, !animation.frames.isEmpty else {
            frame = nil
            return
        }
        let index = min(max(clock.frameIndex, 0), animation.frames.count - 1)
        frame = animation.frames[index]
    }
}

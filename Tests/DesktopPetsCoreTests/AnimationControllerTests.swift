import CoreGraphics
import Testing
@testable import DesktopPetsCore

/// Builds throwaway animations. The images are 2x2 and never inspected; these tests are about
/// *when* the controller says a redraw is needed, not what gets drawn.
private func makeImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

private func makeAnimation(
    state: String,
    frameCount: Int,
    fps: Double,
    loops: Bool
) -> SpriteAnimation {
    SpriteAnimation(
        state: state,
        spec: StateSpec(fps: fps, loop: loops),
        frames: (0..<frameCount).map { _ in makeImage() },
        masks: []
    )
}

@Suite struct AnimationControllerTests {
    // MARK: The redraw token

    @Test func advancingWithinOneFrameDoesNotChangeTheToken() {
        // 4 frames at 10fps means a new frame every 0.1s.
        let controller = AnimationController()
        controller.play(makeAnimation(state: "idle", frameCount: 4, fps: 10, loops: true))

        let initial = controller.token
        #expect(initial == SpriteFrameToken(state: "idle", frameIndex: 0))

        // Three 0.03s steps land on 0.09s: still inside the first frame.
        for _ in 0..<3 { controller.advance(by: 0.03) }

        #expect(controller.token == initial, "re-drawing an identical frame is the thing being avoided")
    }

    @Test func crossingIntoTheNextFrameChangesTheToken() {
        let controller = AnimationController()
        controller.play(makeAnimation(state: "idle", frameCount: 4, fps: 10, loops: true))

        for _ in 0..<3 { controller.advance(by: 0.03) }
        controller.advance(by: 0.03) // 0.12s, now into frame 1

        #expect(controller.token == SpriteFrameToken(state: "idle", frameIndex: 1))
    }

    @Test func aThirtyHertzTickDoesNotAskForThirtyRedrawsPerSecond() throws {
        // This is the whole point of the token. The tick runs at 30Hz and the sprite advances at
        // 10fps, so two ticks in three would otherwise repaint a byte-identical image. That
        // measured as a flat ~3% of a core in both the walking and the sleeping state.
        let controller = AnimationController()
        controller.play(makeAnimation(state: "walk", frameCount: 4, fps: 10, loops: true))

        var changes = 0
        var seen = Set<Int>()
        var previous = controller.token

        for _ in 0..<30 { // one second of ticks
            controller.advance(by: 1.0 / 30.0)
            let token = controller.token
            seen.insert(token.frameIndex)
            if token != previous {
                changes += 1
                previous = token
            }
        }

        #expect(changes < 10, "30 ticks caused \(changes) redraws; expected roughly one per frame")
        #expect(seen == [0, 1, 2, 3], "every frame of the loop should still be reached")
    }

    @Test func switchingStateChangesTheToken() {
        let controller = AnimationController()
        controller.play(makeAnimation(state: "idle", frameCount: 4, fps: 6, loops: true))
        let idle = controller.token

        controller.play(makeAnimation(state: "sleep", frameCount: 4, fps: 3, loops: true))

        #expect(controller.token != idle)
        #expect(controller.token.state == "sleep")
    }

    @Test func aNonLoopingAnimationHoldsTheSameTokenOnItsLastFrame() {
        // `click` plays once and then sits on the final frame until the state machine moves on.
        let controller = AnimationController()
        controller.play(makeAnimation(state: "click", frameCount: 6, fps: 12, loops: false))

        controller.advance(by: 10) // far past the end
        let settled = controller.token
        #expect(settled == SpriteFrameToken(state: "click", frameIndex: 5))
        #expect(controller.isFinished)

        // More time must not keep asking for redraws of a finished one-shot.
        for _ in 0..<10 { controller.advance(by: 0.01) }
        #expect(controller.token == settled)
    }

    @Test func restartReturnsTheTokenToTheFirstFrame() {
        // How a second click replays the reaction: the state name does not change, so a token
        // comparing state alone would miss it.
        let controller = AnimationController()
        controller.play(makeAnimation(state: "click", frameCount: 4, fps: 10, loops: false))
        controller.advance(by: 0.25)

        let partway = controller.token
        #expect(partway.frameIndex > 0)

        controller.restart()
        #expect(controller.token == SpriteFrameToken(state: "click", frameIndex: 0))
        #expect(controller.token != partway, "restarting must ask for a redraw")
    }

    @Test func replayingTheSameStateIsANoOpSoALoopIsNotResetEveryTick() {
        let animation = makeAnimation(state: "idle", frameCount: 4, fps: 10, loops: true)
        let controller = AnimationController()
        controller.play(animation)
        controller.advance(by: 0.25)

        let partway = controller.token
        controller.play(animation) // same state, as happens every tick

        #expect(controller.token == partway, "a looping animation must not restart each tick")
    }

    @Test func playingNothingClearsTheToken() {
        let controller = AnimationController()
        controller.play(makeAnimation(state: "idle", frameCount: 4, fps: 6, loops: true))

        controller.play(nil)

        #expect(controller.token == SpriteFrameToken(state: "", frameIndex: 0))
        #expect(controller.frame == nil)
    }

    // MARK: Frame selection

    @Test func everyFrameIsReachableInALoop() {
        let controller = AnimationController()
        controller.play(makeAnimation(state: "walk", frameCount: 6, fps: 10, loops: true))

        var seen: [Int] = []
        for _ in 0..<60 {
            controller.advance(by: 0.1 / 4) // sample finer than the frame rate
            if seen.last != controller.frameIndex { seen.append(controller.frameIndex) }
        }

        #expect(Set(seen) == Set(0..<6))
        #expect(seen.count >= 6)
    }

    @Test func theFrameMatchesTheIndex() {
        let frames = (0..<3).map { _ in makeImage() }
        let animation = SpriteAnimation(
            state: "idle",
            spec: StateSpec(fps: 10, loop: true),
            frames: frames,
            masks: []
        )
        let controller = AnimationController()
        controller.play(animation)

        for _ in 0..<20 {
            controller.advance(by: 0.05)
            let index = controller.frameIndex
            #expect((0..<3).contains(index))
            #expect(controller.frame === frames[index], "the drawn image must match the reported index")
        }
    }

    @Test func anAnimationWithNoFramesIsHarmless() {
        let controller = AnimationController()
        controller.play(SpriteAnimation(
            state: "broken",
            spec: StateSpec(fps: 10, loop: true),
            frames: [],
            masks: []
        ))

        controller.advance(by: 1)

        #expect(controller.frame == nil)
        #expect(controller.frameIndex == 0)
        #expect(controller.token == SpriteFrameToken(state: "broken", frameIndex: 0))
    }

    @Test func tokensAreComparableAcrossControllers() {
        // PetController compares the token against the last one it drew. A fresh controller (after a
        // skin change) starts at frame 0, which is why that comparison starts from nil rather than a
        // default token.
        let a = AnimationController()
        a.play(makeAnimation(state: "idle", frameCount: 4, fps: 6, loops: true))

        let b = AnimationController()
        b.play(makeAnimation(state: "idle", frameCount: 4, fps: 6, loops: true))

        #expect(a.token == b.token)
    }
}

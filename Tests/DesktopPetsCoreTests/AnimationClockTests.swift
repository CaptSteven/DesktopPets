import Testing
@testable import DesktopPetsCore

@Suite struct AnimationClockTests {
    // MARK: Looping playback

    @Test func loopingAdvancesOneFramePerFrameDuration() {
        // 4 frames at 10fps => a new frame every 0.1s.
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: true)
        #expect(clock.frameIndex == 0)

        clock.advance(by: 0.05)
        #expect(clock.frameIndex == 0, "half a frame in, still on frame 0")

        clock.advance(by: 0.05)
        #expect(clock.frameIndex == 1)

        clock.advance(by: 0.1)
        #expect(clock.frameIndex == 2)

        clock.advance(by: 0.1)
        #expect(clock.frameIndex == 3)
    }

    @Test func loopingWrapsBackToTheFirstFrame() {
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: true)

        clock.advance(by: 0.4) // exactly one full cycle
        #expect(clock.frameIndex == 0)
        #expect(!clock.isFinished)

        clock.advance(by: 0.05)
        #expect(clock.frameIndex == 0)
        clock.advance(by: 0.05)
        #expect(clock.frameIndex == 1, "playback continued into the second cycle")
    }

    @Test func loopingNeverFinishes() {
        var clock = AnimationClock(frameCount: 3, fps: 6, loops: true)
        for _ in 0..<100 {
            clock.advance(by: 0.1)
            #expect(!clock.isFinished)
        }
    }

    @Test func loopingKeepsElapsedBoundedSoLongRunsCannotOverflow() throws {
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: true)

        // ~11.5 days of accumulated time at 1000s per tick.
        for _ in 0..<1000 {
            clock.advance(by: 1000)
        }

        let duration = try #require(clock.duration)
        #expect(clock.elapsed < duration, "elapsed must wrap instead of growing without bound")
        #expect((0..<4).contains(clock.frameIndex))
    }

    @Test func loopingIsFrameRateIndependent() {
        // The same total time must land on the same frame regardless of tick size.
        var coarse = AnimationClock(frameCount: 8, fps: 12, loops: true)
        var fine = AnimationClock(frameCount: 8, fps: 12, loops: true)

        coarse.advance(by: 0.25)
        for _ in 0..<25 { fine.advance(by: 0.01) }

        #expect(coarse.frameIndex == fine.frameIndex)
    }

    // MARK: Non-looping playback

    @Test func nonLoopingHoldsOnTheLastFrameAndFinishes() {
        // 3 frames at 10fps: the third frame runs from 0.2s to 0.3s.
        var clock = AnimationClock(frameCount: 3, fps: 10, loops: false)

        clock.advance(by: 0.25)
        #expect(clock.frameIndex == 2, "clamped to the last frame")
        #expect(!clock.isFinished, "still mid-way through showing the last frame")

        clock.advance(by: 0.05) // total 0.30s: the last frame's time is up
        #expect(clock.isFinished)
        #expect(clock.frameIndex == 2)

        clock.advance(by: 10)
        #expect(clock.frameIndex == 2, "must not run past the last frame")
        #expect(clock.isFinished)
    }

    @Test func nonLoopingIsNotFinishedOnTheFinalFrameBoundary() {
        // 3 frames at 10fps: the third frame starts at 0.2s and finishes at 0.3s.
        var clock = AnimationClock(frameCount: 3, fps: 10, loops: false)
        clock.advance(by: 0.2)

        #expect(clock.frameIndex == 2)
        #expect(!clock.isFinished, "the last frame is still being shown")
    }

    @Test func resetRestartsPlayback() {
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: false)
        clock.advance(by: 1)
        #expect(clock.isFinished)

        clock.reset()
        #expect(clock.frameIndex == 0)
        #expect(clock.elapsed == 0)
        #expect(!clock.isFinished)
    }

    // MARK: Degenerate input

    @Test func zeroFPSAndZeroFramesStayOnFrameZero() {
        var noFPS = AnimationClock(frameCount: 4, fps: 0, loops: true)
        noFPS.advance(by: 5)
        #expect(noFPS.frameIndex == 0)
        #expect(!noFPS.isFinished)
        #expect(noFPS.duration == nil)

        var noFrames = AnimationClock(frameCount: 0, fps: 10, loops: false)
        noFrames.advance(by: 5)
        #expect(noFrames.frameIndex == 0)
        #expect(!noFrames.isFinished)
        #expect(noFrames.duration == nil)
    }

    @Test func negativeFrameCountIsNormalisedToZero() {
        let clock = AnimationClock(frameCount: -5, fps: 10, loops: false)
        #expect(clock.frameCount == 0)
        #expect(clock.frameIndex == 0)
    }

    @Test func nonPositiveOrNonFiniteDeltaTimeIsIgnored() {
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: true)

        clock.advance(by: 0)
        clock.advance(by: -1)
        clock.advance(by: .nan)
        clock.advance(by: .infinity)

        #expect(clock.elapsed == 0, "garbage delta times must not corrupt the clock")
        #expect(clock.frameIndex == 0)
    }

    @Test func singleFrameAnimationIsStable() {
        var looping = AnimationClock(frameCount: 1, fps: 6, loops: true)
        for _ in 0..<50 { looping.advance(by: 0.1) }
        #expect(looping.frameIndex == 0)
        #expect(!looping.isFinished)

        var once = AnimationClock(frameCount: 1, fps: 6, loops: false)
        once.advance(by: 1)
        #expect(once.frameIndex == 0)
        #expect(once.isFinished)
    }

    @Test func durationAndProgress() throws {
        var clock = AnimationClock(frameCount: 4, fps: 10, loops: true)
        #expect(abs(try #require(clock.duration) - 0.4) <= 0.0001)
        #expect(abs(clock.progress - 0) <= 0.0001)

        clock.advance(by: 0.2)
        #expect(abs(clock.progress - 0.5) <= 0.0001)

        clock.advance(by: 0.4) // wraps
        #expect(abs(clock.progress - 0.5) <= 0.0001)
    }

    @Test func nonLoopingProgressClampsAtOne() {
        var clock = AnimationClock(frameCount: 2, fps: 10, loops: false)
        clock.advance(by: 99)
        #expect(abs(clock.progress - 1) <= 0.0001)
    }
}

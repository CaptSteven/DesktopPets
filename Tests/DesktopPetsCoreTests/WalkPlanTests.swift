import CoreGraphics
import Testing
@testable import DesktopPetsCore

@Suite struct WalkPlanTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let petWidth: Double = 64

    // MARK: Walkable range

    @Test func walkableRangeKeepsTheWholeSpriteInsideTheVisibleFrame() {
        let plan = WalkPlan(edgeInset: 24)
        let range = plan.walkableRange(in: screen, petWidth: petWidth)

        // 0 + 24 + 32 = 56, and 1000 - 24 - 32 = 944.
        #expect(range.lowerBound == 56)
        #expect(range.upperBound == 944)

        // The resulting window edges are inside the frame at both extremes.
        let leftmostWindowEdge = range.lowerBound - petWidth / 2
        let rightmostWindowEdge = range.upperBound + petWidth / 2
        #expect(leftmostWindowEdge >= screen.minX + plan.edgeInset)
        #expect(rightmostWindowEdge <= screen.maxX - plan.edgeInset)
    }

    @Test func walkableRangeCollapsesToTheMiddleWhenTheSpriteDoesNotFit() {
        let narrow = CGRect(x: 0, y: 0, width: 80, height: 800)
        let range = WalkPlan(edgeInset: 24).walkableRange(in: narrow, petWidth: petWidth)

        #expect(range.lowerBound == 40)
        #expect(range.upperBound == 40)
        #expect(range.lowerBound <= range.upperBound, "range must not be inverted")
    }

    @Test func walkableRangeRespectsANegativeOriginScreen() {
        let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let range = WalkPlan(edgeInset: 0).walkableRange(in: leftScreen, petWidth: 64)

        #expect(range.lowerBound == -1920 + 32)
        #expect(range.upperBound == 0 - 32)
    }

    // MARK: Facing

    @Test func facingFollowsTheDirectionOfTravel() {
        #expect(Facing(fromX: 500, toX: 100) == .left)
        #expect(Facing(fromX: 100, toX: 500) == .right)
        // Standing still keeps facing right rather than flickering.
        #expect(Facing(fromX: 300, toX: 300) == .right)
        #expect(Facing.left.isFlipped)
        #expect(!Facing.right.isFlipped)
    }

    // MARK: Stepping

    @Test func stepMovesAtMostSpeedTimesDeltaTime() {
        let plan = WalkPlan(speed: 42)
        let result = plan.step(fromX: 0, toX: 100, dt: 1)

        #expect(abs(result.x - 42) <= 0.0001)
        #expect(!result.arrived)
    }

    @Test func stepMovesLeftWhenTheTargetIsBehind() {
        let plan = WalkPlan(speed: 42)
        let result = plan.step(fromX: 100, toX: 0, dt: 1)

        #expect(abs(result.x - 58) <= 0.0001)
        #expect(!result.arrived)
    }

    @Test func stepLandsExactlyOnTheTargetWithoutOvershooting() {
        let plan = WalkPlan(speed: 42)
        let result = plan.step(fromX: 0, toX: 100, dt: 10)

        #expect(abs(result.x - 100) <= 0.0001, "must clamp onto the target, not overshoot")
        #expect(result.arrived)
    }

    @Test func stepReportsArrivalWhenAlreadyThere() {
        let plan = WalkPlan(speed: 42)
        let result = plan.step(fromX: 250, toX: 250, dt: 0.033)

        #expect(abs(result.x - 250) <= 0.0001)
        #expect(result.arrived)
    }

    @Test func stepWithNonPositiveDeltaTimeDoesNotMove() {
        let plan = WalkPlan(speed: 42)
        #expect(abs(plan.step(fromX: 10, toX: 900, dt: 0).x - 10) <= 0.0001)
    }

    @Test func repeatedStepsConvergeOnTheTarget() {
        let plan = WalkPlan(speed: 42)
        var x = 0.0
        var ticks = 0
        let target = 400.0

        while ticks < 10_000 {
            let result = plan.step(fromX: x, toX: target, dt: 1.0 / 30.0)
            x = result.x
            ticks += 1
            if result.arrived { break }
        }

        #expect(abs(x - target) <= 0.0001)
        // 400pt at 42pt/s is ~9.5s, so ~286 ticks at 30Hz. Generous bound to avoid flakiness.
        #expect(ticks < 400)
    }

    // MARK: Target selection

    @Test func chooseTargetStaysWithinRangeAndRespectsMinimumTravel() {
        let plan = WalkPlan(minTravel: 48)
        let range = plan.walkableRange(in: screen, petWidth: petWidth)
        var rng = SeededGenerator(seed: 42)

        for _ in 0..<200 {
            let currentX = Double.random(in: range, using: &rng)
            let target = plan.chooseTarget(in: range, from: currentX, using: &rng)

            #expect(range.contains(target), "target \(target) escaped \(range)")
            #expect(abs(target - currentX) >= 48, "target was a micro-step")
        }
    }

    @Test func chooseTargetReproducesForTheSameSeed() {
        let plan = WalkPlan()
        let range = plan.walkableRange(in: screen, petWidth: petWidth)

        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        let picksA = (0..<10).map { _ in plan.chooseTarget(in: range, from: 500, using: &first) }
        let picksB = (0..<10).map { _ in plan.chooseTarget(in: range, from: 500, using: &second) }

        #expect(picksA == picksB)
    }

    @Test func chooseTargetWithADegenerateRangeReturnsThatPoint() {
        var rng = SeededGenerator(seed: 1)
        #expect(WalkPlan().chooseTarget(in: 300...300, from: 900, using: &rng) == 300)
    }

    @Test func chooseTargetRelaxesMinimumTravelOnATinyScreen() {
        // A 20pt range cannot satisfy a 48pt minimum travel; it must still terminate.
        let range = 0.0...20.0
        var rng = SeededGenerator(seed: 3)

        #expect(range.contains(WalkPlan(minTravel: 48).chooseTarget(in: range, from: 10, using: &rng)))
    }

    // MARK: Pauses

    @Test func pauseStaysWithinBounds() {
        let plan = WalkPlan(minPause: 2, maxPause: 5)
        var rng = SeededGenerator(seed: 11)

        for _ in 0..<200 {
            let pause = plan.pause(using: &rng)
            #expect(pause >= 2)
            #expect(pause <= 5)
        }
    }

    @Test func pauseNormalisesSwappedBounds() {
        // A caller passing (max, min) must not produce an invalid range that traps.
        let plan = WalkPlan(minPause: 9, maxPause: 1)
        var rng = SeededGenerator(seed: 11)

        #expect(plan.minPause == 1)
        #expect(plan.maxPause == 9)
        let pause = plan.pause(using: &rng)
        #expect(pause >= 1)
        #expect(pause <= 9)
    }

    @Test func pauseWithEqualBoundsIsConstant() {
        var rng = SeededGenerator(seed: 11)
        #expect(WalkPlan(minPause: 3, maxPause: 3).pause(using: &rng) == 3)
    }

    @Test func defaultPlanIsConfiguredForAmbling() {
        let plan = WalkPlan()
        #expect(plan.speed > 0)
        #expect(plan.minPause <= plan.maxPause)
    }
}

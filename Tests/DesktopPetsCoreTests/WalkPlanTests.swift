import CoreGraphics
import Testing
@testable import DesktopPetsCore

@Suite struct WalkPlanTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let petSize = CGSize(width: 64, height: 64)

    // MARK: Walkable area

    @Test func walkableAreaKeepsTheWholeSpriteInsideTheVisibleFrame() {
        let plan = WalkPlan(edgeInset: 24)
        let area = plan.walkableArea(in: screen, petSize: petSize)

        // Hotspot bounds, half a sprite in from the inset edge on every side.
        #expect(area.minX == 56) // 0 + 24 + 32
        #expect(area.maxX == 944) // 1000 - 24 - 32
        #expect(area.minY == 56)
        #expect(area.maxY == 744)
    }

    @Test func walkableAreaCollapsesToTheMiddleWhenTheSpriteDoesNotFit() {
        let narrow = CGRect(x: 0, y: 0, width: 80, height: 80)
        let area = WalkPlan(edgeInset: 24).walkableArea(in: narrow, petSize: petSize)

        #expect(area.midX == 40)
        #expect(area.midY == 40)
        #expect(area.width >= 0, "the area must never be inverted")
        #expect(area.height >= 0)
    }

    @Test func walkableAreaRespectsANegativeOriginScreen() {
        // A second display positioned to the left of and below the primary one.
        let leftScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let area = WalkPlan(edgeInset: 0).walkableArea(in: leftScreen, petSize: petSize)

        // Typed explicitly: inline arithmetic on the right of == infers Int and compares unequal
        // for equal numbers. See the note at the top of TestSupport.swift.
        let expectedMinX: CGFloat = -1920 + 32
        let expectedMaxX: CGFloat = 0 - 32
        let expectedMinY: CGFloat = -200 + 32

        #expect(area.minX == expectedMinX)
        #expect(area.maxX == expectedMaxX)
        #expect(area.minY == expectedMinY)
    }

    // MARK: Choosing a walk

    @Test func aWalkTargetStaysOnTheCurrentLine() {
        // Walking never changes height — that is what climbing is for, and keeping them separate
        // means a walk can never imply a diagonal drift.
        let plan = WalkPlan(minTravel: 48)
        let area = plan.walkableArea(in: screen, petSize: petSize)
        let current = CGPoint(x: 300, y: 400)
        var rng = SeededGenerator(seed: 42)

        for _ in 0..<50 {
            let target = plan.chooseWalkTarget(in: area, from: current, using: &rng)
            #expect(target.y == current.y, "a walk target must not change height")
        }
    }

    @Test func aWalkTargetIsInsideTheAreaAndWorthStarting() {
        let plan = WalkPlan(minTravel: 48)
        let area = plan.walkableArea(in: screen, petSize: petSize)
        var rng = SeededGenerator(seed: 7)

        for _ in 0..<200 {
            let currentX = Double.random(in: area.minX...area.maxX, using: &rng)
            let current = CGPoint(x: currentX, y: 400)
            let target = plan.chooseWalkTarget(in: area, from: current, using: &rng)

            #expect(area.contains(target), "target \(target) escaped \(area)")
            #expect(abs(target.x - current.x) >= 48, "target was a micro-step")
        }
    }

    @Test func walkTargetsReproduceForTheSameSeed() {
        let plan = WalkPlan()
        let area = plan.walkableArea(in: screen, petSize: petSize)

        var first = SeededGenerator(seed: 9)
        var second = SeededGenerator(seed: 9)
        let a = (0..<10).map { _ in plan.chooseWalkTarget(in: area, from: CGPoint(x: 500, y: 100), using: &first) }
        let b = (0..<10).map { _ in plan.chooseWalkTarget(in: area, from: CGPoint(x: 500, y: 100), using: &second) }

        #expect(a == b)
    }

    // MARK: Choosing a climb

    @Test func aClimbTargetChangesHeightAndStaysInsideTheArea() {
        let plan = WalkPlan(minClimb: 90)
        let area = plan.walkableArea(in: screen, petSize: petSize)
        var rng = SeededGenerator(seed: 3)

        for _ in 0..<200 {
            let currentY = Double.random(in: area.minY...area.maxY, using: &rng)
            let target = plan.chooseClimbTarget(in: area, from: currentY, using: &rng)

            let unwrapped = try? #require(target)
            guard let unwrapped else { continue }
            #expect(area.minY...area.maxY ~= unwrapped)
            #expect(unwrapped != currentY, "a climb that goes nowhere would play the animation on the spot")
        }
    }

    @Test func aClimbTargetIsAtLeastMinClimbAwayWhenThereIsRoom() {
        let plan = WalkPlan(minClimb: 90)
        let area = plan.walkableArea(in: screen, petSize: petSize)
        var rng = SeededGenerator(seed: 11)

        // Start from a plain interior point so the re-roll has room to satisfy the minimum.
        for _ in 0..<100 {
            let target = try? #require(plan.chooseClimbTarget(in: area, from: 400, using: &rng))
            if let target { #expect(abs(target - 400) >= 90) }
        }
    }

    @Test func thereIsNoClimbWhenThereIsNowhereToGo() {
        // A screen barely taller than the pet: climbing would be a no-op, so the plan declines.
        let shortScreen = CGRect(x: 0, y: 0, width: 1000, height: 140)
        let plan = WalkPlan(edgeInset: 24, minClimb: 90)
        let area = plan.walkableArea(in: shortScreen, petSize: petSize)
        var rng = SeededGenerator(seed: 5)

        #expect(area.height < 90)
        #expect(plan.chooseClimbTarget(in: area, from: area.midY, using: &rng) == nil)
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
        let result = plan.step(from: .zero, to: CGPoint(x: 100, y: 0), dt: 1, speed: plan.speed)

        #expect(abs(result.position.x - 42) <= 0.0001)
        #expect(result.position.y == 0)
        #expect(!result.arrived)
    }

    @Test func stepMovesStraightUpWhenTheTargetIsAbove() {
        // What a climb looks like: no horizontal component at all.
        let plan = WalkPlan(climbSpeed: 28)
        let result = plan.step(
            from: CGPoint(x: 500, y: 100),
            to: CGPoint(x: 500, y: 400),
            dt: 1,
            speed: plan.climbSpeed
        )

        #expect(result.position.x == 500, "climbing must not drift sideways")
        #expect(abs(result.position.y - 128) <= 0.0001)
        #expect(!result.arrived)
    }

    @Test func stepCoversTheFullDistanceOnADiagonal() {
        // The step is limited by *distance*, not per axis, so a diagonal move is not faster.
        let plan = WalkPlan()
        let result = plan.step(from: .zero, to: CGPoint(x: 30, y: 40), dt: 1, speed: 10)

        let travelled = (result.position.x * result.position.x + result.position.y * result.position.y).squareRoot()
        #expect(abs(travelled - 10) <= 0.0001, "travelled \(travelled), expected exactly the speed")
    }

    @Test func stepLandsExactlyOnTheTargetWithoutOvershooting() {
        let plan = WalkPlan()
        let result = plan.step(from: .zero, to: CGPoint(x: 100, y: 0), dt: 10, speed: 42)

        #expect(result.position == CGPoint(x: 100, y: 0))
        #expect(result.arrived)
    }

    @Test func stepReportsArrivalWhenAlreadyThere() {
        let plan = WalkPlan()
        let result = plan.step(
            from: CGPoint(x: 250, y: 250),
            to: CGPoint(x: 250, y: 250),
            dt: 0.033,
            speed: 42
        )

        #expect(result.position == CGPoint(x: 250, y: 250))
        #expect(result.arrived)
    }

    @Test func stepWithNonPositiveDeltaTimeDoesNotMove() {
        let plan = WalkPlan()
        let result = plan.step(from: .zero, to: CGPoint(x: 900, y: 900), dt: 0, speed: 42)

        #expect(result.position == .zero)
        #expect(!result.arrived)
    }

    @Test func repeatedStepsConvergeOnTheTarget() {
        let plan = WalkPlan()
        var position = CGPoint(x: 0, y: 0)
        let target = CGPoint(x: 400, y: 300)
        var ticks = 0

        while ticks < 10_000 {
            let result = plan.step(from: position, to: target, dt: 1.0 / 30.0, speed: plan.speed)
            position = result.position
            ticks += 1
            if result.arrived { break }
        }

        #expect(position == target)
        // 500pt at 42pt/s is ~12s, so ~360 ticks at 30Hz. Generous bound to avoid flakiness.
        #expect(ticks < 500)
    }

    // MARK: Pauses

    @Test func pauseStaysWithinBounds() {
        let plan = WalkPlan(minPause: 2, maxPause: 5)
        var rng = SeededGenerator(seed: 13)

        for _ in 0..<200 {
            let pause = plan.pause(using: &rng)
            #expect(pause >= 2)
            #expect(pause <= 5)
        }
    }

    @Test func pauseNormalisesSwappedBounds() {
        let plan = WalkPlan(minPause: 9, maxPause: 1)
        var rng = SeededGenerator(seed: 13)

        #expect(plan.minPause == 1)
        #expect(plan.maxPause == 9)
        let pause = plan.pause(using: &rng)
        #expect(pause >= 1)
        #expect(pause <= 9)
    }

    @Test func climbingIsSlowerThanWalking() {
        // Climbing should look like work, not a lift.
        let plan = WalkPlan()
        #expect(plan.climbSpeed < plan.speed)
    }
}

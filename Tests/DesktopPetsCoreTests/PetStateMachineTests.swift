import CoreGraphics
import Testing
@testable import DesktopPetsCore

/// A degenerate walkable area: zero width means a walk target can only be the current x, and zero
/// height means there is nowhere to climb. That makes the walk/idle/sleep tests deterministic
/// without having to seed the machine's own RNG.
private let pointArea = CGRect(x: 500, y: 500, width: 0, height: 0)

/// An area tall and wide enough for both walking and climbing.
private let roomyArea = CGRect(x: 0, y: 0, width: 800, height: 600)

@Suite struct PetStateMachineTests {
    func makeMachine(
        speed: Double = 100,
        climbSpeed: Double = 100,
        sleepAfter: Double = 30,
        clickDuration: Double = 0.5,
        initialPause: Double = 1.5,
        minPause: Double = 2,
        maxPause: Double = 2,
        performanceChance: Double = 0,
        climbChance: Double = 0,
        performances: [String] = [],
        performanceDurations: [String: Double] = [:]
    ) -> PetStateMachine {
        PetStateMachine(
            walkPlan: WalkPlan(
                speed: speed,
                climbSpeed: climbSpeed,
                minPause: minPause,
                maxPause: maxPause,
                minTravel: 0
            ),
            behavior: BehaviorPlan(
                performanceChance: performanceChance,
                climbChance: climbChance,
                performances: performances
            ),
            sleepAfter: sleepAfter,
            clickDuration: clickDuration,
            performanceDurations: performanceDurations,
            initialPause: initialPause
        )
    }

    /// Advances in small steps, the way the real 30Hz tick would.
    func advance(
        _ machine: inout PetStateMachine,
        seconds: Double,
        current: CGPoint = CGPoint(x: 500, y: 500),
        area: CGRect = pointArea,
        holdStill: Bool = false
    ) {
        let step = 1.0 / 30.0
        var elapsed = 0.0
        while elapsed < seconds {
            machine.tick(dt: step, current: current, area: area, holdStill: holdStill)
            elapsed += step
        }
    }

    // MARK: Startup

    @Test func startsIdleWithNoDestination() {
        let machine = makeMachine()

        #expect(machine.activity == .idle)
        #expect(machine.walkTarget == nil)
        #expect(machine.climbTargetY == nil)
        #expect(machine.facing == .right)
    }

    @Test func staysIdleUntilTheInitialPauseElapses() {
        var machine = makeMachine(initialPause: 1.5)

        advance(&machine, seconds: 1.0)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 1.0)
        #expect(machine.activity == .walking)
    }

    // MARK: Walking

    @Test func aWalkTargetIsWithinTheWalkableArea() throws {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1, current: CGPoint(x: 100, y: 200), area: roomyArea)

        let target = try #require(machine.walkTarget)
        #expect(roomyArea.contains(target))
        #expect(target.y == 200, "a walk must stay on the current line")
    }

    @Test func facingTurnsTowardsTheTarget() throws {
        // Standing outside the walkable area on each side, so every reachable target is on one
        // side of the pet. The area spans x 56...744.
        var left = makeMachine(initialPause: 0)
        advance(&left, seconds: 0.1, current: CGPoint(x: 1000, y: 300), area: roomyArea)
        #expect(left.activity == .walking)
        #expect(left.facing == .left, "everything reachable is to the left of x=1000")

        var right = makeMachine(initialPause: 0)
        advance(&right, seconds: 0.1, current: CGPoint(x: 0, y: 300), area: roomyArea)
        #expect(right.activity == .walking)
        #expect(right.facing == .right, "everything reachable is to the right of x=0")
    }

    @Test func arrivingReturnsToIdleAndClearsTheStaleTarget() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .walking)
        #expect(machine.walkTarget != nil)

        machine.arrivedAtDestination()
        #expect(machine.activity == .idle)
        #expect(machine.walkTarget == nil, "the stale target must not survive the walk")
    }

    @Test func arrivingRearsThePauseBeforeTheNextWalk() {
        var machine = makeMachine(initialPause: 0, minPause: 2, maxPause: 2)

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .walking)

        machine.arrivedAtDestination()
        #expect(machine.activity == .idle)

        // The 2s pause must be honoured before the next activity starts.
        advance(&machine, seconds: 1.0)
        #expect(machine.activity == .idle)
        advance(&machine, seconds: 1.5)
        #expect(machine.activity == .walking)
    }

    @Test func theTargetIsNotReRolledWhileStillGoing() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1)
        let firstTarget = machine.walkTarget
        #expect(firstTarget != nil)

        advance(&machine, seconds: 0.5)
        #expect(machine.walkTarget == firstTarget)
    }

    // MARK: Climbing

    @Test func climbsWhenThereIsRoomAndItRollsAClimb() throws {
        var machine = makeMachine(initialPause: 0, climbChance: 1.0)

        advance(&machine, seconds: 0.1, current: CGPoint(x: 400, y: 300), area: roomyArea)

        #expect(machine.activity == .climbing)
        let targetY = try #require(machine.climbTargetY)
        #expect(targetY != 300, "a climb must actually change height")
        #expect((roomyArea.minY...roomyArea.maxY).contains(targetY))
    }

    @Test func doesNotClimbWhenThereIsNowhereToGo() {
        // The zero-height area stands in for a screen with no vertical room.
        var machine = makeMachine(initialPause: 0, climbChance: 1.0)

        advance(&machine, seconds: 0.1)

        #expect(machine.activity == .walking, "with no vertical room it should just walk")
        #expect(machine.climbTargetY == nil)
    }

    @Test func doesNotClimbWhenTheSkinHasNoClimbingArt() {
        // The ladder is drawn rather than loaded, so it would still appear — and the pet would
        // slide up it in whatever pose it happened to be in. Better to stay on the ground.
        var machine = PetStateMachine(
            walkPlan: WalkPlan(speed: 100, minPause: 2, maxPause: 2, minTravel: 0),
            behavior: BehaviorPlan(performanceChance: 0, climbChance: 1.0),
            sleepAfter: 30,
            clickDuration: 0.5,
            animatableStates: ["idle", "walk"], // no "climb"
            initialPause: 0
        )

        advance(&machine, seconds: 0.1, current: CGPoint(x: 400, y: 300), area: roomyArea)

        #expect(machine.activity == .walking)
        #expect(machine.climbTargetY == nil)
    }

    @Test func aClimbEndsWhenTheDestinationIsReached() {
        var machine = makeMachine(initialPause: 0, climbChance: 1.0)

        advance(&machine, seconds: 0.1, current: CGPoint(x: 400, y: 300), area: roomyArea)
        #expect(machine.activity == .climbing)

        machine.arrivedAtDestination()

        #expect(machine.activity == .idle)
        #expect(machine.climbTargetY == nil)
    }

    @Test func climbingDoesNotCountAsInteraction() {
        var machine = makeMachine(sleepAfter: 5, initialPause: 0, climbChance: 1.0)

        advance(&machine, seconds: 2, current: CGPoint(x: 400, y: 300), area: roomyArea)
        #expect(machine.activity == .climbing)

        advance(&machine, seconds: 4, current: CGPoint(x: 400, y: 300), area: roomyArea)
        #expect(machine.activity == .sleeping, "a long climb is still not interaction")
    }

    // MARK: Performances

    @Test func performsAStateTheSkinProvides() {
        var machine = makeMachine(
            initialPause: 0,
            performanceChance: 1.0,
            performances: ["mine"],
            performanceDurations: ["mine": 0.5]
        )

        advance(&machine, seconds: 0.1)

        #expect(machine.activity == .performing("mine"))
        #expect(machine.activity.animationState == "mine")
    }

    @Test func skipsPerformancesTheSkinHasNoArtFor() {
        // Declared in the behaviour plan but absent from the skin: playing `tnt` with no frames
        // would look like the pet freezing mid-throw, so it is dropped instead.
        var machine = makeMachine(
            initialPause: 0,
            performanceChance: 1.0,
            performances: ["tnt"],
            performanceDurations: [:]
        )

        advance(&machine, seconds: 0.1)

        #expect(machine.activity == .walking, "with nothing to perform it should just walk")
    }

    @Test func aPerformancePlaysForItsDurationThenReturnsToIdle() {
        var machine = makeMachine(
            initialPause: 0,
            performanceChance: 1.0,
            performances: ["fight"],
            performanceDurations: ["fight": 0.5]
        )

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .performing("fight"))

        advance(&machine, seconds: 0.3)
        #expect(machine.activity == .performing("fight"), "still mid-swing")

        advance(&machine, seconds: 0.3)
        #expect(machine.activity == .idle, "the performance finished")
    }

    @Test func aPerformanceIsItselfInteraction() {
        var machine = makeMachine(
            sleepAfter: 3,
            initialPause: 0,
            performanceChance: 1.0,
            performances: ["mine"],
            performanceDurations: ["mine": 5]
        )

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .performing("mine"))

        advance(&machine, seconds: 4)
        #expect(machine.activity == .performing("mine"), "it should not doze off mid-swing")
    }

    @Test func aSecondPerformanceIsNotReplayedAsOneShot() {
        // Two different performances are different activities, so the machine moves between them.
        var machine = makeMachine(
            initialPause: 0,
            performanceChance: 1.0,
            performances: ["mine"],
            performanceDurations: ["mine": 0.2]
        )

        advance(&machine, seconds: 0.1)
        let firstTransition = machine.transitionCount

        advance(&machine, seconds: 0.5) // finish, idle for a moment, then choose again
        #expect(machine.transitionCount > firstTransition)
    }

    // MARK: Sleeping

    @Test func dozesOffAfterAQuietSpell() {
        var machine = makeMachine(sleepAfter: 30, initialPause: 100)

        advance(&machine, seconds: 29)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 2)
        #expect(machine.activity == .sleeping)
    }

    @Test func sleepingIsStickyAcrossTicks() {
        var machine = makeMachine(sleepAfter: 5, initialPause: 100)

        advance(&machine, seconds: 10)
        #expect(machine.activity == .sleeping)

        // Minutes later it is still asleep; only input wakes it.
        advance(&machine, seconds: 600)
        #expect(machine.activity == .sleeping)
    }

    @Test func aClickWakesThePet() {
        var machine = makeMachine(sleepAfter: 5, clickDuration: 0.5, initialPause: 100)
        advance(&machine, seconds: 10)
        #expect(machine.activity == .sleeping)

        machine.reactToClick()
        #expect(machine.activity == .showingClick)

        advance(&machine, seconds: 0.6)
        #expect(machine.activity == .idle)
    }

    @Test func aDragWakesThePet() {
        var machine = makeMachine(sleepAfter: 5, initialPause: 100)
        advance(&machine, seconds: 10)
        #expect(machine.activity == .sleeping)

        machine.beginDrag()
        #expect(machine.activity == .dragging)

        machine.endDrag()
        #expect(machine.activity == .idle)
    }

    @Test func wakingFromSleepGivesAFullQuietSpellAgain() {
        var machine = makeMachine(sleepAfter: 5, clickDuration: 0.5, initialPause: 100)

        advance(&machine, seconds: 10)
        #expect(machine.activity == .sleeping)

        machine.reactToClick()
        advance(&machine, seconds: 0.6)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 3)
        #expect(machine.activity == .idle, "the sleep clock restarted")

        advance(&machine, seconds: 3)
        #expect(machine.activity == .sleeping)
    }

    // MARK: Clicking

    @Test func clickReactionLastsForItsDuration() {
        var machine = makeMachine(clickDuration: 0.5, initialPause: 100)

        machine.reactToClick()
        #expect(machine.activity == .showingClick)

        advance(&machine, seconds: 0.4)
        #expect(machine.activity == .showingClick)

        advance(&machine, seconds: 0.2)
        #expect(machine.activity == .idle)
    }

    @Test func clickingAgainRestartsTheReaction() {
        var machine = makeMachine(clickDuration: 0.5, initialPause: 100)

        machine.reactToClick()
        advance(&machine, seconds: 0.4)
        #expect(machine.activity == .showingClick)

        // A second click before the first finishes must replay the animation. The caller detects
        // that through transitionCount, because the activity name does not change.
        let countBefore = machine.transitionCount
        machine.reactToClick()

        #expect(machine.activity == .showingClick)
        #expect(machine.transitionCount == countBefore + 1)

        advance(&machine, seconds: 0.4)
        #expect(machine.activity == .showingClick, "the reaction restarted from zero")
    }

    // MARK: Dragging

    @Test func draggingSuspendsEverythingUntilReleased() {
        var machine = makeMachine(sleepAfter: 2, initialPause: 0)

        machine.beginDrag()
        #expect(machine.activity == .dragging)

        advance(&machine, seconds: 60)
        #expect(machine.activity == .dragging)

        machine.endDrag()
        #expect(machine.activity == .idle)
    }

    @Test func droppingRestartsTheSleepClock() {
        var machine = makeMachine(sleepAfter: 5, initialPause: 0, minPause: 100, maxPause: 100)

        machine.beginDrag()
        advance(&machine, seconds: 60)
        machine.endDrag()

        advance(&machine, seconds: 3)
        #expect(machine.activity == .idle, "the drop should restart the sleep clock, not resume it")
    }

    // MARK: Held still (a menu is open)

    @Test func holdingStillStopsThePetFromSettingOff() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 10, holdStill: true)

        #expect(machine.activity == .idle)
        #expect(machine.walkTarget == nil)
    }

    @Test func holdingStillStillLetsAReactionPlayOut() {
        // With a menu open, clicking a sleeping pet used to leave it stuck on the sleep frame.
        var machine = makeMachine(clickDuration: 0.5)

        machine.reactToClick()
        #expect(machine.activity == .showingClick)

        advance(&machine, seconds: 0.4, holdStill: true)
        #expect(machine.activity == .showingClick, "still mid-reaction")

        advance(&machine, seconds: 0.2, holdStill: true)
        #expect(machine.activity == .idle, "the reaction finished even while held")
    }

    @Test func holdingStillEndsAMoveInProgress() {
        var machine = makeMachine(initialPause: 0, climbChance: 1.0)

        advance(&machine, seconds: 0.1, current: CGPoint(x: 400, y: 300), area: roomyArea)
        #expect(machine.activity == .climbing)

        // Staying in the climbing state while the caller is not moving us would be an animation of
        // a pet climbing in place.
        advance(&machine, seconds: 0.1, holdStill: true)
        #expect(machine.activity == .idle)
        #expect(machine.climbTargetY == nil)
    }

    @Test func aHeldPetResumesOnceReleased() {
        var machine = makeMachine(initialPause: 0, minPause: 1, maxPause: 1)

        advance(&machine, seconds: 10, holdStill: true)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 2)
        #expect(machine.activity == .walking)
    }

    // MARK: Tick hygiene

    @Test func nonPositiveOrNonFiniteDeltaTimeIsIgnored() {
        var machine = makeMachine(initialPause: 0)

        machine.tick(dt: 0, current: .zero, area: pointArea)
        machine.tick(dt: -1, current: .zero, area: pointArea)
        machine.tick(dt: .nan, current: .zero, area: pointArea)
        machine.tick(dt: .infinity, current: .zero, area: pointArea)

        #expect(machine.activity == .idle, "garbage deltas must not advance the machine")
    }

    @Test func everyActivityMapsOntoAKnownSkinState() {
        // A typo here would make the pet silently fall back to idle for that activity.
        for activity in PetActivity.representableCases {
            #expect(
                SkinManifest.knownStates.contains(activity.animationState),
                "\(activity) maps to unknown state \"\(activity.animationState)\""
            )
        }
    }

    @Test func theBehaviourPlanClampsNonsenseProbabilities() {
        let plan = BehaviorPlan(performanceChance: 5, climbChance: -2)

        #expect(plan.performanceChance == 1)
        #expect(plan.climbChance == 0)
    }

    @Test func tuningValuesAreClampedAgainstNonsense() {
        let machine = makeMachine(sleepAfter: -10, clickDuration: -1, initialPause: -5)

        #expect(machine.sleepAfter >= 1)
        #expect(machine.clickDuration > 0)
    }
}

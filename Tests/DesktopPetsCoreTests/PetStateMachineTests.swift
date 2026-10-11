import Testing
@testable import DesktopPetsCore

/// A degenerate but fully deterministic setup: a single-point walkable range means the target
/// never depends on the RNG.
private let pointRange: ClosedRange<Double> = 500...500
/// Ranges chosen so the target is always on one side of `currentX`, making facing deterministic.
private let rangeToTheLeft: ClosedRange<Double> = 0...999
private let rangeToTheRight: ClosedRange<Double> = 1...1000

@Suite struct PetStateMachineTests {
    func makeMachine(
        speed: Double = 100,
        sleepAfter: Double = 30,
        clickDuration: Double = 0.5,
        initialPause: Double = 1.5,
        minPause: Double = 2,
        maxPause: Double = 2
    ) -> PetStateMachine {
        PetStateMachine(
            walkPlan: WalkPlan(speed: speed, minPause: minPause, maxPause: maxPause, minTravel: 0),
            sleepAfter: sleepAfter,
            clickDuration: clickDuration,
            initialPause: initialPause
        )
    }

    /// Advances in small steps, the way the real 30Hz tick would.
    func advance(
        _ machine: inout PetStateMachine,
        seconds: Double,
        currentX: Double = 500,
        range: ClosedRange<Double> = pointRange,
        holdStill: Bool = false
    ) {
        let step = 1.0 / 30.0
        var elapsed = 0.0
        while elapsed < seconds {
            machine.tick(dt: step, currentX: currentX, walkableRange: range, holdStill: holdStill)
            elapsed += step
        }
    }

    // MARK: Startup

    @Test func startsIdleWithNoWalkTarget() {
        let machine = makeMachine()

        #expect(machine.activity == .idle)
        #expect(machine.walkTargetX == nil)
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

    @Test func walkTargetIsWithinTheWalkableRange() throws {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1, range: rangeToTheRight)

        let target = try #require(machine.walkTargetX)
        #expect(rangeToTheRight.contains(target))
    }

    @Test func facingTurnsTowardsTheTarget() {
        var walkingLeft = makeMachine(initialPause: 0)
        advance(&walkingLeft, seconds: 0.1, currentX: 1000, range: rangeToTheLeft)
        #expect(walkingLeft.activity == .walking)
        #expect(walkingLeft.facing == .left)

        var walkingRight = makeMachine(initialPause: 0)
        advance(&walkingRight, seconds: 0.1, currentX: 0, range: rangeToTheRight)
        #expect(walkingRight.activity == .walking)
        #expect(walkingRight.facing == .right)
    }

    @Test func arrivingReturnsToIdleAndClearsTheStaleTarget() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .walking)
        #expect(machine.walkTargetX != nil)

        machine.arrivedAtDestination()
        #expect(machine.activity == .idle)
        #expect(machine.walkTargetX == nil, "the stale target must not survive the walk")
    }

    @Test func arrivingRearsThePauseBeforeTheNextWalk() {
        var machine = makeMachine(initialPause: 0, minPause: 2, maxPause: 2)

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .walking)

        machine.arrivedAtDestination()
        #expect(machine.activity == .idle)

        // The 2s pause must be honoured before the next walk starts.
        advance(&machine, seconds: 1.0)
        #expect(machine.activity == .idle)
        advance(&machine, seconds: 1.5)
        #expect(machine.activity == .walking)
    }

    @Test func theTargetIsNotReRolledWhileStillWalking() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1)
        let firstTarget = machine.walkTargetX
        #expect(firstTarget != nil)

        advance(&machine, seconds: 0.5)
        #expect(machine.walkTargetX == firstTarget)
    }

    // MARK: Sleeping

    @Test func dozesOffAfterAQuietSpell() {
        var machine = makeMachine(sleepAfter: 30, initialPause: 100)

        advance(&machine, seconds: 29)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 2)
        #expect(machine.activity == .sleeping)
    }

    @Test func walkingDoesNotCountAsInteractionSoThePetStillDozes() {
        // Never let it arrive, and make the initial pause immediate.
        var machine = makeMachine(sleepAfter: 5, initialPause: 0)

        advance(&machine, seconds: 4)
        #expect(machine.activity == .walking, "still strolling")

        advance(&machine, seconds: 2)
        #expect(machine.activity == .sleeping, "autonomous walking must not reset the sleep clock")
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

        // The sleep clock restarted, so it does not immediately doze off again.
        advance(&machine, seconds: 3)
        #expect(machine.activity == .idle)

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

        advance(&machine, seconds: 0.2)
        #expect(machine.activity == .idle)
    }

    @Test func aReactionIsItselfInteraction() {
        var machine = makeMachine(sleepAfter: 3, clickDuration: 5, initialPause: 100)

        machine.reactToClick()
        advance(&machine, seconds: 4.5)
        #expect(machine.activity == .showingClick, "the pet should not fall asleep mid-reaction")
    }

    // MARK: Dragging

    @Test func draggingSuspendsEverythingUntilReleased() {
        var machine = makeMachine(sleepAfter: 2, initialPause: 0)

        machine.beginDrag()
        #expect(machine.activity == .dragging)

        // Held for far longer than the sleep timeout: it must stay in the drag state.
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

    // MARK: Tick hygiene

    @Test func nonPositiveOrNonFiniteDeltaTimeIsIgnored() {
        var machine = makeMachine(initialPause: 0)

        machine.tick(dt: 0, currentX: 500, walkableRange: pointRange)
        machine.tick(dt: -1, currentX: 500, walkableRange: pointRange)
        machine.tick(dt: .nan, currentX: 500, walkableRange: pointRange)
        machine.tick(dt: .infinity, currentX: 500, walkableRange: pointRange)

        #expect(machine.activity == .idle, "garbage deltas must not advance the machine")
    }

    @Test func everyActivityMapsOntoAKnownSkinState() {
        // A typo here would make the pet silently fall back to idle for that activity.
        for activity in PetActivity.allCases {
            #expect(
                SkinManifest.knownStates.contains(activity.animationState),
                "\(activity) maps to unknown state \"\(activity.animationState)\""
            )
        }
    }

    @Test func tuningValuesAreClampedAgainstNonsense() {
        let machine = makeMachine(sleepAfter: -10, clickDuration: -1, initialPause: -5)

        #expect(machine.sleepAfter >= 1)
        #expect(machine.clickDuration > 0)
    }

    // MARK: Held still (a menu is open)

    @Test func holdingStillStopsThePetFromStartingAWalk() {
        var machine = makeMachine(initialPause: 0)

        // Ten times longer than the initial pause, and it still should not set off.
        advance(&machine, seconds: 10, holdStill: true)

        #expect(machine.activity == .idle)
        #expect(machine.walkTargetX == nil)
    }

    @Test func holdingStillStillLetsAReactionPlayOut() {
        // The actual bug: with a menu open, clicking a sleeping pet left it stuck on the sleep
        // frame, because the whole tick was skipped. The reaction has to run to completion.
        var machine = makeMachine(clickDuration: 0.5, initialPause: 0)

        machine.reactToClick()
        #expect(machine.activity == .showingClick)

        advance(&machine, seconds: 0.4, holdStill: true)
        #expect(machine.activity == .showingClick, "still mid-reaction")

        advance(&machine, seconds: 0.2, holdStill: true)
        #expect(machine.activity == .idle, "the reaction finished even while held")
    }

    @Test func holdingStillEndsAWalkInProgress() {
        var machine = makeMachine(initialPause: 0)

        advance(&machine, seconds: 0.1)
        #expect(machine.activity == .walking)

        // The caller stops moving us, so staying in the walking state would just be an animation of
        // a pet marching on the spot.
        advance(&machine, seconds: 0.1, holdStill: true)
        #expect(machine.activity == .idle)
        #expect(machine.walkTargetX == nil)
    }

    @Test func holdingStillStillAllowsDozeOff() {
        // Being held is not interaction, so a menu left open long enough still ends in a nap.
        var machine = makeMachine(sleepAfter: 5, initialPause: 100)

        advance(&machine, seconds: 3, holdStill: true)
        #expect(machine.activity == .idle)

        advance(&machine, seconds: 3, holdStill: true)
        #expect(machine.activity == .sleeping)
    }

    @Test func aHeldPetResumesWalkingOnceReleased() {
        var machine = makeMachine(initialPause: 0, minPause: 1, maxPause: 1)

        advance(&machine, seconds: 10, holdStill: true)
        #expect(machine.activity == .idle)

        // Release: it should pick up again rather than staying stuck.
        advance(&machine, seconds: 2)
        #expect(machine.activity == .walking)
    }

    @Test func holdStillDefaultsToOff() {
        // Every caller that does not pass the flag keeps the old behaviour.
        var machine = makeMachine(initialPause: 0)
        machine.tick(dt: 0.1, currentX: 500, walkableRange: pointRange)
        #expect(machine.activity == .walking)
    }
}

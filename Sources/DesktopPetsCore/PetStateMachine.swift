import Foundation

/// What the pet is doing right now. Each case maps onto one animation state by name.
public enum PetActivity: Equatable, CaseIterable {
    case idle
    case walking
    case dragging
    case sleeping
    case showingClick

    /// The `skin.json` state name that animates this activity.
    ///
    /// Always one of `SkinManifest.knownStates`; a test pins that down, because a typo here would
    /// make the pet silently fall back to idle.
    public var animationState: String {
        switch self {
        case .idle: return "idle"
        case .walking: return "walk"
        case .dragging: return "drag"
        case .sleeping: return "sleep"
        case .showingClick: return "click"
        }
    }
}

/// Decides when the pet changes activity: idle -> walk -> idle, doze off after a quiet spell, and
/// react to being clicked or dragged.
///
/// Deliberately owns no position and no AppKit state. It decides *when* and *where to walk*; the
/// caller integrates the movement and reports back when the destination is reached. Time is an
/// explicit input, which keeps every transition in one readable, testable place.
public struct PetStateMachine {
    /// Autonomous movement tuning.
    public var walkPlan: WalkPlan
    /// Quiet spell before the pet lies down. Only user interaction resets this.
    public var sleepAfter: Double
    /// How long the one-shot click reaction plays before returning to idle.
    public var clickDuration: Double

    public private(set) var activity: PetActivity = .idle
    public private(set) var facing: Facing = .right

    /// Where the current walk is headed, or nil when not walking. Kept beside `activity` rather
    /// than as an associated value so `PetActivity` stays a simple, comparable enum.
    public private(set) var walkTargetX: Double?

    /// Increments on every transition, including re-entering the same activity. Callers use this
    /// to replay one-shot animations, so a second click restarts the reaction instead of being
    /// swallowed by "same state, nothing to do".
    public private(set) var transitionCount: Int = 0

    private var timeInState: Double = 0
    private var timeSinceInteraction: Double = 0
    private var timeUntilNextWalk: Double
    private var rng = SystemRandomNumberGenerator()

    public init(
        walkPlan: WalkPlan,
        sleepAfter: Double,
        clickDuration: Double,
        initialPause: Double = 1.5
    ) {
        self.walkPlan = walkPlan
        // Guard the tuning values so a bad config cannot make the pet sleep instantly or restart
        // its click animation every tick.
        self.sleepAfter = max(1, sleepAfter)
        self.clickDuration = max(0.05, clickDuration)
        self.timeUntilNextWalk = max(0, initialPause)
    }

    // MARK: User interaction

    /// Called once the mouse has moved far enough to count as a drag.
    public mutating func beginDrag() {
        transition(to: .dragging)
    }

    /// Called when the mouse is released. The machine does not track position itself; the caller
    /// reads the settled position straight off the window.
    public mutating func endDrag() {
        transition(to: .idle)
        timeSinceInteraction = 0
        timeUntilNextWalk = walkPlan.pause(using: &rng)
    }

    /// A click that never became a drag.
    public mutating func reactToClick() {
        transition(to: .showingClick)
        timeSinceInteraction = 0
    }

    /// The caller reports that the walk destination was actually reached.
    public mutating func arrivedAtDestination() {
        enterIdle()
    }

    // MARK: Time

    @discardableResult
    public mutating func tick(
        dt: Double,
        currentX: Double,
        walkableRange: ClosedRange<Double>
    ) -> PetActivity {
        guard dt > 0, dt.isFinite else { return activity }
        timeInState += dt

        switch activity {
        case .dragging:
            // The user is holding the pet; it never dozes off mid-drag.
            return activity

        case .showingClick:
            // Reacting is itself interaction, so the sleep clock stays at zero.
            timeSinceInteraction = 0
            if timeInState >= clickDuration { enterIdle() }
            return activity

        case .sleeping:
            // Nothing wakes it but input; that is handled by the interaction methods.
            return activity

        case .idle:
            timeSinceInteraction += dt
            if timeSinceInteraction >= sleepAfter {
                enterSleep()
            } else {
                timeUntilNextWalk -= dt
                if timeUntilNextWalk <= 0 {
                    enterWalk(currentX: currentX, walkableRange: walkableRange)
                }
            }
            return activity

        case .walking:
            // Walking is autonomous, so it does not count as interaction: a pet left alone long
            // enough still lies down, even mid-stroll.
            timeSinceInteraction += dt
            if timeSinceInteraction >= sleepAfter { enterSleep() }
            return activity
        }
    }

    // MARK: Transitions

    private mutating func enterWalk(currentX: Double, walkableRange: ClosedRange<Double>) {
        let target = walkPlan.chooseTarget(in: walkableRange, from: currentX, using: &rng)
        facing = Facing(fromX: currentX, toX: target)
        // Arm the next pause now, so it is already decided when this walk ends.
        timeUntilNextWalk = walkPlan.pause(using: &rng)
        transition(to: .walking, walkTarget: target)
    }

    private mutating func enterIdle() {
        transition(to: .idle)
        if timeUntilNextWalk <= 0 {
            timeUntilNextWalk = walkPlan.pause(using: &rng)
        }
    }

    private mutating func enterSleep() {
        transition(to: .sleeping)
    }

    private mutating func transition(to newActivity: PetActivity, walkTarget: Double? = nil) {
        activity = newActivity
        walkTargetX = walkTarget
        timeInState = 0
        transitionCount += 1
    }
}

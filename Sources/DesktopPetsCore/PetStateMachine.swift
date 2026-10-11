import CoreGraphics
import Foundation

/// What the pet is doing right now. Each case maps onto one animation state by name.
public enum PetActivity: Equatable {
    case idle
    case walking
    case climbing
    case dragging
    case sleeping
    case showingClick
    /// A one-shot performance — `mine`, `fight`, `tnt`. The payload is the skin's state name, so
    /// adding another performance needs a name and art, not a new enum case.
    case performing(String)

    /// The `skin.json` state name that animates this activity.
    ///
    /// Always one of `SkinManifest.knownStates`; a test pins that down, because a typo here would
    /// make the pet silently fall back to idle.
    public var animationState: String {
        switch self {
        case .idle: return "idle"
        case .walking: return "walk"
        case .climbing: return "climb"
        case .dragging: return "drag"
        case .sleeping: return "sleep"
        case .showingClick: return "click"
        case .performing(let state): return state
        }
    }

    /// One representative of every shape this enum can take, for coverage checks. The payload case
    /// cannot be `CaseIterable`.
    public static var representableCases: [PetActivity] {
        [.idle, .walking, .climbing, .dragging, .sleeping, .showingClick, .performing("mine")]
    }
}

/// How often the pet does something other than walk, and what it may do instead.
public struct BehaviorPlan: Equatable {
    /// Chance that the next thing the pet does is a performance rather than a walk.
    public var performanceChance: Double
    /// Chance that a walk is replaced by a climb to a different height.
    public var climbChance: Double
    /// Skin states the pet may perform. Filtered at runtime to those the skin actually provides.
    public var performances: [String]

    public init(
        performanceChance: Double = 0.35,
        climbChance: Double = 0.25,
        performances: [String] = ["mine", "fight", "tnt"]
    ) {
        self.performanceChance = Swift.min(Swift.max(performanceChance, 0), 1)
        self.climbChance = Swift.min(Swift.max(climbChance, 0), 1)
        self.performances = performances
    }
}

/// Decides when the pet changes activity: idle -> walk -> idle, climb to another height, put on a
/// performance, doze off after a quiet spell, and react to being clicked or dragged.
///
/// Deliberately owns no position and no AppKit state. It decides *where* to go; the caller
/// integrates the movement each tick and reports back when the destination is reached. Time and the
/// current position are explicit inputs, which keeps every transition in one readable, testable
/// place.
public struct PetStateMachine {
    /// Movement tuning.
    public var walkPlan: WalkPlan
    /// What the pet may do on a whim.
    public var behavior: BehaviorPlan
    /// Quiet spell before the pet lies down. Only user interaction resets this.
    public var sleepAfter: Double
    /// How long the one-shot click reaction plays before returning to idle.
    public var clickDuration: Double
    /// How long each performance plays, taken from the skin's frame counts and frame rates.
    public var performanceDurations: [String: Double]

    /// Which states the skin can actually animate.
    ///
    /// `nil` means "assume the skin has everything", which is what a pure-logic caller wants. The
    /// app passes the real set, so the pet never plays a state it has no art for: a climb without
    /// climbing frames would slide the pet up a ladder in its idle pose.
    public var animatableStates: Set<String>?

    public private(set) var activity: PetActivity = .idle
    public private(set) var facing: Facing = .right

    /// Where the current walk is headed, or nil when not walking.
    public private(set) var walkTarget: CGPoint?
    /// The height the current climb is headed for, or nil when not climbing.
    public private(set) var climbTargetY: Double?

    /// Increments on every transition, including re-entering the same activity. Callers use this
    /// to replay one-shot animations, so a second click restarts the reaction instead of being
    /// swallowed by "same state, nothing to do".
    public private(set) var transitionCount: Int = 0

    private var timeInState: Double = 0
    private var timeSinceInteraction: Double = 0
    private var timeUntilNextActivity: Double
    private var rng = SystemRandomNumberGenerator()

    public init(
        walkPlan: WalkPlan,
        behavior: BehaviorPlan = BehaviorPlan(),
        sleepAfter: Double,
        clickDuration: Double,
        animatableStates: Set<String>? = nil,
        performanceDurations: [String: Double] = [:],
        initialPause: Double = 1.5
    ) {
        self.walkPlan = walkPlan
        self.behavior = behavior
        self.sleepAfter = max(1, sleepAfter)
        self.clickDuration = max(0.05, clickDuration)
        self.animatableStates = animatableStates
        self.performanceDurations = performanceDurations
        self.timeUntilNextActivity = max(0, initialPause)
    }

    /// Performances the skin can actually animate. A performance with no art would show up as the
    /// pet falling back to idle mid-swing, so those are dropped rather than attempted.
    private var availablePerformances: [String] {
        behavior.performances.filter { name in
            (performanceDurations[name] ?? 0) > 0 && (animatableStates?.contains(name) ?? true)
        }
    }

    /// Whether a climb is worth attempting. Same reasoning as the performances: a pet that cannot
    /// animate climbing would slide up the ladder in whatever pose it was already in.
    private var canClimb: Bool {
        animatableStates?.contains("climb") ?? true
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
        timeUntilNextActivity = walkPlan.pause(using: &rng)
    }

    /// A click that never became a drag.
    public mutating func reactToClick() {
        transition(to: .showingClick)
        timeSinceInteraction = 0
    }

    /// The caller reports that the walk or climb destination was actually reached.
    public mutating func arrivedAtDestination() {
        enterIdle()
    }

    // MARK: Time

    @discardableResult
    public mutating func tick(
        dt: Double,
        current: CGPoint,
        area: CGRect,
        holdStill: Bool = false
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

        case .performing(let name):
            // Putting on a show is deliberate, so the pet does not doze off half way through one.
            timeSinceInteraction = 0
            if timeInState >= (performanceDurations[name] ?? 0) { enterIdle() }
            return activity

        case .sleeping:
            // Nothing wakes it but input; that is handled by the interaction methods.
            return activity

        case .idle:
            timeSinceInteraction += dt
            if timeSinceInteraction >= sleepAfter {
                enterSleep()
            } else if !holdStill {
                timeUntilNextActivity -= dt
                if timeUntilNextActivity <= 0 {
                    chooseNextActivity(current: current, area: area)
                }
            }
            return activity

        case .walking, .climbing:
            // Wandering is autonomous, so it does not count as interaction: a pet left alone long
            // enough still lies down, even mid-stroll.
            timeSinceInteraction += dt
            if timeSinceInteraction >= sleepAfter {
                enterSleep()
            } else if holdStill {
                // Don't keep going when the caller is not moving us.
                enterIdle()
            }
            return activity
        }
    }

    // MARK: Choosing what to do

    private mutating func chooseNextActivity(current: CGPoint, area: CGRect) {
        let available = availablePerformances
        if !available.isEmpty,
           Double.random(in: 0..<1, using: &rng) < behavior.performanceChance,
           let name = available.randomElement(using: &rng) {
            // Arm the next pause now, so it is already decided when this finishes.
            timeUntilNextActivity = walkPlan.pause(using: &rng)
            transition(to: .performing(name))
            return
        }

        if canClimb,
           Double.random(in: 0..<1, using: &rng) < behavior.climbChance,
           let targetY = walkPlan.chooseClimbTarget(in: area, from: current.y, using: &rng) {
            timeUntilNextActivity = walkPlan.pause(using: &rng)
            transition(to: .climbing, climbTargetY: targetY)
            return
        }

        let target = walkPlan.chooseWalkTarget(in: area, from: current, using: &rng)
        facing = Facing(fromX: current.x, toX: target.x)
        timeUntilNextActivity = walkPlan.pause(using: &rng)
        transition(to: .walking, walkTarget: target)
    }

    // MARK: Transitions

    private mutating func enterIdle() {
        transition(to: .idle)
        if timeUntilNextActivity <= 0 {
            timeUntilNextActivity = walkPlan.pause(using: &rng)
        }
    }

    private mutating func enterSleep() {
        transition(to: .sleeping)
    }

    private mutating func transition(
        to newActivity: PetActivity,
        walkTarget: CGPoint? = nil,
        climbTargetY: Double? = nil
    ) {
        activity = newActivity
        self.walkTarget = walkTarget
        self.climbTargetY = climbTargetY
        timeInState = 0
        transitionCount += 1
    }
}

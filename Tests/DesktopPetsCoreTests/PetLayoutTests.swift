import CoreGraphics
import Testing
@testable import DesktopPetsCore

@Suite struct PetLayoutTests {
    let size = CGSize(width: 64, height: 64)
    let position = CGPoint(x: 500, y: 100)

    // MARK: anchor -> origin

    @Test func bottomCenterAnchorPutsFeetAtPosition() {
        let origin = PetLayout.windowOrigin(anchor: .bottomCenter, size: size, position: position)
        #expect(origin.x == 468) // 500 - 64/2
        #expect(origin.y == 100) // feet on the position
    }

    @Test func everyAnchorTranslatesThePositionCorrectly() {
        let cases: [(Anchor, CGPoint)] = [
            (.center, CGPoint(x: 468, y: 68)),
            (.bottomCenter, CGPoint(x: 468, y: 100)),
            (.topCenter, CGPoint(x: 468, y: 36)),
            (.bottomLeft, CGPoint(x: 500, y: 100)),
            (.bottomRight, CGPoint(x: 436, y: 100)),
            (.topLeft, CGPoint(x: 500, y: 36)),
            (.topRight, CGPoint(x: 436, y: 36)),
        ]

        // Every case in Anchor must be covered, otherwise this test silently stops testing.
        #expect(Set(cases.map { $0.0 }) == Set(Anchor.allCases))

        for (anchor, expected) in cases {
            let origin = PetLayout.windowOrigin(anchor: anchor, size: size, position: position)
            #expect(abs(origin.x - expected.x) <= 0.0001, "x for \(anchor)")
            #expect(abs(origin.y - expected.y) <= 0.0001, "y for \(anchor)")
        }
    }

    @Test func hotspotIsTheExactInverseOfWindowOrigin() {
        for anchor in Anchor.allCases {
            let origin = PetLayout.windowOrigin(anchor: anchor, size: size, position: position)
            let recovered = PetLayout.hotspot(anchor: anchor, size: size, origin: origin)
            #expect(abs(recovered.x - position.x) <= 0.0001, "x for \(anchor)")
            #expect(abs(recovered.y - position.y) <= 0.0001, "y for \(anchor)")
        }
    }

    @Test func windowSizeAppliesScaleAndRounds() {
        #expect(PetLayout.windowSize(spriteSize: CGSize(width: 64, height: 64), scale: 1)
            == CGSize(width: 64, height: 64))
        #expect(PetLayout.windowSize(spriteSize: CGSize(width: 64, height: 64), scale: 2)
            == CGSize(width: 128, height: 128))
        // A nonsensical scale falls back to 1 rather than producing a zero-size window.
        #expect(PetLayout.windowSize(spriteSize: CGSize(width: 33, height: 33), scale: 0)
            == CGSize(width: 33, height: 33))
    }

    // MARK: clamp

    @Test func clampLeavesAnInteriorWindowAlone() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let origin = CGPoint(x: 400, y: 300)
        #expect(PetLayout.clamp(origin, size: size, into: frame) == origin)
    }

    @Test func clampPullsBackFromEachEdge() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)

        // Past the left edge.
        #expect(PetLayout.clamp(CGPoint(x: 0, y: 300), size: size, into: frame).x == 100)
        // Past the right edge (frame.maxX - width = 1100 - 64 = 1036).
        #expect(PetLayout.clamp(CGPoint(x: 5000, y: 300), size: size, into: frame).x == 1036)
        // Past the bottom edge.
        #expect(PetLayout.clamp(CGPoint(x: 400, y: -500), size: size, into: frame).y == 50)
        // Past the top edge (frame.maxY - height = 850 - 64 = 786).
        #expect(PetLayout.clamp(CGPoint(x: 400, y: 5000), size: size, into: frame).y == 786)
    }

    @Test func clampHandlesAWindowLargerThanTheScreen() {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        let clamped = PetLayout.clamp(CGPoint(x: 999, y: 999), size: size, into: frame)

        // Pinned to the frame's lower corner instead of an inverted range.
        #expect(clamped.x == 0)
        #expect(clamped.y == 0)
    }

    @Test func clampHandlesANegativeOriginFrame() {
        // A screen positioned to the left of / below the primary one.
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let clamped = PetLayout.clamp(CGPoint(x: -3000, y: 5000), size: size, into: frame)

        #expect(clamped.x == -1920)
        // Compare against a typed value, not inline arithmetic: Swift Testing captures each side
        // of the comparison independently, so `clamped.y == -200 + 1080 - 64` loses the CGFloat
        // context, infers Int for the right-hand side and evaluates to false for equal numbers.
        let expectedY = frame.maxY - size.height
        #expect(clamped.y == expectedY)
    }

    @Test func isFullyVisible() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        #expect(PetLayout.isFullyVisible(origin: CGPoint(x: 100, y: 100), size: size, in: frame))
        // Flush against every edge is still fully visible.
        #expect(PetLayout.isFullyVisible(origin: CGPoint(x: 0, y: 0), size: size, in: frame))
        #expect(PetLayout.isFullyVisible(origin: CGPoint(x: 936, y: 736), size: size, in: frame))
        // One point off the right edge.
        #expect(!PetLayout.isFullyVisible(origin: CGPoint(x: 937, y: 100), size: size, in: frame))
        #expect(!PetLayout.isFullyVisible(origin: CGPoint(x: 100, y: -1), size: size, in: frame))
    }

    // MARK: Screen selection

    let primary = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        isMain: true
    )
    let secondary = ScreenInfo(
        frame: CGRect(x: 1920, y: 0, width: 1280, height: 800),
        visibleFrame: CGRect(x: 1920, y: 0, width: 1280, height: 800),
        isMain: false
    )

    @Test func activeScreenPrefersTheOneContainingThePoint() {
        let screens = [primary, secondary]

        #expect(ScreenSelector.activeScreen(for: CGPoint(x: 100, y: 100), screens: screens) == primary)
        #expect(ScreenSelector.activeScreen(for: CGPoint(x: 2500, y: 400), screens: screens) == secondary)
        // Inside the primary's frame but behind the menu bar: still the primary.
        #expect(ScreenSelector.activeScreen(for: CGPoint(x: 900, y: 1070), screens: screens) == primary)
    }

    @Test func activeScreenFallsBackToTheNearestWhenOffAllScreens() {
        let screens = [primary, secondary]

        // Far to the right of everything -> the secondary.
        #expect(ScreenSelector.activeScreen(for: CGPoint(x: 9999, y: 400), screens: screens) == secondary)
        // Far to the left -> the primary.
        #expect(ScreenSelector.activeScreen(for: CGPoint(x: -9999, y: 400), screens: screens) == primary)
    }

    @Test func activeScreenBreaksTiesInFavourOfMain() {
        // Two screens equally far from the point; the main one must win.
        let left = ScreenInfo(frame: CGRect(x: -500, y: 0, width: 100, height: 100), isMain: false)
        let right = ScreenInfo(frame: CGRect(x: 400, y: 0, width: 100, height: 100), isMain: true)

        #expect(ScreenSelector.activeScreen(for: CGPoint(x: 0, y: 0), screens: [left, right]) == right)
    }

    @Test func activeScreenReturnsNilForNoScreens() {
        #expect(ScreenSelector.activeScreen(for: .zero, screens: []) == nil)
        #expect(ScreenSelector.mainScreen(in: []) == nil)
    }

    @Test func mainScreenPrefersTheFlaggedScreen() {
        #expect(ScreenSelector.mainScreen(in: [secondary, primary]) == primary)

        // No screen flagged main: fall back to the first rather than nothing.
        let unflagged = [
            ScreenInfo(frame: CGRect(x: 0, y: 0, width: 10, height: 10), isMain: false),
            ScreenInfo(frame: CGRect(x: 20, y: 0, width: 10, height: 10), isMain: false),
        ]
        #expect(ScreenSelector.mainScreen(in: unflagged) == unflagged[0])
    }

    @Test func squaredDistanceIsZeroInsideAndGrowsOutside() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(ScreenSelector.squaredDistance(from: CGPoint(x: 50, y: 50), to: rect) == 0)
        #expect(ScreenSelector.squaredDistance(from: CGPoint(x: 103, y: 50), to: rect) == 9)
        #expect(ScreenSelector.squaredDistance(from: CGPoint(x: 103, y: 104), to: rect) == 9 + 16)
    }
}

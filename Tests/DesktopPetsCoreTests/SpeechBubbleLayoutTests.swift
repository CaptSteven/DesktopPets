import CoreGraphics
import Testing
@testable import DesktopPetsCore

@Suite struct SpeechBubbleLayoutTests {
    /// A typical laptop screen with a menu bar, so `visibleFrame` is shorter than `frame`.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let bubble = CGSize(width: 120, height: 40)

    /// A pet standing near the bottom centre, 128x128 (matching the placeholder skin).
    let groundPet = CGRect(x: 656, y: 24, width: 128, height: 128)

    @Test func sitsAboveThePetCentredOnIt() {
        let origin = SpeechBubbleLayout.origin(size: bubble, above: groundPet, within: screen)

        // Centred: pet midX 720, bubble half-width 60 -> x 660.
        #expect(origin.x == 660)
        // Just above the pet's top edge (24 + 128 = 152), plus the 4pt gap.
        #expect(origin.y == 156)
    }

    @Test func isPulledInsideTheLeftEdge() {
        let petAtLeftEdge = CGRect(x: 0, y: 24, width: 128, height: 128)
        let origin = SpeechBubbleLayout.origin(size: bubble, above: petAtLeftEdge, within: screen)

        #expect(origin.x == 4, "must not hang off the left of the screen")
    }

    @Test func isPulledInsideTheRightEdge() {
        let petAtRightEdge = CGRect(x: screen.maxX - 128, y: 24, width: 128, height: 128)
        let origin = SpeechBubbleLayout.origin(size: bubble, above: petAtRightEdge, within: screen)

        // maxX - width - margin = 1440 - 120 - 4
        #expect(origin.x == 1316)
    }

    @Test func flipsBelowThePetWhenThereIsNoRoomAbove() {
        // Pet perched at the very top of the visible area.
        let petAtTop = CGRect(x: 656, y: screen.maxY - 128, width: 128, height: 128)
        let origin = SpeechBubbleLayout.origin(size: bubble, above: petAtTop, within: screen)

        // Above would be 875 + 4, well past the top; so it goes below the pet instead.
        #expect(origin.y == petAtTop.minY - 4 - bubble.height)
        #expect(origin.y + bubble.height <= screen.maxY)
    }

    @Test func neverEscapesTheVisibleFrameVertically() {
        for petY in stride(from: 0.0, through: screen.maxY - 128, by: 40) {
            let pet = CGRect(x: 656, y: petY, width: 128, height: 128)
            let origin = SpeechBubbleLayout.origin(size: bubble, above: pet, within: screen)

            #expect(origin.y >= screen.minY, "pet at y=\(petY) pushed the bubble below the screen")
            #expect(origin.y + bubble.height <= screen.maxY,
                    "pet at y=\(petY) pushed the bubble above the screen")
        }
    }

    @Test func handlesAScreenWithANegativeOrigin() {
        // A second display positioned to the left of the primary one.
        let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let pet = CGRect(x: -1920, y: 40, width: 128, height: 128)

        let origin = SpeechBubbleLayout.origin(size: bubble, above: pet, within: leftScreen)

        // Typed explicitly: `origin.x == -1920 + 4` would infer Int on the right and compare
        // unequal for equal numbers. See the note at the top of TestSupport.swift.
        let expectedX: CGFloat = -1920 + 4
        #expect(origin.x == expectedX)
        #expect(origin.y == 172)
    }

    @Test func collapsesGracefullyWhenTheBubbleIsWiderThanTheScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 60, height: 60)
        let huge = CGSize(width: 200, height: 40)

        let origin = SpeechBubbleLayout.origin(size: huge, above: tiny, within: tiny)

        // Pinned to the lower-left margin rather than producing an inverted range or a NaN.
        #expect(origin.x == 4)
        #expect(origin.y >= 4)
    }
}

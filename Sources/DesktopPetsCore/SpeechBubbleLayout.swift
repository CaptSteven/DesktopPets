import CoreGraphics

/// Placement maths for the speech bubble.
///
/// Lives in Core with the rest of the layout code because it is pure geometry with a couple of
/// easy-to-get-wrong cases: a pet near the left or right edge, and a pet near the top of the
/// screen where there is no room above it.
public enum SpeechBubbleLayout {
    /// Where to place a bubble of `size` so it sits above `petFrame`, centred on the pet and
    /// inside `visibleFrame`.
    ///
    /// Flips below the pet when there is not enough room above, so the bubble never runs off the
    /// top of the display.
    public static func origin(
        size: CGSize,
        above petFrame: CGRect,
        within visibleFrame: CGRect,
        gap: Double = 4,
        margin: Double = 4
    ) -> CGPoint {
        let x = clampScalar(
            petFrame.midX - size.width / 2,
            lower: visibleFrame.minX + margin,
            upper: visibleFrame.maxX - size.width - margin
        )

        var y = petFrame.maxY + gap
        if y + size.height > visibleFrame.maxY - margin {
            // No room above: drop below the pet instead.
            y = petFrame.minY - gap - size.height
        }

        return CGPoint(
            x: x,
            y: clampScalar(
                y,
                lower: visibleFrame.minY + margin,
                upper: visibleFrame.maxY - size.height - margin
            )
        )
    }

    /// Clamps, collapsing to `lower` when the range is inverted — which happens when the bubble is
    /// taller or wider than the space available.
    private static func clampScalar(_ value: Double, lower: Double, upper: Double) -> Double {
        let effectiveUpper = Swift.max(upper, lower)
        return Swift.min(Swift.max(value, lower), effectiveUpper)
    }
}

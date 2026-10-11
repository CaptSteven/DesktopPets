import AppKit

/// Draws a ladder tall enough to fill whatever it is given: two rails and evenly spaced rungs.
///
/// Drawn rather than loaded because a climb can be any height. Art would need one image per
/// possible distance, or tiling that shows seams.
final class LadderView: NSView {
    private static let railWidth: CGFloat = 3
    private static let rungSpacing: CGFloat = 13
    private static let rungHeight: CGFloat = 3

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        let wood = NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.24, alpha: 0.92)
        let edge = NSColor(calibratedRed: 0.44, green: 0.29, blue: 0.16, alpha: 0.95)

        // Rails down each side.
        for x in [bounds.minX, bounds.maxX - Self.railWidth] {
            let rail = CGRect(x: x, y: bounds.minY, width: Self.railWidth, height: bounds.height)
            context.setFillColor(wood.cgColor)
            context.fill(rail)
            context.setFillColor(edge.cgColor)
            context.fill(CGRect(x: rail.minX, y: rail.minY, width: 1, height: rail.height))
        }

        // Rungs, laid out from the bottom so they stay put when the window is resized.
        context.setFillColor(wood.cgColor)
        var y = bounds.minY + Self.rungSpacing
        while y < bounds.maxY - Self.rungHeight {
            context.fill(CGRect(
                x: bounds.minX,
                y: y,
                width: bounds.width,
                height: Self.rungHeight
            ))
            y += Self.rungSpacing
        }
    }
}

/// The ladder the pet climbs.
///
/// A separate window rather than part of the pet's own frames: a ladder has to stay put while the
/// pet moves up it. Drawn inside the sprite it would slide upward with the pet, which reads as the
/// pet carrying the ladder rather than climbing it.
final class LadderWindow: NSWindow {
    /// How much wider than the pet the ladder is. Narrower would be hidden behind it.
    private static let widthFactor: CGFloat = 0.62

    private let ladderView = LadderView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        // Purely scenery: it must never intercept a click meant for the pet or anything else.
        ignoresMouseEvents = true
        contentView = ladderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows a ladder reaching from `fromY` to `toY`, centred on `centreX`.
    func show(from fromY: CGFloat, to toY: CGFloat, centreX: CGFloat, petWidth: CGFloat, behind petWindow: NSWindow) {
        let width = max(8, (petWidth * Self.widthFactor).rounded())
        let bottom = min(fromY, toY)
        // A few points of overhang at each end, so the ladder looks planted rather than floating.
        let overhang: CGFloat = 10
        let height = abs(toY - fromY) + overhang * 2
        let origin = CGPoint(
            x: (centreX - width / 2).rounded(),
            y: (bottom - overhang).rounded()
        )

        let target = CGRect(origin: origin, size: CGSize(width: width, height: height))
        if frame != target { setFrame(target, display: true) }
        ladderView.needsDisplay = true

        if !isVisible {
            orderFrontRegardless()
            // Behind the pet, so the pet reads as being on the ladder rather than beside it.
            order(.below, relativeTo: petWindow.windowNumber)
        }
    }

    func hide() {
        orderOut(nil)
    }
}

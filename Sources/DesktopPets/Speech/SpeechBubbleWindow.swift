import AppKit
import DesktopPetsCore

/// Draws a rounded bubble with a tail pointing down at the pet.
///
/// The view is flipped, which is the natural coordinate system for laying out text.
final class SpeechBubbleView: NSView {
    static let tailHeight: CGFloat = 7
    static let cornerRadius: CGFloat = 9
    static let textInset: CGFloat = 8
    static let maxTextWidth: CGFloat = 200
    static let minWidth: CGFloat = 44

    private static let tailWidth: CGFloat = 14

    var text: String = "" {
        didSet {
            if text != oldValue { needsDisplay = true }
        }
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    // MARK: Sizing

    static func attributedString(for text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
    }

    /// Fitting size for `text`, capped at ``maxTextWidth`` so long phrases wrap instead of
    /// stretching across the screen.
    static func size(for text: String) -> CGSize {
        let attributed = attributedString(for: text)
        let measured = attributed.boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let width = max(minWidth, ceil(measured.width) + textInset * 2)
        let height = ceil(measured.height) + textInset * 2 + tailHeight
        return CGSize(width: width, height: height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !text.isEmpty else { return }

        context.clear(bounds)
        let body = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - Self.tailHeight)
        )

        // Body and tail as one filled shape, so there is no seam where they meet. No stroke: an
        // outline would draw a line straight across that join. The window's own shadow gives the
        // bubble its edge instead.
        let path = CGMutablePath()
        path.addRoundedRect(
            in: body,
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius
        )

        let tailCentreX = bounds.midX
        let tailLeft = tailCentreX - Self.tailWidth / 2
        path.move(to: CGPoint(x: tailLeft, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: tailCentreX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: tailLeft + Self.tailWidth, y: body.maxY - 1))
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor)
        context.fillPath()

        Self.attributedString(for: text).draw(
            with: body.insetBy(dx: Self.textInset, dy: Self.textInset),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }
}

/// The bubble's window: decoration only, floating above the pet.
final class SpeechBubbleWindow: NSWindow {
    private let bubbleView = SpeechBubbleView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        // A soft shadow is what separates the bubble from a busy wallpaper.
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        // Purely decorative: clicks belong to whatever is behind the bubble.
        ignoresMouseEvents = true
        alphaValue = 0
        contentView = bubbleView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sizes, places and shows the bubble above `petFrame`. `alpha` drives the fade.
    func present(text: String, above petFrame: CGRect, within visibleFrame: CGRect, alpha: CGFloat) {
        let size = SpeechBubbleView.size(for: text)
        let target = origin(above: petFrame, size: size, within: visibleFrame)

        if bubbleView.text != text { bubbleView.text = text }
        if frame.size != size { setContentSize(size) }
        if frame.origin != target { setFrameOrigin(target) }

        alphaValue = alpha
        if !isVisible { orderFrontRegardless() }
    }

    func dismiss() {
        alphaValue = 0
        orderOut(nil)
    }

    /// Sits just above the pet, centred on it, pulled inside the screen. Flips below the pet when
    /// there is no room above, so the bubble never runs off the top of the display.
    private func origin(above petFrame: CGRect, size: CGSize, within visibleFrame: CGRect) -> CGPoint {
        SpeechBubbleLayout.origin(size: size, above: petFrame, within: visibleFrame)
    }
}

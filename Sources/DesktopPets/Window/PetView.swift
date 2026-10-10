import AppKit
import DesktopPetsCore

/// Draws the current sprite frame and turns mouse gestures into pet reactions.
///
/// The view moves its own window during a drag; deciding what that *means* (switching to the drag
/// animation, saving the new position) is left to the callbacks.
final class PetView: NSView {
    /// How far the mouse must move before a press counts as a drag rather than a click.
    private static let dragThreshold: CGFloat = 3

    var frameImage: CGImage? {
        didSet { needsDisplay = true }
    }

    var facing: Facing = .right {
        didSet {
            if facing != oldValue { needsDisplay = true }
        }
    }

    /// A press that never became a drag. The event is passed on so the menu can be popped up where
    /// the user actually clicked.
    var onLeftClick: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStartMouse: CGPoint?
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isDragging = false

    override var isOpaque: Bool { false }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let frameImage, let context = NSGraphicsContext.current?.cgContext else { return }

        context.clear(bounds)

        context.saveGState()
        // Pixel art: never smooth the sprite, or the pixels turn to mush when scaled up.
        context.interpolationQuality = .none
        if facing.isFlipped {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(frameImage, in: bounds)
        context.restoreGState()
    }

    // MARK: Mouse

    /// Without this, the first click on the window of an inactive app only activates it and never
    /// reaches the view — so the pet would appear to swallow the first click of every interaction.
    /// An accessory app is inactive almost all the time, which would make that most clicks.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        Log.window.notice("mouseDown at \(event.locationInWindow.debugDescription, privacy: .public)")
        dragStartMouse = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartMouse, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y

        if !isDragging {
            guard (dx * dx + dy * dy).squareRoot() >= Self.dragThreshold else { return }
            isDragging = true
            onDragStart?()
        }

        window.setFrameOrigin(CGPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouse = nil
            isDragging = false
        }

        if isDragging {
            onDragEnd?()
        } else {
            onLeftClick?(event)
        }
    }

    /// Right-click is the language toggle, so this deliberately does not fall through to
    /// `NSView.menu`. Returning without calling super also stops AppKit from showing one.
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

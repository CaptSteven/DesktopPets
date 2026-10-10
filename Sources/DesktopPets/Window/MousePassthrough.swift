import AppKit
import DesktopPetsCore

/// Keeps a borderless window click-through wherever the sprite is transparent.
///
/// The usual approach is a global mouse-moved event monitor that toggles
/// `NSWindow.ignoresMouseEvents`. This does the same thing, but polls from the tick that already
/// drives the animation instead of installing monitors. That avoids the focus and permission
/// subtleties of global monitors, and the cost is at most one frame (~33ms) of latency before a
/// click starts passing through. For a pet that only reacts to deliberate clicks, that is
/// imperceptible; if it ever matters, this is the one place to change.
final class MousePassthrough {
    private let window: NSWindow
    private let threshold: UInt8
    private var isForcedInteractive = false

    init(window: NSWindow, threshold: UInt8) {
        self.window = window
        self.threshold = threshold
    }

    /// While the user is dragging the pet, the window must keep receiving mouse events no matter
    /// what pixel is under the cursor.
    func setForcedInteractive(_ forced: Bool) {
        isForcedInteractive = forced
        if forced { window.ignoresMouseEvents = false }
    }

    /// `alphaAt` maps a point in window coordinates (bottom-left origin, in points) to the
    /// sprite's alpha there, or nil when there is no pixel at that point.
    func update(alphaAt: (CGPoint) -> UInt8?) {
        guard !isForcedInteractive else { return }

        let mouse = NSEvent.mouseLocation
        let frame = window.frame

        // Anywhere outside the window is unreachable for clicks anyway; treating it as
        // transparent means the check below only ever runs for the small sprite rect.
        guard frame.contains(mouse) else {
            window.ignoresMouseEvents = true
            return
        }

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let alpha = alphaAt(local) ?? 0
        window.ignoresMouseEvents = alpha < threshold
    }
}

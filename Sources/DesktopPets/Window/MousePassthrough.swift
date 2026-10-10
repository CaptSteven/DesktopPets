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
    /// Last value pushed to the window, so the log only fires when it actually flips.
    private var lastApplied: Bool?

    init(window: NSWindow, threshold: UInt8) {
        self.window = window
        self.threshold = threshold
    }

    /// While the user is dragging the pet, the window must keep receiving mouse events no matter
    /// what pixel is under the cursor.
    func setForcedInteractive(_ forced: Bool) {
        isForcedInteractive = forced
        if forced { apply(ignoresMouseEvents: false, reason: "forced interactive (dragging)") }
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
            apply(ignoresMouseEvents: true, reason: "cursor outside window")
            return
        }

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        guard let alpha = alphaAt(local) else {
            // No decoded frame to sample. Treating that as opaque would leave the pet swallowing
            // clicks it cannot act on, so fail towards click-through and say why.
            apply(ignoresMouseEvents: true, reason: "no alpha mask available")
            return
        }

        apply(
            ignoresMouseEvents: alpha < threshold,
            reason: "alpha \(alpha) vs threshold \(threshold)"
        )
    }

    /// Applies the flag, logging only when it changes.
    ///
    /// Whether the pet can be clicked is otherwise invisible from outside the process, so this is
    /// what makes a "I cannot interact with it" report diagnosable:
    ///
    ///     log stream --predicate 'subsystem == "com.desktoppets.DesktopPets"'
    private func apply(ignoresMouseEvents: Bool, reason: String) {
        guard lastApplied != ignoresMouseEvents || window.ignoresMouseEvents != ignoresMouseEvents
        else { return }

        lastApplied = ignoresMouseEvents
        window.ignoresMouseEvents = ignoresMouseEvents
        // Marked `.public`: os.Logger redacts interpolated values by default, which would hide the
        // one thing this log exists to tell us.
        Log.window.notice("click-through \(ignoresMouseEvents ? "ON" : "OFF", privacy: .public) — \(reason, privacy: .public)")
    }
}

import AppKit

/// The pet's window: borderless, fully transparent, and floating above normal windows.
///
/// It deliberately cannot become key or main. A desktop pet that steals focus from whatever the
/// user is typing into would be worse than no pet at all.
final class PetWindow: NSWindow {
    init(contentSize: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // Follow the user across Spaces, stay put during Mission Control, and remain visible over
        // full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // Without this the window would be listed as a candidate for window-cycling shortcuts.
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

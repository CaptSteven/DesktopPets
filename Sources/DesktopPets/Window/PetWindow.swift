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
        // The whole window takes clicks, not just the opaque pixels of the sprite.
        //
        // This used to be per-pixel: the tick sampled the sprite's alpha under the cursor and
        // toggled `ignoresMouseEvents`, so the transparent margins passed clicks through to
        // whatever was behind. That broke in a way that was hard to see coming — whether the pet
        // could be clicked depended on the *art*, and on which frame was showing. `guitarist`
        // covers 16% of the frame while idle but only 12% while asleep, and its sleeping pose
        // leaves the window's centre transparent, so the pixel most people aim at passed the click
        // straight through. Since a sleeping pet can only be woken by being clicked, it stayed
        // asleep and unresponsive until it was quit and relaunched.
        //
        // The window is only as large as the sprite (128pt here), so accepting clicks across all of
        // it costs very little.
        ignoresMouseEvents = false
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

import AppKit
import DesktopPetsCore

/// Bridges AppKit's screen list into the AppKit-free `ScreenInfo` type that layout math uses.
extension NSScreen {
    /// `NSScreen.screens.first` is the screen holding the menu bar, which is the one AppKit
    /// considers primary. `NSScreen.main` is only "the screen with the key window", which for an
    /// accessory app can be any of them.
    func screenInfo(isPrimary: Bool) -> ScreenInfo {
        ScreenInfo(frame: frame, visibleFrame: visibleFrame, isMain: isPrimary)
    }
}

enum ScreenMapping {
    static var all: [ScreenInfo] {
        // `NSScreen.screens` is fetched once here rather than inside the per-screen conversion:
        // this runs on every tick, so doing it inside the closure turned one lookup into one per
        // attached display.
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        return screens.map { $0.screenInfo(isPrimary: $0 == primary) }
    }

    /// The screen the pet should live on, given where it currently is.
    static func active(for position: CGPoint) -> ScreenInfo? {
        ScreenSelector.activeScreen(for: position, screens: all)
    }

    /// The visible frame of the screen nearest `position`, falling back to the primary screen's
    /// frame and finally to a sane default so the pet always has somewhere to be.
    static func visibleFrame(nearest position: CGPoint?) -> CGRect {
        if let position, let screen = active(for: position) { return screen.visibleFrame }
        if let primary = ScreenSelector.mainScreen(in: all) { return primary.visibleFrame }
        return CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

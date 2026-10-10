import AppKit

/// Builds the pet's right-click menu.
///
/// The menu is attached with `NSView.menu`, so AppKit shows it on right-click without any extra
/// event handling. It is rebuilt whenever the skin changes so the header stays accurate.
enum PetMenu {
    static func build(target: AnyObject, skinName: String, speechEnabled: Bool) -> NSMenu {
        let menu = NSMenu()

        // A disabled header item doubles as a label for the currently loaded skin.
        let header = menu.addItem(withTitle: "Skin: \(skinName)", action: nil, keyEquivalent: "")
        header.isEnabled = false

        menu.addItem(.separator())

        let speak = menu.addItem(
            withTitle: "Speak",
            action: #selector(PetController.toggleSpeech(_:)),
            keyEquivalent: ""
        )
        speak.target = target
        speak.state = speechEnabled ? .on : .off

        menu.addItem(.separator())

        let reload = menu.addItem(
            withTitle: "Reload Skin and Phrases",
            action: #selector(PetController.reloadSkin(_:)),
            keyEquivalent: "r"
        )
        reload.target = target

        let resetPosition = menu.addItem(
            withTitle: "Reset Position",
            action: #selector(PetController.resetPosition(_:)),
            keyEquivalent: ""
        )
        resetPosition.target = target

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: "Quit DesktopPets",
            action: #selector(PetController.quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = target

        return menu
    }
}

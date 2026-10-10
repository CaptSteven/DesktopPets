import AppKit
import DesktopPetsCore

/// Builds the pet's menu.
///
/// Note this is opened by *left*-clicking the pet (see `PetView`), not by right-click: right-click
/// is the language toggle. That is why the menu is popped up explicitly rather than attached with
/// `NSView.menu`.
enum PetMenu {
    static func build(
        target: AnyObject,
        skinName: String,
        speechEnabled: Bool,
        language: AppLanguage
    ) -> NSMenu {
        let strings = MenuStrings.forLanguage(language)
        let menu = NSMenu()

        // A disabled header row doubles as a label for the currently loaded skin.
        let header = menu.addItem(
            withTitle: strings.skinHeader(name: skinName),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false

        menu.addItem(.separator())

        let speak = menu.addItem(
            withTitle: strings.speak,
            action: #selector(PetController.toggleSpeech(_:)),
            keyEquivalent: ""
        )
        speak.target = target
        speak.state = speechEnabled ? .on : .off

        menu.addItem(.separator())

        let reload = menu.addItem(
            withTitle: strings.reload,
            action: #selector(PetController.reloadSkin(_:)),
            keyEquivalent: ""
        )
        reload.target = target

        let resetPosition = menu.addItem(
            withTitle: strings.resetPosition,
            action: #selector(PetController.resetPosition(_:)),
            keyEquivalent: ""
        )
        resetPosition.target = target

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: strings.quit,
            action: #selector(PetController.quit(_:)),
            keyEquivalent: ""
        )
        quit.target = target

        return menu
    }
}

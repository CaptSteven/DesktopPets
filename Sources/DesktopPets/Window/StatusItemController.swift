import AppKit
import DesktopPetsCore

/// A menu-bar icon carrying the same menu as the pet.
///
/// This exists to make "I cannot close it" impossible. The pet's controls all live on a sprite you
/// have to click, which is a single point of failure: if the pet is covered, off-screen, or not
/// receiving clicks, there is no way to reach Quit. A status item is always reachable, and is the
/// standard thing for an `.accessory` app to have.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var onAction: ((MenuAction) -> Void)?

    init() {
        // `.variableLength` so the pawprint icon sizes itself.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "DesktopPets"
        )
        image?.isTemplate = true

        statusItem.button?.image = image
        statusItem.button?.toolTip = "DesktopPets"
    }

    /// Rebuilds the menu. Called whenever the skin or language changes.
    func update(items: [MenuItem], onAction: @escaping (MenuAction) -> Void) {
        self.onAction = onAction

        let menu = NSMenu()
        for item in items {
            switch item {
            case .separator:
                menu.addItem(.separator())

            case .header(let title):
                let menuItem = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false

            case .action(let action, let title):
                let menuItem = menu.addItem(
                    withTitle: title,
                    action: #selector(handleMenuSelection(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = action.rawValue

            case .toggle(let action, let title, let isOn):
                let menuItem = menu.addItem(
                    withTitle: title,
                    action: #selector(handleMenuSelection(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = action.rawValue
                menuItem.state = isOn ? .on : .off
            }
        }

        statusItem.menu = menu
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleMenuSelection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = MenuAction(rawValue: raw)
        else { return }

        onAction?(action)
    }
}

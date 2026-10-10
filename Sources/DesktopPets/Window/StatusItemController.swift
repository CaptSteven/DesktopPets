import AppKit
import DesktopPetsCore

/// A menu-bar icon carrying the pet's menu.
///
/// This exists to make "I cannot close it" impossible. The pet's controls all live on a sprite you
/// have to click, which is a single point of failure: if the pet is covered, off-screen, or not
/// receiving clicks, there is no way to reach Quit. A status item is always reachable, and is the
/// standard thing for an `.accessory` app to have.
///
/// It also carries the skin picker, because the menu bar has no free right-click to hang one on.
final class StatusItemController {
    private let statusItem: NSStatusItem
    /// Kept so a clicked row can be mapped back to its command. Rows are tracked by index rather
    /// than by stashing a command in `representedObject`, which would have to be bridged to `Any`.
    private var items: [MenuItem] = []
    private var onCommand: ((MenuCommand) -> Void)?

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

    /// Rebuilds the menu. Called whenever the skin, language or speech setting changes.
    func update(items: [MenuItem], onCommand: @escaping (MenuCommand) -> Void) {
        self.items = items
        self.onCommand = onCommand

        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            switch item {
            case .separator:
                menu.addItem(.separator())

            case .header(let title):
                let menuItem = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false

            case .action(_, let title), .toggle(_, let title, _):
                let menuItem = menu.addItem(
                    withTitle: title,
                    action: #selector(handleMenuSelection(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = index
                if case .toggle(_, _, let isOn) = item {
                    menuItem.state = isOn ? .on : .off
                }
            }
        }

        statusItem.menu = menu
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleMenuSelection(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              items.indices.contains(index),
              let command = items[index].command
        else { return }

        onCommand?(command)
    }
}

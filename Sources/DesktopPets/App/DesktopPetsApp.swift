import AppKit
import DesktopPetsCore

@main
enum DesktopPetsApp {
    /// `NSApplication.delegate` is a weak reference, so the delegate is owned here.
    private static let delegate = AppDelegate()

    static func main() {
        // A headless mode is the only way to check skin loading without a window server, since an
        // executable target cannot be imported by the test target.
        if CommandLine.arguments.contains("--verify-skin") {
            SkinVerifier.run()
        }

        let app = NSApplication.shared
        // No Dock icon and no menu bar: a desktop pet should not look like a running application.
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private let config = ConfigStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        startController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remember where the pet was standing.
        controller?.persistPosition()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Builds the controller from whatever is currently on disk. Also used to reload after the
    /// user edits or replaces their art.
    private func startController() {
        do {
            guard let locator = AssetLocator.resolve() else {
                throw SpriteSourceError.noSkinsFound(
                    URL(fileURLWithPath: "Resources/Skins", isDirectory: true)
                )
            }

            guard let skinName = SpriteSource.resolveSkinName(config: config, locator: locator) else {
                throw SpriteSourceError.noSkinsFound(locator.skinsDirectory)
            }

            let skin = try SpriteSource.loadSkin(named: skinName, from: locator)
            let controller = PetController(locator: locator, config: config, skin: skin)
            controller.onReloadRequested = { [weak self] in self?.reload() }
            controller.onSkinChangeRequested = { [weak self] name in self?.switchSkin(to: name) }
            controller.start()
            self.controller = controller
        } catch {
            reportFatal(error)
        }
    }

    private func reload() {
        controller?.stop()
        controller = nil
        startController()
    }

    /// Swaps to another skin and rebuilds. The controller has already written the choice to
    /// `ConfigStore`, so `startController` picks it up.
    private func switchSkin(to name: String) {
        Log.info("Switching skin to \"\(name)\"")
        reload()
    }

    private func reportFatal(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        Log.error(message)

        // The app has no Dock icon, so the alert has to be pushed to the front explicitly.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "DesktopPets could not start"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        alert.runModal()

        NSApp.terminate(nil)
    }
}

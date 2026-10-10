import AppKit
import DesktopPetsCore

/// Shows the self-drawn menu panel and decides when it closes.
///
/// Nothing here blocks. The panel is an ordinary window that either receives a click or does not,
/// and there is no nested event loop anywhere — which matters, because this is the only route to
/// Quit. The previous implementation called `NSMenu.popUp`, which runs a modal tracking loop, and
/// that turned out to be a very bad thing to put in front of the only way out of the app.
final class PetMenuController {
    /// Safety net: never leave the panel stranded on screen.
    private static let autoCloseAfter: TimeInterval = 30

    private let panel = PetMenuPanel()
    private let view = PetMenuPanelView()
    private var globalMonitor: Any?
    private var autoCloseTimer: Timer?
    private var onCommand: ((MenuCommand) -> Void)?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel.contentView = view
        view.onSelect = { [weak self] index in self?.select(at: index) }
    }

    /// Shows the menu with its top-left corner at `point`.
    func show(
        items: [MenuItem],
        at point: CGPoint,
        within visibleFrame: CGRect,
        onCommand: @escaping (MenuCommand) -> Void
    ) {
        self.onCommand = onCommand
        view.items = items

        let size = view.sizeThatFits()
        view.frame = CGRect(origin: .zero, size: size)

        let origin = MenuPanelLayout.origin(size: size, at: point, within: visibleFrame)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)

        // On a nonactivating panel this makes the panel key *without* bringing the app forward, so
        // Escape and the mouse work while whatever you were using stays frontmost.
        panel.makeKeyAndOrderFront(nil)

        startMonitoring()
    }

    func close() {
        stopMonitoring()
        panel.orderOut(nil)
    }

    // MARK: Selection

    private func select(at index: Int) {
        guard view.items.indices.contains(index),
              let command = view.items[index].command
        else { return }

        Log.window.notice("menu selected \(command.identifier, privacy: .public)")
        let handler = onCommand
        close()
        handler?(command)
    }

    // MARK: Dismissal

    private func startMonitoring() {
        stopMonitoring()

        // Clicking another app. Global monitors only see events bound for *other* apps, which is
        // exactly the case the panel cannot notice by itself. Mouse events need no accessibility
        // permission — only keyboard monitors do.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closeIfClickWasOutside()
        }

        autoCloseTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoCloseAfter,
            repeats: false
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    private func closeIfClickWasOutside() {
        guard panel.isVisible else { return }
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
        close()
    }
}

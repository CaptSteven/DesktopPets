import AppKit
import DesktopPetsCore

/// Owns the pet: its window, where it is, and the loop that drives animation and movement.
final class PetController {
    /// 30Hz. The sprite only runs at 6-10fps, but a smoother tick keeps movement and the
    /// click-through check responsive.
    private static let tickInterval: Double = 1.0 / 30.0
    /// A throttled background app can hand us a huge delta; never let one tick teleport the pet.
    private static let maxTickDelta: Double = 0.1
    /// Where the pet stands on first launch, measured up from the bottom of the visible frame.
    private static let defaultFeetInset: Double = 24

    private let locator: AssetLocator
    private let config: ConfigStore
    private let skin: LoadedSkin
    private let window: PetWindow
    private let view: PetView
    private let passthrough: MousePassthrough
    private let animator = AnimationController()
    private let speech: SpeechController

    private var machine: PetStateMachine
    /// The pet's anchor point in screen coordinates. The window frame is derived from it.
    private var hotspot: CGPoint
    private var lastTickTime: TimeInterval
    private var lastTransitionCount = 0
    private var previousActivity: PetActivity = .idle
    private var timer: Timer?
    /// Draws the pet's own menu. This is the only route to Quit from the sprite, so it deliberately
    /// uses no blocking API — see `showMenu(at:)`.
    private let menuController = PetMenuController()
    /// Always-reachable escape hatch in the menu bar, so "I cannot close it" is not possible.
    private let statusItem = StatusItemController()

    /// Set by the app delegate, which rebuilds the controller to pick up new or edited art.
    var onReloadRequested: (() -> Void)?
    /// Set by the app delegate. Rebuilding is the cleanest way to change skin: it re-reads the
    /// manifest, the frames and the phrases, and the window is resized to the new frame size.
    var onSkinChangeRequested: ((String) -> Void)?

    init(locator: AssetLocator, config: ConfigStore, skin: LoadedSkin) {
        self.locator = locator
        self.config = config
        self.skin = skin

        let windowSize = PetLayout.windowSize(
            frameSize: skin.manifest.frameSize,
            scale: skin.manifest.scale
        )

        window = PetWindow(contentSize: windowSize)
        view = PetView(frame: CGRect(origin: .zero, size: windowSize))
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        passthrough = MousePassthrough(window: window, threshold: skin.manifest.hitAlphaThreshold)

        machine = PetStateMachine(
            walkPlan: config.walkPlan(),
            sleepAfter: config.sleepAfter,
            // Only a real "click" animation sets the duration; the lookup must not fall back to
            // idle, which would report a looping animation's duration of zero.
            clickDuration: skin.animations["click"]?.duration ?? 0
        )

        speech = SpeechController(config: config, book: Self.loadPhrases(from: locator))

        hotspot = Self.initialHotspot(
            anchor: skin.manifest.anchor,
            windowSize: windowSize,
            saved: config.petPosition
        )
        lastTickTime = ProcessInfo.processInfo.systemUptime

        window.setFrameOrigin(
            PetLayout.windowOrigin(anchor: skin.manifest.anchor, size: windowSize, position: hotspot)
        )

        refreshMenu()
        view.onDragStart = { [weak self] in self?.handleDragStart() }
        view.onDragEnd = { [weak self] in self?.handleDragEnd() }
        view.onLeftClick = { [weak self] event in self?.handleLeftClick(with: event) }
        view.onRightClick = { [weak self] _ in self?.handleRightClick() }
    }

    // MARK: Lifecycle

    func start() {
        window.orderFrontRegardless()

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // `.common` keeps the pet moving while a menu is open or a window is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        speech.stop()
        menuController.close()
        statusItem.remove()
        window.orderOut(nil)
    }

    /// Writes the pet's position so it reappears in the same place next launch.
    func persistPosition() {
        config.petPosition = hotspot
        config.skinName = skin.name
    }

    // MARK: Menu actions

    /// Rebuilds the controller from scratch, which re-reads both the skin and the phrase files.
    @objc func reloadSkin(_ sender: Any?) {
        persistPosition()
        onReloadRequested?()
    }

    @objc func toggleSpeech(_ sender: Any?) {
        speech.setEnabled(!speech.isEnabled)
        refreshMenu()
    }

    @objc func resetPosition(_ sender: Any?) {
        let windowSize = window.frame.size
        hotspot = Self.defaultHotspot(
            anchor: skin.manifest.anchor,
            windowSize: windowSize,
            visible: ScreenMapping.visibleFrame(nearest: hotspot)
        )
        moveWindowToHotspot(visible: ScreenMapping.visibleFrame(nearest: hotspot))
        persistPosition()
    }

    @objc func quit(_ sender: Any?) {
        persistPosition()
        NSApp.terminate(nil)
    }

    // MARK: Interaction

    private func handleDragStart() {
        // The window must keep receiving events for the whole drag, whatever pixel is underneath.
        passthrough.setForcedInteractive(true)
        machine.beginDrag()
    }

    private func handleDragEnd() {
        passthrough.setForcedInteractive(false)
        machine.endDrag()

        // The user can drop the pet anywhere, including off-screen: pull it back and record where
        // it actually ended up rather than where we last thought it was.
        let windowSize = window.frame.size
        let visible = ScreenMapping.visibleFrame(nearest: NSEvent.mouseLocation)
        let clamped = PetLayout.clamp(window.frame.origin, size: windowSize, into: visible)

        window.setFrameOrigin(clamped)
        hotspot = PetLayout.hotspot(
            anchor: skin.manifest.anchor,
            size: windowSize,
            origin: clamped
        )
        persistPosition()
    }

    /// Left-click: react, then open the menu where the user clicked.
    private func handleLeftClick(with event: NSEvent) {
        machine.reactToClick()
        // Answer immediately rather than waiting for the next tick: the bubble should feel like a
        // reaction to the click.
        speech.react(
            to: .click,
            petState: machine.activity.animationState,
            petFrame: window.frame,
            visibleFrame: ScreenMapping.visibleFrame(nearest: hotspot)
        )
        showMenu(at: NSEvent.mouseLocation)
    }

    /// Right-click: pick a different skin.
    ///
    /// The language toggle used to live here; it is in the menu and the menu-bar item, so giving
    /// right-click to the skin picker does not lose anything.
    private func handleRightClick() {
        menuController.show(
            items: PetMenuModel.skinPickerItems(
                strings: menuStrings,
                skins: installedSkins,
                currentSkin: skin.name
            ),
            at: NSEvent.mouseLocation,
            within: ScreenMapping.visibleFrame(nearest: hotspot),
            onCommand: { [weak self] command in self?.perform(command) }
        )
    }

    /// Opens the pet's menu with its top-left corner at `point`.
    ///
    /// Two things are deliberately absent here. There is no `NSApp.activate`, which previously left
    /// the app running with no key window — a state where clicks stop being delivered. And there is
    /// no `NSMenu.popUp`, which runs a nested modal event loop; putting that in front of the only
    /// route to Quit is how the pet became impossible to close.
    private func showMenu(at point: CGPoint) {
        menuController.show(
            items: menuItems,
            at: point,
            within: ScreenMapping.visibleFrame(nearest: hotspot),
            onCommand: { [weak self] command in self?.perform(command) }
        )
    }

    /// Dispatches a menu choice, wherever it came from: a panel or the menu-bar item.
    private func perform(_ command: MenuCommand) {
        switch command {
        case .toggleSpeech: toggleSpeech(nil)
        case .switchLanguage: switchLanguage()
        case .reload: reloadSkin(nil)
        case .resetPosition: resetPosition(nil)
        case .quit: quit(nil)
        case .selectSkin(let name): selectSkin(named: name)
        }
    }

    /// Switches skins by rebuilding the controller, which re-reads the manifest, the frames and
    /// the phrases, and resizes the window to the new frame size.
    private func selectSkin(named name: String) {
        guard name != skin.name else { return }
        persistPosition()
        config.skinName = name
        onSkinChangeRequested?(name)
    }

    /// Flips the menu language and announces it in the new one.
    ///
    /// The announcement is deliberate: the menu is closed by the time this runs, so without it the
    /// toggle would change something you cannot see until you next open the menu.
    private func switchLanguage() {
        let language = config.toggleLanguage()
        refreshMenu()
        speech.announce(
            language.switchAnnouncement,
            petFrame: window.frame,
            visibleFrame: ScreenMapping.visibleFrame(nearest: hotspot)
        )
    }

    // MARK: Frame loop

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(now - lastTickTime, 0), Self.maxTickDelta)
        lastTickTime = now

        // The menu is anchored where it was opened, so the pet has to hold still while it is up —
        // and it should not wander off or doze off mid-choice either. Animation keeps running so it
        // does not look frozen.
        if menuController.isVisible {
            animator.advance(by: dt)
            view.frameImage = animator.frame
            updatePassthrough()
            return
        }

        let windowSize = window.frame.size
        let visible = ScreenMapping.visibleFrame(nearest: hotspot)
        let walkable = machine.walkPlan.walkableRange(in: visible, petWidth: windowSize.width)

        let activity = machine.tick(dt: dt, currentX: hotspot.x, walkableRange: walkable)

        // The machine decides where to walk; the controller integrates the movement.
        if activity == .walking, let targetX = machine.walkTargetX {
            let step = machine.walkPlan.step(fromX: hotspot.x, toX: targetX, dt: dt)
            hotspot.x = step.x
            if step.arrived { machine.arrivedAtDestination() }
        }

        // While dragging, the view is moving the window and would fight us for control.
        if activity != .dragging {
            moveWindowToHotspot(visible: visible)
        }

        updateAnimation(for: activity, dt: dt)
        updateSpeech(for: activity, dt: dt, visible: visible)
        updatePassthrough()
    }

    private func moveWindowToHotspot(visible: CGRect) {
        let windowSize = window.frame.size
        let anchor = skin.manifest.anchor

        let desired = PetLayout.windowOrigin(anchor: anchor, size: windowSize, position: hotspot)
        let clamped = PetLayout.clamp(desired, size: windowSize, into: visible)
        window.setFrameOrigin(clamped)

        // Clamping can move the pet; keep the hotspot honest so the walk range stays truthful.
        if clamped != desired {
            hotspot = PetLayout.hotspot(anchor: anchor, size: windowSize, origin: clamped)
        }
    }

    private func updateAnimation(for activity: PetActivity, dt: Double) {
        animator.play(skin.animation(for: activity.animationState))

        // Replay one-shot reactions: a second click should restart the animation even though the
        // activity name did not change.
        if machine.transitionCount != lastTransitionCount {
            lastTransitionCount = machine.transitionCount
            animator.restart()
        }

        animator.advance(by: dt)
        view.facing = machine.facing
        view.frameImage = animator.frame
    }

    /// Remarks for the activities that deserve one, then keeps the bubble positioned as the pet
    /// moves. Clicks are handled in `handleClick` so they answer without waiting for a tick.
    private func updateSpeech(for activity: PetActivity, dt: Double, visible: CGRect) {
        if activity != previousActivity {
            switch activity {
            case .sleeping:
                speech.react(to: .sleep, petState: activity.animationState,
                             petFrame: window.frame, visibleFrame: visible)
            case .dragging:
                speech.react(to: .drag, petState: activity.animationState,
                             petFrame: window.frame, visibleFrame: visible)
            case .idle, .walking, .showingClick:
                break
            }
            previousActivity = activity
        }

        speech.tick(
            dt: dt,
            petState: activity.animationState,
            petFrame: window.frame,
            visibleFrame: visible
        )
    }

    private func updatePassthrough() {
        passthrough.update { [weak self] localPoint in
            self?.alpha(atWindowPoint: localPoint)
        }
    }

    private var menuStrings: MenuStrings { MenuStrings.forLanguage(config.language) }

    /// Installed skins, read fresh each time so dropping a new folder in and hitting Reload picks
    /// it up without restarting.
    private var installedSkins: [String] { locator.availableSkins() }

    /// The full menu, rebuilt on demand so it always reflects the current language, skin and
    /// settings. The menu-bar item carries the skin list too, since it has no right-click of its
    /// own to hang a picker on.
    private var menuItems: [MenuItem] {
        PetMenuModel.menuBarItems(
            strings: menuStrings,
            skinName: skin.name,
            skins: installedSkins,
            speechEnabled: speech.isEnabled
        )
    }

    private func refreshMenu() {
        statusItem.update(items: menuItems) { [weak self] command in self?.perform(command) }
    }

    /// Reads `Resources/Phrases/*.json`. A malformed file leaves the pet silent rather than
    /// stopping it from running.
    private static func loadPhrases(from locator: AssetLocator) -> PhraseBook {
        do {
            return try PhraseBook.loadDirectory(at: locator.phrasesDirectory)
        } catch {
            Log.warning("Could not read phrases (\(error)); the pet will stay quiet")
            return PhraseBook()
        }
    }

    /// Samples the current frame's alpha for a point in window coordinates, accounting for the
    /// horizontal flip used when the pet faces left.
    private func alpha(atWindowPoint point: CGPoint) -> UInt8? {
        guard let mask = animator.mask else { return nil }
        let size = window.frame.size
        guard size.width > 0, size.height > 0 else { return nil }

        var u = point.x / size.width
        let v = point.y / size.height
        if view.facing.isFlipped { u = 1 - u }

        return mask.alpha(atNormalizedX: u, y: v)
    }

    // MARK: Placement

    private static func defaultHotspot(anchor: Anchor, windowSize: CGSize, visible: CGRect) -> CGPoint {
        switch anchor {
        case .bottomCenter, .bottomLeft, .bottomRight:
            return CGPoint(x: visible.midX, y: visible.minY + defaultFeetInset)
        default:
            return CGPoint(x: visible.midX, y: visible.midY)
        }
    }

    /// Restores the saved position, pulled back on screen in case monitors have changed since the
    /// pet was last placed.
    private static func initialHotspot(anchor: Anchor, windowSize: CGSize, saved: CGPoint?) -> CGPoint {
        guard let saved else {
            return defaultHotspot(
                anchor: anchor,
                windowSize: windowSize,
                visible: ScreenMapping.visibleFrame(nearest: nil)
            )
        }

        let visible = ScreenMapping.visibleFrame(nearest: saved)
        let origin = PetLayout.windowOrigin(anchor: anchor, size: windowSize, position: saved)
        let clamped = PetLayout.clamp(origin, size: windowSize, into: visible)
        return PetLayout.hotspot(anchor: anchor, size: windowSize, origin: clamped)
    }
}

import AppKit
import DesktopPetsCore

/// Draws the menu rows. Flipped, so `MenuPanelMetrics.offsetFromTop` maps straight onto view
/// coordinates with no conversion.
final class PetMenuPanelView: NSView {
    private static let fontSize: CGFloat = 13
    private static let headerFontSize: CGFloat = 10
    private static let textInset: CGFloat = 14
    private static let checkmarkWidth: CGFloat = 20
    private static let minWidth: CGFloat = 150

    var items: [MenuItem] = [] {
        didSet {
            if items != oldValue {
                highlighted = nil
                needsDisplay = true
                needsLayout = true
            }
        }
    }

    /// Index into `items` of the row under the cursor.
    private(set) var highlighted: Int?

    var metrics = MenuPanelMetrics()
    /// Called with the index of the row the user clicked.
    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    // MARK: Geometry

    /// Natural width: wide enough for the longest row, plus room for the checkmark.
    static func width(for items: [MenuItem], metrics: MenuPanelMetrics) -> CGFloat {
        var widest = minWidth
        for item in items {
            guard let title = item.title else { continue }
            let font = NSFont.systemFont(ofSize: item.isSelectable ? fontSize : headerFontSize)
            let size = (title as NSString).size(withAttributes: [.font: font])
            let extra = checkmarkWidth + textInset * 2
            widest = max(widest, size.width + extra)
        }
        return ceil(widest)
    }

    func sizeThatFits() -> CGSize {
        CGSize(
            width: Self.width(for: items, metrics: metrics),
            height: metrics.height(for: items)
        )
    }

    private func rect(forItemAt index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: metrics.offsetFromTop(ofItemAt: index, in: items),
            width: bounds.width,
            height: metrics.height(of: items[index])
        )
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // `.activeAlways` so hovering still highlights while another app is frontmost.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHighlight(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        if highlighted != nil {
            highlighted = nil
            needsDisplay = true
        }
    }

    private func updateHighlight(for event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let index = metrics.itemIndex(atOffsetFromTop: local.y, in: items)
        if index != highlighted {
            highlighted = index
            needsDisplay = true
        }
    }

    // MARK: Clicks

    /// Without this, the first click on the window of an inactive app only activates it and never
    /// reaches the view — which is what makes a menu feel like it "swallows" clicks.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let index = metrics.itemIndex(atOffsetFromTop: local.y, in: items) else { return }
        onSelect?(index)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.clear(bounds)

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 10,
            yRadius: 10
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        for (index, item) in items.enumerated() {
            draw(item, at: index)
        }
    }

    private func draw(_ item: MenuItem, at index: Int) {
        let rowRect = rect(forItemAt: index)

        switch item {
        case .separator:
            // A hairline inset from both edges, like a real menu.
            let line = CGRect(x: 12, y: rowRect.midY, width: bounds.width - 24, height: 1)
            NSColor.separatorColor.setFill()
            NSBezierPath(rect: line).fill()

        case .header:
            drawText(
                item.title ?? "",
                in: rowRect,
                font: .systemFont(ofSize: Self.headerFontSize),
                colour: .secondaryLabelColor
            )

        case .action, .toggle:
            let isHighlighted = index == highlighted
            if isHighlighted {
                let highlight = NSBezierPath(
                    roundedRect: rowRect.insetBy(dx: 4, dy: 1),
                    xRadius: 6,
                    yRadius: 6
                )
                NSColor.selectedContentBackgroundColor.setFill()
                highlight.fill()
            }

            drawText(
                item.title ?? "",
                in: rowRect,
                font: .systemFont(ofSize: Self.fontSize),
                colour: isHighlighted ? .selectedMenuItemTextColor : .labelColor
            )

            if item.isOn {
                let checkRect = CGRect(
                    x: bounds.width - Self.checkmarkWidth,
                    y: rowRect.minY,
                    width: Self.checkmarkWidth,
                    height: rowRect.height
                )
                drawText(
                    "✓",
                    in: checkRect,
                    font: .systemFont(ofSize: Self.fontSize),
                    colour: isHighlighted ? .selectedMenuItemTextColor : .labelColor
                )
            }
        }
    }

    private func drawText(_ text: String, in rect: CGRect, font: NSFont, colour: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(
            x: rect.minX + Self.textInset,
            y: rect.minY + (rect.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

/// The panel the menu is drawn in.
///
/// `.nonactivatingPanel` is the whole point: it can take clicks and become key **without**
/// activating the app, so the pet never steals focus from whatever you are working in. That is
/// also why nothing here calls `NSApp.activate` — doing so is what previously left the app active
/// with no key window, a state where clicks stop being delivered.
final class PetMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

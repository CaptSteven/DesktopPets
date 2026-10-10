import CoreGraphics

/// Row sizes for the self-drawn menu panel.
///
/// Kept in Core with the rest of the layout maths because turning a click coordinate into "which
/// row did they hit" is exactly the kind of off-by-one that is invisible until someone clicks the
/// wrong item.
public struct MenuPanelMetrics: Equatable {
    /// Height of a clickable row.
    public var rowHeight: Double
    /// Height of the non-selectable header row.
    public var headerRowHeight: Double
    /// Height of a separator.
    public var separatorHeight: Double
    /// Padding above the first row and below the last.
    public var padding: Double

    public init(
        rowHeight: Double = 26,
        headerRowHeight: Double = 20,
        separatorHeight: Double = 9,
        padding: Double = 5
    ) {
        self.rowHeight = rowHeight
        self.headerRowHeight = headerRowHeight
        self.separatorHeight = separatorHeight
        self.padding = padding
    }

    public func height(of item: MenuItem) -> Double {
        switch item {
        case .separator: return separatorHeight
        case .header: return headerRowHeight
        case .action, .toggle: return rowHeight
        }
    }

    /// Total panel height, including padding.
    public func height(for items: [MenuItem]) -> Double {
        padding * 2 + items.reduce(0) { $0 + height(of: $1) }
    }

    /// Distance from the top of the panel to the top of `items[index]`.
    public func offsetFromTop(ofItemAt index: Int, in items: [MenuItem]) -> Double {
        var offset = padding
        for item in items.prefix(index) {
            offset += height(of: item)
        }
        return offset
    }

    /// Index of the row containing `offsetFromTop`, or nil when it lands on padding, a separator or
    /// the header.
    public func itemIndex(atOffsetFromTop offset: Double, in items: [MenuItem]) -> Int? {
        var cursor = padding
        for (index, item) in items.enumerated() {
            let next = cursor + height(of: item)
            if offset >= cursor, offset < next {
                // Only clickable rows resolve to an index; decoration is transparent to clicks.
                return item.isSelectable ? index : nil
            }
            cursor = next
        }
        return nil
    }
}

/// Where to put the menu panel.
public enum MenuPanelLayout {
    /// Places the panel so its top-left corner sits at `point`, like a normal pop-up menu.
    ///
    /// Flips above the point when there is not enough room below, and is clamped to the screen on
    /// every edge — including when the panel is taller or wider than the space available.
    public static func origin(
        size: CGSize,
        at point: CGPoint,
        within visibleFrame: CGRect,
        margin: Double = 4
    ) -> CGPoint {
        let x = clampScalar(
            point.x,
            lower: visibleFrame.minX + margin,
            upper: visibleFrame.maxX - size.width - margin
        )

        // Top edge at the click point, so the panel opens downwards.
        var y = point.y - size.height

        // Not enough room below the click: flip so the panel opens upwards instead.
        if y < visibleFrame.minY + margin {
            y = point.y
        }

        return CGPoint(
            x: x,
            y: clampScalar(
                y,
                lower: visibleFrame.minY + margin,
                upper: visibleFrame.maxY - size.height - margin
            )
        )
    }

    /// Clamps, collapsing to `lower` when the range is inverted — which happens when the panel is
    /// bigger than the space available.
    private static func clampScalar(_ value: Double, lower: Double, upper: Double) -> Double {
        let effectiveUpper = Swift.max(upper, lower)
        return Swift.min(Swift.max(value, lower), effectiveUpper)
    }
}

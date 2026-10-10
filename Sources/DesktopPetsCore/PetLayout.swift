import CoreGraphics
import Foundation

/// A screen, described without AppKit so layout math stays unit-testable.
///
/// `visibleFrame` is the AppKit notion of "the part not covered by the menu bar or Dock",
/// already in the global bottom-left-origin coordinate space AppKit windows use.
public struct ScreenInfo: Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var isMain: Bool

    public init(frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }

    /// Convenience for tests and for screens with no menu bar / Dock.
    public init(frame: CGRect, isMain: Bool = false) {
        self.init(frame: frame, visibleFrame: frame, isMain: isMain)
    }
}

/// Pure geometry: turning a persisted hotspot into a window frame and back, and keeping the
/// pet on screen.
public enum PetLayout {
    /// The window is exactly the sprite's display size. Anything larger would create dead
    /// zones that swallow clicks meant for whatever is behind the pet.
    public static func windowSize(spriteSize: CGSize, scale: Double) -> CGSize {
        let effective = scale > 0 ? scale : 1
        return CGSize(
            width: (spriteSize.width * effective).rounded(),
            height: (spriteSize.height * effective).rounded()
        )
    }

    public static func windowSize(frameSize: SkinSize, scale: Double) -> CGSize {
        windowSize(spriteSize: frameSize.cgSize, scale: scale)
    }

    /// Window origin (bottom-left in AppKit coordinates) for a hotspot.
    public static func windowOrigin(anchor: Anchor, size: CGSize, position: CGPoint) -> CGPoint {
        switch anchor {
        case .center:
            return CGPoint(x: position.x - size.width / 2, y: position.y - size.height / 2)
        case .bottomCenter:
            return CGPoint(x: position.x - size.width / 2, y: position.y)
        case .topCenter:
            return CGPoint(x: position.x - size.width / 2, y: position.y - size.height)
        case .bottomLeft:
            return CGPoint(x: position.x, y: position.y)
        case .bottomRight:
            return CGPoint(x: position.x - size.width, y: position.y)
        case .topLeft:
            return CGPoint(x: position.x, y: position.y - size.height)
        case .topRight:
            return CGPoint(x: position.x - size.width, y: position.y - size.height)
        }
    }

    /// Inverse of ``windowOrigin(anchor:size:position:)`` — used when persisting a dragged window.
    public static func hotspot(anchor: Anchor, size: CGSize, origin: CGPoint) -> CGPoint {
        switch anchor {
        case .center:
            return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        case .bottomCenter:
            return CGPoint(x: origin.x + size.width / 2, y: origin.y)
        case .topCenter:
            return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height)
        case .bottomLeft:
            return origin
        case .bottomRight:
            return CGPoint(x: origin.x + size.width, y: origin.y)
        case .topLeft:
            return CGPoint(x: origin.x, y: origin.y + size.height)
        case .topRight:
            return CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        }
    }

    /// Pulls a window origin back inside `frame`.
    ///
    /// When the window is bigger than `frame` on an axis, the window is pinned to `frame`'s
    /// lower edge on that axis rather than oscillating between two impossible constraints.
    public static func clamp(_ origin: CGPoint, size: CGSize, into frame: CGRect) -> CGPoint {
        CGPoint(
            x: clampScalar(origin.x, lower: frame.minX, upper: frame.maxX - size.width),
            y: clampScalar(origin.y, lower: frame.minY, upper: frame.maxY - size.height)
        )
    }

    private static func clampScalar(_ value: Double, lower: Double, upper: Double) -> Double {
        // `upper` can fall below `lower` for oversized windows; collapse to `lower` in that case.
        let effectiveUpper = Swift.max(upper, lower)
        return Swift.min(Swift.max(value, lower), effectiveUpper)
    }

    /// True when the window fits entirely inside `frame`.
    public static func isFullyVisible(origin: CGPoint, size: CGSize, in frame: CGRect) -> Bool {
        // Half-open comparisons, hence the explicit epsilon on the far edges.
        let epsilon = 0.5
        return origin.x >= frame.minX - epsilon
            && origin.y >= frame.minY - epsilon
            && origin.x + size.width <= frame.maxX + epsilon
            && origin.y + size.height <= frame.maxY + epsilon
    }
}

/// Picks which screen the pet belongs to when it moves, gets dragged, or is restored from disk.
public enum ScreenSelector {
    /// The screen containing `position`, else the nearest one, else the main screen, else nil.
    public static func activeScreen(for position: CGPoint, screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }

        if let containing = screens.first(where: { $0.visibleFrame.contains(position) }) {
            return containing
        }

        // Nearest by squared distance to the visible frame; ties resolved in favour of main.
        var best: ScreenInfo?
        var bestDistance = Double.greatestFiniteMagnitude
        for screen in screens {
            let distance = squaredDistance(from: position, to: screen.visibleFrame)
            if distance < bestDistance {
                bestDistance = distance
                best = screen
            } else if distance == bestDistance, screen.isMain, best?.isMain != true {
                best = screen
            }
        }
        return best ?? mainScreen(in: screens)
    }

    public static func mainScreen(in screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first(where: { $0.isMain }) ?? screens.first
    }

    /// Squared distance from a point to a rect; zero when the point is inside.
    static func squaredDistance(from point: CGPoint, to rect: CGRect) -> Double {
        let dx: Double
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }
        let dy: Double
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
    }
}

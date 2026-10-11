import CoreGraphics

/// Per-pixel alpha of a single frame.
///
/// No longer decides where the pet is clickable — the whole sprite window takes clicks now. It is
/// kept for the `--verify-skin` coverage report, which is how you notice that a pose barely fills
/// its frame.
///
/// Row 0 is the bottom row: CoreGraphics bitmaps fill bottom-up, which matches AppKit's
/// bottom-left window coordinates, so no vertical flip is needed anywhere.
public struct AlphaMask {
    public let width: Int
    public let height: Int
    private let values: [UInt8]

    public init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        self.width = width
        self.height = height
        self.values = buffer
    }

    /// Alpha in `0...255`; out-of-bounds reads are transparent rather than a crash.
    public func alpha(atX x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return values[y * width + x]
    }

    public func alpha(atNormalizedX u: Double, y v: Double) -> UInt8 {
        guard u >= 0, u < 1, v >= 0, v < 1 else { return 0 }
        let x = Int(u * Double(width))
        let y = Int(v * Double(height))
        return alpha(atX: x, y: y)
    }
}

/// One animation state, ready to draw.
public struct SpriteAnimation {
    public let state: String
    public let spec: StateSpec
    public let frames: [CGImage]
    public let masks: [AlphaMask]

    public init(state: String, spec: StateSpec, frames: [CGImage], masks: [AlphaMask]) {
        self.state = state
        self.spec = spec
        self.frames = frames
        self.masks = masks
    }

    public var frameCount: Int { frames.count }

    /// Duration of one pass, in seconds. Used for one-shot states such as `click`.
    public var duration: Double {
        guard spec.loop == false, spec.fps > 0 else { return 0 }
        return Double(frames.count) / spec.fps
    }
}

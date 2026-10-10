import CoreGraphics
import DesktopPetsCore
import Foundation
import ImageIO

enum PackerError: LocalizedError {
    case missingManifest(URL)
    case emptyStateDirectory(state: String, directory: URL)
    case unreadableImage(URL)
    case frameSizeMismatch(state: String, file: URL, expected: SkinSize, actual: SkinSize)
    case couldNotCreateContext(width: Int, height: Int)
    case couldNotWrite(URL)
    case noStates

    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "No skin.json at \(url.path)"
        case .emptyStateDirectory(let state, let directory):
            return """
                State "\(state)" has no PNG frames in \(directory.path).
                Every state declared in skin.json needs at least one frame; comment one out if you \
                do not want it yet.
                """
        case .unreadableImage(let url):
            return "Could not decode image at \(url.path)"
        case .frameSizeMismatch(let state, let file, let expected, let actual):
            return """
                Frame \(file.lastPathComponent) in state "\(state)" is \(actual.width)x\(actual.height), \
                but skin.json declares \(expected.width)x\(expected.height).
                """
        case .couldNotCreateContext(let width, let height):
            return "Could not create a \(width)x\(height) drawing context"
        case .couldNotWrite(let url):
            return "Could not write \(url.path)"
        case .noStates:
            return "skin.json declares no states"
        }
    }
}

struct PackedState {
    let name: String
    let row: Int
    let frameCount: Int
    let previewURL: URL
}

struct PackResult {
    let skinName: String
    let sheetURL: URL
    let manifestURL: URL
    let states: [PackedState]
}

/// How far one decoded frame differs from the same frame read back out of the sheet.
struct FrameComparison {
    let state: String
    let frame: Int
    /// Largest absolute per-channel difference across RGBA. Zero means identical.
    let maxChannelDifference: Int
}

struct VerifyReport {
    let comparisons: [FrameComparison]

    var mismatches: [FrameComparison] { comparisons.filter { $0.maxChannelDifference != 0 } }
    var isIdentical: Bool { mismatches.isEmpty }
    var worstDifference: Int { comparisons.map(\.maxChannelDifference).max() ?? 0 }
}

/// Turns `Skins/<name>/src/<state>/*.png` into a sprite sheet plus GIF previews.
enum Packer {
    static func pack(
        skinNamed name: String,
        from locator: AssetLocator,
        fileManager: FileManager = .default
    ) throws -> PackResult {
        let manifestURL = locator.sourceManifestURL(inSkin: name)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PackerError.missingManifest(manifestURL)
        }
        let manifest = try SkinManifest.load(from: manifestURL)

        let buildDirectory = locator.packedManifestURL(inSkin: name).deletingLastPathComponent()
        let previewDirectory = locator.previewDirectory(inSkin: name)
        try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)

        // Read every declared state first, so a missing directory fails before anything is written
        // and a half-packed skin never lands on disk.
        //
        // Unlike the runtime, the packer requires frames for *every* declared state. Being strict
        // here is the point: a state you forgot to draw is caught now, rather than silently
        // falling back to idle at runtime.
        var framesByState: [String: [CGImage]] = [:]
        for state in manifest.states.keys.sorted() {
            let directory = locator.sourceFramesDirectory(inSkin: name, state: state)
            let files = pngFiles(in: directory, fileManager: fileManager)
            guard !files.isEmpty else {
                throw PackerError.emptyStateDirectory(state: state, directory: directory)
            }

            var frames: [CGImage] = []
            for file in files {
                let image = try loadImage(at: file)
                let actual = SkinSize(width: image.width, height: image.height)
                guard actual == manifest.frameSize else {
                    throw PackerError.frameSizeMismatch(
                        state: state,
                        file: file,
                        expected: manifest.frameSize,
                        actual: actual
                    )
                }
                frames.append(image)
            }
            framesByState[state] = frames
        }
        guard !framesByState.isEmpty else { throw PackerError.noStates }

        // Alphabetical row assignment, so re-packing an unchanged skin is byte-identical.
        let rowByState = Dictionary(
            uniqueKeysWithValues: SkinManifest.packedRows(for: manifest.states).map { ($0.state, $0.row) }
        )

        var packed = manifest
        for (state, row) in rowByState {
            packed.states[state]?.row = row
            packed.states[state]?.frames = framesByState[state]?.count
        }
        try packed.validatePacked()

        let sheetSize = SkinManifest.packedSheetSize(for: packed.states, frameSize: packed.frameSize)
        let sheet = try renderSheet(
            framesByState: framesByState,
            rowByState: rowByState,
            manifest: packed,
            size: sheetSize
        )

        let sheetURL = locator.packedSheetURL(inSkin: name)
        try writePNG(sheet, to: sheetURL, contextSize: sheetSize)

        let packedManifestURL = locator.packedManifestURL(inSkin: name)
        do {
            try packed.encodedJSON().write(to: packedManifestURL)
        } catch {
            throw PackerError.couldNotWrite(packedManifestURL)
        }

        var states: [PackedState] = []
        for state in packed.states.keys.sorted() {
            guard let row = rowByState[state],
                  let frames = framesByState[state],
                  let spec = packed.states[state]
            else { continue }

            let previewURL = previewDirectory.appendingPathComponent("\(state).gif")
            try writeGIF(frames: frames, fps: spec.fps, size: packed.frameSize, to: previewURL)
            states.append(
                PackedState(name: state, row: row, frameCount: frames.count, previewURL: previewURL)
            )
        }

        return PackResult(
            skinName: name,
            sheetURL: sheetURL,
            manifestURL: packedManifestURL,
            states: states
        )
    }

    // MARK: Verification

    /// Re-reads the packed sheet and compares every frame against its source PNG.
    ///
    /// This is the check that the layout math is actually right: row assignment, column order, and
    /// the top-left / bottom-left flip between `CGImage.cropping` and the drawing context. A
    /// mistake in any of those still produces a sheet that *looks* plausible, so comparing pixels
    /// is the only honest way to know. Run automatically after every pack.
    static func verifySheet(
        skinNamed name: String,
        from locator: AssetLocator,
        fileManager: FileManager = .default
    ) throws -> VerifyReport {
        let packed = try SkinManifest.load(from: locator.packedManifestURL(inSkin: name))
        try packed.validatePacked()

        let sheet = try loadImage(at: locator.packedSheetURL(inSkin: name))
        let sheetURL = locator.packedSheetURL(inSkin: name)
        var comparisons: [FrameComparison] = []

        for state in packed.states.keys.sorted() {
            guard let spec = packed.states[state], let row = spec.row, let count = spec.frames else { continue }

            let directory = locator.sourceFramesDirectory(inSkin: name, state: state)
            let files = pngFiles(in: directory, fileManager: fileManager)
            guard files.count == count else {
                throw PackerError.emptyStateDirectory(state: state, directory: directory)
            }

            for (column, file) in files.enumerated() {
                let source = try loadImage(at: file)
                guard let cropped = sheet.cropping(to: packed.sheetFrameRect(row: row, column: column)) else {
                    throw PackerError.couldNotWrite(sheetURL)
                }

                comparisons.append(FrameComparison(
                    state: state,
                    frame: column,
                    maxChannelDifference: maxChannelDifference(
                        between: source,
                        and: cropped,
                        size: packed.frameSize
                    )
                ))
            }
        }

        return VerifyReport(comparisons: comparisons)
    }

    /// Largest absolute per-channel difference between two frames, rendered into the same format.
    private static func maxChannelDifference(
        between lhs: CGImage,
        and rhs: CGImage,
        size: SkinSize
    ) -> Int {
        guard let a = rgbaBytes(of: lhs, size: size),
              let b = rgbaBytes(of: rhs, size: size),
              a.count == b.count
        else {
            // Distinctly impossible value, so a failure to normalise never reads as "identical".
            return Int.max
        }

        var worst = 0
        for index in a.indices {
            let difference = abs(Int(a[index]) - Int(b[index]))
            if difference > worst { worst = difference }
        }
        return worst
    }

    /// Normalises any image into premultiplied RGBA8 so two images can be compared byte for byte.
    private static func rgbaBytes(of image: CGImage, size: SkinSize) -> [UInt8]? {
        let bytesPerRow = size.width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * size.height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        return drew ? buffer : nil
    }

    // MARK: Sheet

    private static func renderSheet(
        framesByState: [String: [CGImage]],
        rowByState: [String: Int],
        manifest: SkinManifest,
        size: SkinSize
    ) throws -> CGImage {
        guard let context = makeContext(size: size) else {
            throw PackerError.couldNotCreateContext(width: size.width, height: size.height)
        }
        context.interpolationQuality = .none
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        for (state, row) in rowByState {
            guard let frames = framesByState[state] else { continue }
            for (column, frame) in frames.enumerated() {
                // `sheetFrameRect` is in CGImage top-left coordinates; this context is bottom-left.
                let target = manifest.sheetFrameRect(row: row, column: column)
                let inContext = CGRect(
                    x: target.minX,
                    y: Double(size.height) - target.maxY,
                    width: target.width,
                    height: target.height
                )
                context.draw(frame, in: inContext)
            }
        }

        guard let image = context.makeImage() else {
            throw PackerError.couldNotCreateContext(width: size.width, height: size.height)
        }
        return image
    }

    // MARK: GIF previews

    /// Writes a looping GIF at the state's frame rate.
    ///
    /// GIF only supports 1-bit alpha, so frames are composited onto a flat light background;
    /// otherwise the transparent regions turn into black fringes. These are for checking frame
    /// order and rhythm by eye — they are not what the app draws.
    private static func writeGIF(frames: [CGImage], fps: Double, size: SkinSize, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else {
            throw PackerError.couldNotWrite(url)
        }

        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )

        let delay = fps > 0 ? 1.0 / fps : 0.1
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ] as CFDictionary

        let background = CGColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
        for frame in frames {
            let flattened = try composite(frame, onto: background, size: size)
            CGImageDestinationAddImage(destination, flattened, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw PackerError.couldNotWrite(url)
        }
    }

    private static func composite(_ frame: CGImage, onto colour: CGColor, size: SkinSize) throws -> CGImage {
        guard let context = makeContext(size: size) else {
            throw PackerError.couldNotCreateContext(width: size.width, height: size.height)
        }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.setFillColor(colour)
        context.fill(rect)
        context.interpolationQuality = .none
        context.draw(frame, in: rect)

        guard let image = context.makeImage() else {
            throw PackerError.couldNotCreateContext(width: size.width, height: size.height)
        }
        return image
    }

    // MARK: Plumbing

    private static func makeContext(size: SkinSize) -> CGContext? {
        CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func pngFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw PackerError.unreadableImage(url)
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL, contextSize: SkinSize) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw PackerError.couldNotWrite(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PackerError.couldNotWrite(url)
        }
    }
}

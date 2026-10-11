import AppKit
import DesktopPetsCore
import ImageIO

/// Where a skin's frames were read from.
enum SpriteOrigin: String {
    /// The packer's `build/sheet.png`, addressed through `build/skin.json`.
    case packedSheet
    /// Loose `src/<state>/*.png` files, which is what you get before running the packer.
    case looseFrames
}

/// A skin that has been loaded and decoded.
struct LoadedSkin {
    let name: String
    let manifest: SkinManifest
    let animations: [String: SpriteAnimation]
    let origin: SpriteOrigin

    /// The animation for `state`, degrading to the manifest's fallback (normally `idle`) when the
    /// skin does not provide it.
    func animation(for state: String) -> SpriteAnimation? {
        animations[state] ?? animations[manifest.fallbackState(for: state)]
    }
}

enum SpriteSourceError: LocalizedError {
    case noSkinsFound(URL)
    case missingManifest(URL)
    case emptyStateDirectory(state: String, directory: URL)
    case frameSizeMismatch(state: String, file: URL, expected: SkinSize, actual: SkinSize)
    case unreadableImage(URL)
    case noFramesLoaded(skin: String)

    var errorDescription: String? {
        switch self {
        case .noSkinsFound(let directory):
            return """
                No skins found in \(directory.path).
                Create Resources/Skins/<name>/skin.json and Resources/Skins/<name>/src/<state>/*.png.
                Run Scripts/make-placeholder-skin.sh to generate a working example.
                """
        case .missingManifest(let url):
            return "Missing skin manifest at \(url.path)"
        case .emptyStateDirectory(let state, let directory):
            return """
                State "\(state)" has no frames in \(directory.path).
                "idle" and "walk" are required; give every other declared state its own frames.
                """
        case .frameSizeMismatch(let state, let file, let expected, let actual):
            return """
                Frame \(file.lastPathComponent) in state "\(state)" is \(actual.width)x\(actual.height), \
                but skin.json declares \(expected.width)x\(expected.height).
                """
        case .unreadableImage(let url):
            return "Could not decode image at \(url.path)"
        case .noFramesLoaded(let skin):
            return "Skin \"\(skin)\" has no usable animations"
        }
    }
}

/// Loads skins from disk.
///
/// Prefers the packed sprite sheet (`build/sheet.png` + `build/skin.json`) when the packer has
/// produced one, and otherwise reads loose frames from `Skins/<name>/src/<state>/*.png`. The
/// fallback matters: it means you can edit art and hit Reload Skin without re-packing.
enum SpriteSource {
    /// The skin to run: whatever the user configured, else the first one available.
    static func resolveSkinName(config: ConfigStore, locator: AssetLocator) -> String? {
        let available = locator.availableSkins()
        guard !available.isEmpty else { return nil }

        if let configured = config.skinName {
            if available.contains(configured) { return configured }
            Log.warning("Configured skin \"\(configured)\" not found; falling back to \(available[0])")
        }
        return available[0]
    }

    static func loadSkin(
        named name: String,
        from locator: AssetLocator,
        fileManager: FileManager = .default
    ) throws -> LoadedSkin {
        let manifestURL = locator.runtimeManifestURL(inSkin: name)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SpriteSourceError.missingManifest(manifestURL)
        }
        let manifest = try SkinManifest.load(from: manifestURL)

        let animations: [String: SpriteAnimation]
        let origin: SpriteOrigin

        if let packed = try loadPackedSheet(name: name, locator: locator, fileManager: fileManager) {
            animations = packed.animations
            origin = .packedSheet
        } else {
            animations = try loadFrameDirectories(
                manifest: manifest,
                name: name,
                locator: locator,
                fileManager: fileManager
            )
            origin = .looseFrames
        }

        guard !animations.isEmpty else {
            throw SpriteSourceError.noFramesLoaded(skin: name)
        }

        Log.info("""
            Loaded skin "\(name)" from \(origin.rawValue) with states: \
            \(animations.keys.sorted().joined(separator: ", "))
            """)
        return LoadedSkin(name: name, manifest: manifest, animations: animations, origin: origin)
    }

    /// Reads the packer's sprite sheet.
    ///
    /// Returns nil — rather than throwing — when no sheet has been produced yet, or when the
    /// packed manifest is stale or hand-edited, so the caller can fall back to loose frames.
    private static func loadPackedSheet(
        name: String,
        locator: AssetLocator,
        fileManager: FileManager
    ) throws -> LoadedSkin? {
        let sheetURL = locator.packedSheetURL(inSkin: name)
        let manifestURL = locator.packedManifestURL(inSkin: name)

        guard fileManager.fileExists(atPath: sheetURL.path),
              fileManager.fileExists(atPath: manifestURL.path)
        else { return nil }

        let manifest: SkinManifest
        do {
            manifest = try SkinManifest.load(from: manifestURL)
            try manifest.validatePacked()
        } catch {
            Log.warning("Packed manifest at \(manifestURL.path) is unusable "
                + "(\(error)); falling back to src/ frames")
            return nil
        }

        let sheet = try loadImage(at: sheetURL)
        var animations: [String: SpriteAnimation] = [:]

        for state in manifest.states.keys.sorted() {
            guard let spec = manifest.states[state],
                  let row = spec.row,
                  let count = spec.frames,
                  count > 0
            else { continue }

            var frames: [CGImage] = []
            var masks: [AlphaMask] = []

            for column in 0..<count {
                // Nil here means the sheet is smaller than the manifest claims, which is a real
                // error rather than something to paper over.
                guard let frame = sheet.cropping(to: manifest.sheetFrameRect(row: row, column: column)),
                      let mask = AlphaMask(image: frame)
                else {
                    throw SpriteSourceError.unreadableImage(sheetURL)
                }
                frames.append(frame)
                masks.append(mask)
            }

            animations[state] = SpriteAnimation(state: state, spec: spec, frames: frames, masks: masks)
        }

        guard !animations.isEmpty else { return nil }
        return LoadedSkin(name: name, manifest: manifest, animations: animations, origin: .packedSheet)
    }

    /// Reads `Skins/<name>/src/<state>/*.png`, sorted by filename so `000.png` plays first.
    ///
    /// Required states (`idle`, `walk`) must have frames. Optional states are skipped with a
    /// warning, and the runtime falls back to `idle` for them.
    private static func loadFrameDirectories(
        manifest: SkinManifest,
        name: String,
        locator: AssetLocator,
        fileManager: FileManager
    ) throws -> [String: SpriteAnimation] {
        var animations: [String: SpriteAnimation] = [:]

        for state in manifest.states.keys.sorted() {
            guard let spec = manifest.states[state] else { continue }
            let directory = locator.sourceFramesDirectory(inSkin: name, state: state)
            let files = pngFiles(in: directory, fileManager: fileManager)

            guard !files.isEmpty else {
                if SkinManifest.requiredStates.contains(state) {
                    throw SpriteSourceError.emptyStateDirectory(state: state, directory: directory)
                }
                Log.warning("State \"\(state)\" has no frames in \(directory.path); it will fall back to idle")
                continue
            }

            var frames: [CGImage] = []
            var masks: [AlphaMask] = []

            for file in files {
                let image = try loadImage(at: file)
                let actual = SkinSize(width: image.width, height: image.height)
                guard actual == manifest.frameSize else {
                    throw SpriteSourceError.frameSizeMismatch(
                        state: state,
                        file: file,
                        expected: manifest.frameSize,
                        actual: actual
                    )
                }
                guard let mask = AlphaMask(image: image) else {
                    throw SpriteSourceError.unreadableImage(file)
                }
                frames.append(image)
                masks.append(mask)
            }

            animations[state] = SpriteAnimation(state: state, spec: spec, frames: frames, masks: masks)
        }

        return animations
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
            throw SpriteSourceError.unreadableImage(url)
        }
        return image
    }
}

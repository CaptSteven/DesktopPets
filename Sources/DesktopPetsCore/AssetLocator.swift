import Foundation

/// Finds the `Resources/` directory that holds `Skins/` and `Phrases/`.
///
/// Why this exists at all: `Resources/` is runtime content, not SPM bundle resources. Keeping it
/// out of `Package.swift` means adding a skin never touches the build definition, `build-app.sh`
/// can copy the directory wholesale, and you can tweak art and hit reload without rebuilding.
/// The cost is that we locate it ourselves, in three tiers:
///
/// 1. `DESKTOPPETS_RESOURCES` — explicit override, useful for trying a skin from anywhere.
/// 2. `Bundle.main.resourceURL` — the `.app` case, where resources sit in `Contents/Resources`.
/// 3. The source tree, derived from this file's compile-time path — the `swift run` case.
public struct AssetLocator: Equatable {
    public enum Source: String, Equatable {
        case environment
        case bundle
        case sourceTree
    }

    public static let environmentKey = "DESKTOPPETS_RESOURCES"

    /// Directory that contains `Skins/` and `Phrases/`.
    public let resourcesRoot: URL
    public let source: Source

    public init(resourcesRoot: URL, source: Source) {
        self.resourcesRoot = resourcesRoot
        self.source = source
    }

    public var skinsDirectory: URL {
        resourcesRoot.appendingPathComponent("Skins", isDirectory: true)
    }

    public var phrasesDirectory: URL {
        resourcesRoot.appendingPathComponent("Phrases", isDirectory: true)
    }

    public func skinDirectory(named name: String) -> URL {
        skinsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// The manifest the runtime should read: the packer's output when present, else the
    /// hand-written source manifest.
    public func runtimeManifestURL(inSkin name: String) -> URL {
        let build = skinDirectory(named: name).appendingPathComponent("build/skin.json")
        if FileManager.default.fileExists(atPath: build.path) { return build }
        return sourceManifestURL(inSkin: name)
    }

    public func sourceManifestURL(inSkin name: String) -> URL {
        skinDirectory(named: name).appendingPathComponent("skin.json")
    }

    /// The packer's generated manifest: the hand-written one plus `row` / `frames`.
    public func packedManifestURL(inSkin name: String) -> URL {
        skinDirectory(named: name).appendingPathComponent("build/skin.json")
    }

    /// The packer's generated sprite sheet, laid out according to the packed manifest.
    public func packedSheetURL(inSkin name: String) -> URL {
        skinDirectory(named: name).appendingPathComponent("build/sheet.png")
    }

    /// Where the packer writes per-state GIF previews, for eyeballing frame order and timing.
    public func previewDirectory(inSkin name: String) -> URL {
        skinDirectory(named: name).appendingPathComponent("preview", isDirectory: true)
    }

    /// Names of the skin directories available under `Skins/`, sorted for a stable default choice.
    ///
    /// A usable skin is any subdirectory; whether it actually loads is decided when parsing its
    /// manifest, so a broken skin reports a specific error rather than vanishing from the list.
    public func availableSkins(fileManager: FileManager = .default) -> [String] {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: skinsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return entries.compactMap { url -> String? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            let name = url.lastPathComponent
            return name.hasPrefix(".") ? nil : name
        }
        .sorted()
    }

    /// Frame directory for the pre-packing workflow: `Skins/<name>/src/<state>/*.png`.
    public func sourceFramesDirectory(inSkin name: String, state: String) -> URL {
        skinDirectory(named: name)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent(state, isDirectory: true)
    }

    // MARK: Resolution

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> AssetLocator? {
        if let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            if isResourcesRoot(url, fileManager: fileManager) {
                return AssetLocator(resourcesRoot: url, source: .environment)
            }
        }

        if let bundleResourceURL, isResourcesRoot(bundleResourceURL, fileManager: fileManager) {
            return AssetLocator(resourcesRoot: bundleResourceURL, source: .bundle)
        }

        if let found = sourceTreeResourcesRoot(fileManager: fileManager) {
            return AssetLocator(resourcesRoot: found, source: .sourceTree)
        }

        return nil
    }

    /// A usable resources root must actually contain a `Skins` directory; otherwise a stale or
    /// unrelated path would silently win over a good one.
    public static func isResourcesRoot(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let skins = url.appendingPathComponent("Skins", isDirectory: true)
        guard fileManager.fileExists(atPath: skins.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return true
    }

    /// Walks up from `start` looking for the first directory containing a `Resources/Skins` tree.
    public static func nearestResourcesRoot(
        startingAt start: URL,
        maxLevels: Int = 8,
        fileManager: FileManager = .default
    ) -> URL? {
        var directory = start
        for _ in 0..<maxLevels {
            let candidate = directory.appendingPathComponent("Resources", isDirectory: true)
            if isResourcesRoot(candidate, fileManager: fileManager) { return candidate }

            let parent = directory.deletingLastPathComponent()
            // Reached the filesystem root.
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    /// `Sources/DesktopPetsCore/AssetLocator.swift` -> repository root, at compile time.
    static let compileTimeFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    /// The source-tree tier. Always nil for a shipped `.app`, which is fine.
    public static func sourceTreeResourcesRoot(fileManager: FileManager = .default) -> URL? {
        nearestResourcesRoot(startingAt: compileTimeFileDirectory, fileManager: fileManager)
    }
}

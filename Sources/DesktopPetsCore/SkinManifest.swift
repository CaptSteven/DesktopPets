import CoreGraphics
import Foundation

/// Frame pixel dimensions as written in `skin.json`.
///
/// Deliberately not `CGSize`: `CGSize`'s synthesized `Codable` conformance encodes as a
/// two-element array (`[64, 64]`), which is unpleasant in a hand-edited file.
public struct SkinSize: Codable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }

    public var isPositive: Bool { width > 0 && height > 0 }
}

/// Where the pet's persistent "hotspot" sits inside its own frame.
///
/// The hotspot is the point whose screen coordinates get saved to `UserDefaults`, so the pet
/// reappears in the same place across launches. `bottomCenter` is the sensible default: the
/// hotspot is the pet's feet, which is what you want to pin to the bottom of the screen.
public enum Anchor: String, Codable, CaseIterable {
    case center
    case bottomCenter
    case topCenter
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

/// Per-state animation settings written by hand, plus `row` / `frames` filled in by `SkinPacker`.
public struct StateSpec: Codable, Equatable {
    /// Frames per second. The plan's 6-10fps range is typical, but nothing enforces that.
    public var fps: Double
    /// Whether the animation loops. `click` is the canonical non-looping state.
    public var loop: Bool
    /// Row index inside the packed sprite sheet. `nil` in the hand-written manifest.
    public var row: Int?
    /// Frame count for this state. `nil` in the hand-written manifest.
    public var frames: Int?

    public init(fps: Double, loop: Bool, row: Int? = nil, frames: Int? = nil) {
        self.fps = fps
        self.loop = loop
        self.row = row
        self.frames = frames
    }

    /// True when the packer has recorded where this state lives in the sheet.
    public var isPacked: Bool { row != nil && frames != nil }
}

public enum SkinManifestError: Error, CustomStringConvertible, Equatable {
    case unreadableFile(String)
    case invalidJSON(String)
    case emptyName
    case invalidFrameSize(width: Int, height: Int)
    case invalidScale(Double)
    case missingStates([String])
    case unknownStates([String])
    case invalidState(name: String, reason: String)
    case notPacked([String])

    public var description: String {
        switch self {
        case .unreadableFile(let path):
            return "Could not read skin manifest at \(path)"
        case .invalidJSON(let detail):
            return "Skin manifest is not valid JSON: \(detail)"
        case .emptyName:
            return "Skin manifest has an empty \"name\""
        case .invalidFrameSize(let width, let height):
            return "Skin \"frameSize\" must have positive width and height, got \(width)x\(height)"
        case .invalidScale(let scale):
            return "Skin \"scale\" must be positive, got \(scale)"
        case .missingStates(let states):
            return "Skin manifest is missing required state(s): \(states.sorted().joined(separator: ", "))"
        case .unknownStates(let states):
            return "Skin manifest declares unknown state(s): \(states.sorted().joined(separator: ", ")) "
                + "(known: \(SkinManifest.knownStates.sorted().joined(separator: ", ")))"
        case .invalidState(let name, let reason):
            return "Skin state \"\(name)\" is invalid: \(reason)"
        case .notPacked(let states):
            return "Skin manifest is missing packed row/frames for state(s): "
                + states.sorted().joined(separator: ", ")
        }
    }
}

/// The contract between the hand-drawn art in `Resources/Skins/<name>/` and the runtime.
///
/// Two files carry this shape: the hand-written `skin.json` (fps / loop / scale / anchor /
/// threshold) and the packer's generated `build/skin.json` (the same, plus `row` and `frames`).
public struct SkinManifest: Codable, Equatable {
    public var name: String
    public var frameSize: SkinSize
    /// Display scale. `2` renders a 64x64 frame as 128x128 points (i.e. a @2x asset).
    public var scale: Double
    public var anchor: Anchor
    /// Alpha at or above which a pixel counts as solid, for the `--verify-skin` coverage report.
    ///
    /// This used to drive per-pixel click-through, which is gone: the sprite window now takes
    /// clicks across its whole area, because tying "can I grab the pet" to the art meant a sparse
    /// or repositioned pose could make it unclickable. The field is kept so existing `skin.json`
    /// files stay valid, and it still gives the coverage report a threshold to work from.
    public var hitAlphaThreshold: UInt8
    public var states: [String: StateSpec]

    /// States the runtime knows how to drive. Anything else is a typo and gets rejected.
    ///
    /// `climb`, `mine`, `fight` and `tnt` are optional extras: the pet performs them on a whim, and
    /// a skin that does not provide them simply falls back to `idle` for those moments.
    public static let knownStates: Set<String> = [
        "idle", "walk", "drag", "sleep", "click",
        "climb", "mine", "fight", "tnt",
    ]
    /// `idle` is the universal fallback and `walk` is the point of the app; the rest are optional.
    public static let requiredStates: Set<String> = ["idle", "walk"]

    public static let defaultScale: Double = 1
    public static let defaultAnchor: Anchor = .bottomCenter
    public static let defaultHitAlphaThreshold: UInt8 = 16

    public init(
        name: String,
        frameSize: SkinSize,
        scale: Double = SkinManifest.defaultScale,
        anchor: Anchor = SkinManifest.defaultAnchor,
        hitAlphaThreshold: UInt8 = SkinManifest.defaultHitAlphaThreshold,
        states: [String: StateSpec]
    ) {
        self.name = name
        self.frameSize = frameSize
        self.scale = scale
        self.anchor = anchor
        self.hitAlphaThreshold = hitAlphaThreshold
        self.states = states
    }

    private enum CodingKeys: String, CodingKey {
        case name, frameSize, scale, anchor, hitAlphaThreshold, states
    }

    /// Custom decoding so a hand-written manifest can omit `scale`, `anchor` and the threshold.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        frameSize = try container.decode(SkinSize.self, forKey: .frameSize)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale
        anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? Self.defaultAnchor
        hitAlphaThreshold = try container.decodeIfPresent(UInt8.self, forKey: .hitAlphaThreshold)
            ?? Self.defaultHitAlphaThreshold
        states = try container.decode([String: StateSpec].self, forKey: .states)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(frameSize, forKey: .frameSize)
        try container.encode(scale, forKey: .scale)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(hitAlphaThreshold, forKey: .hitAlphaThreshold)
        try container.encode(states, forKey: .states)
    }
}

// MARK: - Validation

public extension SkinManifest {
    /// Throws a specific, human-readable error for everything that would otherwise fail later
    /// (or worse, fail silently) during rendering.
    func validate() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SkinManifestError.emptyName
        }
        if !frameSize.isPositive {
            throw SkinManifestError.invalidFrameSize(width: frameSize.width, height: frameSize.height)
        }
        if !(scale > 0) || !scale.isFinite {
            throw SkinManifestError.invalidScale(scale)
        }

        let declared = Set(states.keys)
        let unknown = declared.subtracting(Self.knownStates)
        if !unknown.isEmpty {
            throw SkinManifestError.unknownStates(Array(unknown))
        }
        let missing = Self.requiredStates.subtracting(declared)
        if !missing.isEmpty {
            throw SkinManifestError.missingStates(Array(missing))
        }

        for (stateName, spec) in states {
            if !(spec.fps > 0) || !spec.fps.isFinite {
                throw SkinManifestError.invalidState(name: stateName, reason: "fps must be positive, got \(spec.fps)")
            }
            if let frames = spec.frames, frames <= 0 {
                throw SkinManifestError.invalidState(name: stateName, reason: "frames must be positive, got \(frames)")
            }
            if let row = spec.row, row < 0 {
                throw SkinManifestError.invalidState(name: stateName, reason: "row must not be negative, got \(row)")
            }
            // row and frames are written together by the packer; half of a pair means a stale file.
            if (spec.row == nil) != (spec.frames == nil) {
                throw SkinManifestError.invalidState(
                    name: stateName,
                    reason: "row and frames must be present together"
                )
            }
        }
    }

    /// Extra check for the runtime sheet path: every state must know its slot in the sheet.
    func validatePacked() throws {
        try validate()
        let unpacked = states.filter { !$0.value.isPacked }.keys
        if !unpacked.isEmpty {
            throw SkinManifestError.notPacked(Array(unpacked))
        }
    }

    /// Validates, then returns self so it can be used inline in a builder chain.
    @discardableResult
    func validated() throws -> SkinManifest {
        try validate()
        return self
    }
}

// MARK: - Loading

public extension SkinManifest {
    static func decode(from data: Data) throws -> SkinManifest {
        let manifest: SkinManifest
        do {
            manifest = try JSONDecoder().decode(SkinManifest.self, from: data)
        } catch let error as SkinManifestError {
            throw error
        } catch {
            throw SkinManifestError.invalidJSON(String(describing: error))
        }
        try manifest.validate()
        return manifest
    }

    static func load(from url: URL) throws -> SkinManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SkinManifestError.unreadableFile(url.path)
        }
        return try decode(from: data)
    }

    /// Pretty-printed JSON, for the packer to write and for humans to diff.
    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - State lookup

public extension SkinManifest {
    subscript(state: String) -> StateSpec? { states[state] }

    /// Resolves the state to actually play. Unknown or absent states degrade to `idle` rather
    /// than crashing, so a skin with only `idle`/`walk` still runs.
    func fallbackState(for requested: String) -> String {
        if states[requested] != nil { return requested }
        if states["idle"] != nil { return "idle" }
        return states.keys.sorted().first ?? requested
    }

    /// Frame counts per state, taken from the packed manifest when available.
    var packedFrameCounts: [String: Int] {
        states.compactMapValues { $0.frames }
    }

    /// Number of rows needed to pack every state, one state per row.
    static func packedRowCount(for states: [String: StateSpec]) -> Int { states.count }

    /// Deterministic row assignment: alphabetical by state name, so re-packing never reshuffles.
    static func packedRows(for states: [String: StateSpec]) -> [(state: String, row: Int)] {
        states.keys.sorted().enumerated().map { (state: $0.element, row: $0.offset) }
    }

    /// Pixel size of the packed sheet: one row per state, one column per frame.
    ///
    /// Never zero in either dimension, so an empty or frame-less skin still yields a valid (if
    /// useless) bitmap context instead of a crash.
    static func packedSheetSize(for states: [String: StateSpec], frameSize: SkinSize) -> SkinSize {
        let columns = states.values.compactMap(\.frames).max() ?? 0
        return SkinSize(
            width: max(columns, 1) * frameSize.width,
            height: max(states.count, 1) * frameSize.height
        )
    }

    /// Location of a single frame inside the packed sheet, in **CGImage top-left origin**
    /// coordinates — the space `CGImage.cropping(to:)` expects.
    ///
    /// Row 0 is the top row. The packer draws into a bottom-left-origin `CGContext`, so it flips
    /// this rect on the way in; everything that *reads* the sheet (and every test) can use it
    /// directly.
    func sheetFrameRect(row: Int, column: Int) -> CGRect {
        let width = Double(frameSize.width)
        let height = Double(frameSize.height)
        return CGRect(
            x: Double(column) * width,
            y: Double(row) * height,
            width: width,
            height: height
        )
    }
}

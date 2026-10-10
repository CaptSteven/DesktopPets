import Foundation
@testable import DesktopPetsCore

// Gotcha worth knowing before adding assertions: Swift Testing captures each side of a comparison
// independently. When one side is `CGFloat` and the other is a *compound* expression such as
// `-200 + 1080 - 64`, the right-hand side is inferred as `Int` and the comparison returns false
// even when the numbers are equal. Bare literals are fine (`clamped.x == 468` works).
//
// Always compare against a typed value instead:
//
//     let expectedY = frame.maxY - size.height   // CGFloat
//     #expect(clamped.y == expectedY)


/// A throwaway `UserDefaults` suite that cleans up after itself.
///
/// `UserDefaults(suiteName:)` writes a real `~/Library/Preferences/<name>.plist`, and `cfprefsd`
/// keeps the file around even after `removePersistentDomain`. Two things keep a test run from
/// littering the user's home directory: callers pass a *fixed* suite name rather than a fresh UUID
/// per test (so a run creates at most one file, not one per test), and `deinit` deletes both the
/// domain and the file.
///
/// Because the name is shared, suites using this must be `.serialized` so tests cannot interfere.
final class EphemeralDefaults {
    let name: String
    let store: ConfigStore

    init(name: String) {
        self.name = name
        self.store = ConfigStore.ephemeral(name: name)
    }

    /// A raw `UserDefaults` over the same suite, for tests that need to poke values directly.
    var raw: UserDefaults {
        UserDefaults(suiteName: name) ?? .standard
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: name)
        UserDefaults.standard.synchronize()

        // cfprefsd usually leaves the backing file behind; take it out too.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}

/// Deterministic RNG (splitmix64) so tests can assert on "random" choices.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any seed works; mixing avoids a low-entropy first draw for small seeds.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A temporary directory that cleans itself up when the test finishes.
final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopPetsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates intermediate directories and writes `contents`, returning the file URL.
    @discardableResult
    func write(_ relativePath: String, _ contents: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
        return file
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let directory = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }
}

/// A manifest JSON body with placeholders, so each test only spells out the part it cares about.
func makeManifestJSON(
    name: String = "cat",
    frameWidth: Int = 64,
    frameHeight: Int = 64,
    scale: String? = nil,
    anchor: String? = nil,
    hitAlphaThreshold: String? = nil,
    states: String = """
        "idle": { "fps": 6, "loop": true },
        "walk": { "fps": 10, "loop": true }
        """
) -> String {
    var fields = [
        "\"name\": \"\(name)\"",
        "\"frameSize\": { \"width\": \(frameWidth), \"height\": \(frameHeight) }",
    ]
    if let scale { fields.append("\"scale\": \(scale)") }
    if let anchor { fields.append("\"anchor\": \"\(anchor)\"") }
    if let hitAlphaThreshold { fields.append("\"hitAlphaThreshold\": \(hitAlphaThreshold)") }
    fields.append("\"states\": { \(states) }")
    return "{ \(fields.joined(separator: ",\n  ")) }"
}

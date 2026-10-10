import Foundation

// Gotcha worth knowing before adding assertions: Swift Testing captures each side of a comparison
// independently. When one side is `CGFloat` and the other is a *compound* expression such as
// `-200 + 1080 - 64`, the right-hand side is inferred as `Int` and the comparison returns false
// even when the numbers are equal. Bare literals are fine (`clamped.x == 468` works).
//
// Always compare against a typed value instead:
//
//     let expectedY = frame.maxY - size.height   // CGFloat
//     #expect(clamped.y == expectedY)


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

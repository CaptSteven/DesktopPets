import Foundation
import Testing
@testable import DesktopPetsCore

@Suite struct SkinManifestTests {
    // MARK: Defaults

    @Test func handWrittenManifestOmitsOptionalFieldsAndGetsDefaults() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))

        #expect(manifest.name == "cat")
        #expect(manifest.frameSize == SkinSize(width: 64, height: 64))
        #expect(manifest.scale == 1)
        #expect(manifest.anchor == .bottomCenter)
        #expect(manifest.hitAlphaThreshold == 16)
        #expect(Set(manifest.states.keys) == ["idle", "walk"])
        #expect(manifest.states["idle"]?.fps == 6)
        #expect(manifest.states["idle"]?.loop == true)
        #expect(manifest.states["click"] == nil, "undeclared states stay absent")
    }

    @Test func explicitFieldsOverrideDefaults() throws {
        let json = makeManifestJSON(scale: "2", anchor: "topRight", hitAlphaThreshold: "40")
        let manifest = try SkinManifest.decode(from: Data(json.utf8))

        #expect(manifest.scale == 2)
        #expect(manifest.anchor == .topRight)
        #expect(manifest.hitAlphaThreshold == 40)
    }

    @Test func allKnownStatesAreAccepted() throws {
        let states = SkinManifest.knownStates.sorted()
            .map { "\"\($0)\": { \"fps\": 8, \"loop\": true }" }
            .joined(separator: ",\n  ")
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))

        #expect(Set(manifest.states.keys) == SkinManifest.knownStates)
    }

    // MARK: Validation failures

    @Test func typoedStateNameIsRejectedRatherThanSilentlyIgnored() throws {
        let states = """
            "idle": { "fps": 6, "loop": true },
            "walk": { "fps": 10, "loop": true },
            "sllep": { "fps": 3, "loop": true }
            """
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        }
        guard case .unknownStates(let unknown) = error else {
            Issue.record("expected unknownStates, got \(String(describing: error))")
            return
        }
        #expect(unknown == ["sllep"])
    }

    @Test func missingIdleIsRejected() throws {
        let states = #""walk": { "fps": 10, "loop": true }"#
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        }
        guard case .missingStates(let missing) = error else {
            Issue.record("expected missingStates, got \(String(describing: error))")
            return
        }
        #expect(missing == ["idle"])
    }

    @Test func missingWalkIsRejected() throws {
        let states = #""idle": { "fps": 6, "loop": true }"#
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        }
        guard case .missingStates(let missing) = error else {
            Issue.record("expected missingStates, got \(String(describing: error))")
            return
        }
        #expect(missing == ["walk"])
    }

    @Test func nonPositiveFrameSizeIsRejected() {
        let json = makeManifestJSON(frameHeight: 0)
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(json.utf8))
        }
        #expect(error == .invalidFrameSize(width: 64, height: 0))
    }

    @Test func nonPositiveScaleIsRejected() {
        let json = makeManifestJSON(scale: "0")
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(json.utf8))
        }
        #expect(error == .invalidScale(0))
    }

    @Test func emptyNameIsRejected() {
        let json = makeManifestJSON(name: "   ")
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(json.utf8))
        }
        #expect(error == .emptyName)
    }

    @Test func nonPositiveFPSIsRejected() throws {
        let states = """
            "idle": { "fps": 0, "loop": true },
            "walk": { "fps": 10, "loop": true }
            """
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        }
        guard case .invalidState(let name, _) = error else {
            Issue.record("expected invalidState, got \(String(describing: error))")
            return
        }
        #expect(name == "idle")
    }

    @Test func halfRecordedRowFramesPairIsRejected() throws {
        let states = """
            "idle": { "fps": 6, "loop": true, "row": 0 },
            "walk": { "fps": 10, "loop": true }
            """
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        }
        #expect(error == .invalidState(name: "idle", reason: "row and frames must be present together"))
    }

    @Test func malformedJSONReportsInvalidJSON() {
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.decode(from: Data("{ not json".utf8))
        }
        guard case .invalidJSON = error else {
            Issue.record("expected invalidJSON, got \(String(describing: error))")
            return
        }
    }

    @Test func missingFileReportsUnreadableFile() {
        let missing = URL(fileURLWithPath: "/definitely/not/here/skin.json")
        let error = #expect(throws: SkinManifestError.self) {
            try SkinManifest.load(from: missing)
        }
        #expect(error == .unreadableFile(missing.path))
    }

    // MARK: Packing

    @Test func validatePackedRequiresRowAndFramesOnEveryState() throws {
        let unpacked = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))
        let error = #expect(throws: SkinManifestError.self) {
            try unpacked.validatePacked()
        }
        guard case .notPacked(let states) = error else {
            Issue.record("expected notPacked, got \(String(describing: error))")
            return
        }
        #expect(Set(states) == ["idle", "walk"])
    }

    @Test func packedManifestPassesValidationAndExposesFrameCounts() throws {
        let states = """
            "idle": { "fps": 6, "loop": true, "row": 0, "frames": 4 },
            "walk": { "fps": 10, "loop": true, "row": 1, "frames": 6 }
            """
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))

        #expect(throws: Never.self) { try manifest.validatePacked() }
        #expect(manifest.packedFrameCounts == ["idle": 4, "walk": 6])
        #expect(manifest.states["idle"]?.isPacked == true)
    }

    @Test func rowAssignmentIsAlphabeticalSoRepackingDoesNotReshuffle() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))
        let rows = SkinManifest.packedRows(for: manifest.states)

        #expect(rows.map { $0.state } == ["idle", "walk"])
        #expect(rows.map { $0.row } == [0, 1])

        // The same input in a different insertion order must produce the same rows.
        let reshuffled: [String: StateSpec] = [
            "walk": manifest.states["walk"]!,
            "idle": manifest.states["idle"]!,
        ]
        #expect(SkinManifest.packedRows(for: reshuffled).map { $0.state } == ["idle", "walk"])
    }

    // MARK: Round trip

    @Test func encodeDecodeRoundTripPreservesEverything() throws {
        let json = makeManifestJSON(
            name: "shiba",
            scale: "2",
            anchor: "bottomLeft",
            hitAlphaThreshold: "24",
            states: """
                "idle": { "fps": 6, "loop": true, "row": 0, "frames": 4 },
                "walk": { "fps": 10, "loop": true, "row": 1, "frames": 6 }
                """
        )
        let original = try SkinManifest.decode(from: Data(json.utf8))

        let restored = try SkinManifest.decode(from: original.encodedJSON())

        #expect(restored == original)
    }

    @Test func encodedJSONIsSortedAndPrettyPrinted() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))
        let text = String(decoding: try manifest.encodedJSON(), as: UTF8.self)

        #expect(text.contains("\n"), "expected pretty-printed output")
        let anchorRange = try #require(text.range(of: "\"anchor\""))
        let nameRange = try #require(text.range(of: "\"name\""))
        #expect(anchorRange.lowerBound < nameRange.lowerBound, "expected keys in sorted order")
    }

    // MARK: State lookup

    @Test func fallbackStateDegradesToIdle() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))

        #expect(manifest.fallbackState(for: "idle") == "idle")
        #expect(manifest.fallbackState(for: "walk") == "walk")
        // Not declared in this skin, so it falls back rather than crashing.
        #expect(manifest.fallbackState(for: "sleep") == "idle")
        #expect(manifest.fallbackState(for: "nonsense") == "idle")
    }

    @Test func fallbackStateUsesAnyAvailableStateWhenIdleIsAbsent() {
        // validate() requires idle, but a hand-built manifest may not have it.
        let manifest = SkinManifest(
            name: "odd",
            frameSize: SkinSize(width: 8, height: 8),
            states: ["walk": StateSpec(fps: 8, loop: true)]
        )
        #expect(manifest.fallbackState(for: "click") == "walk")
    }

    @Test func subscriptAccessesStates() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))
        #expect(manifest["walk"]?.fps == 10)
        #expect(manifest["click"] == nil)
    }

    @Test func windowSizeScalesFrameSize() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON(scale: "2").utf8))
        let size = PetLayout.windowSize(frameSize: manifest.frameSize, scale: manifest.scale)

        #expect(size.width == 128)
        #expect(size.height == 128)
    }

    // MARK: Packed sheet geometry

    @Test func sheetFrameRectAddressesFramesInTopLeftCoordinates() throws {
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON().utf8))

        // Row 0 is the *top* row, which in CGImage cropping coordinates means y = 0.
        #expect(manifest.sheetFrameRect(row: 0, column: 0) == CGRect(x: 0, y: 0, width: 64, height: 64))
        #expect(manifest.sheetFrameRect(row: 0, column: 2) == CGRect(x: 128, y: 0, width: 64, height: 64))
        #expect(manifest.sheetFrameRect(row: 1, column: 0) == CGRect(x: 0, y: 64, width: 64, height: 64))
        #expect(manifest.sheetFrameRect(row: 3, column: 4) == CGRect(x: 256, y: 192, width: 64, height: 64))
    }

    @Test func sheetFrameRectsTileWithoutOverlapAndFitTheSheet() throws {
        let states = """
            "idle": { "fps": 6, "loop": true, "row": 0, "frames": 3 },
            "walk": { "fps": 10, "loop": true, "row": 1, "frames": 3 }
            """
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))

        var rects: [CGRect] = []
        for row in 0..<2 {
            for column in 0..<3 {
                rects.append(manifest.sheetFrameRect(row: row, column: column))
            }
        }

        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                #expect(!rect.intersects(other), "\(rect) overlaps \(other)")
            }
        }

        // And they must fit inside the sheet the packer allocates.
        let size = SkinManifest.packedSheetSize(for: manifest.states, frameSize: manifest.frameSize)
        for rect in rects {
            #expect(rect.maxX <= Double(size.width))
            #expect(rect.maxY <= Double(size.height))
        }
    }

    @Test func packedSheetSizeUsesTheWidestStateAndOneRowEach() throws {
        let states = """
            "idle": { "fps": 6, "loop": true, "row": 0, "frames": 4 },
            "walk": { "fps": 10, "loop": true, "row": 1, "frames": 6 }
            """
        let manifest = try SkinManifest.decode(from: Data(makeManifestJSON(states: states).utf8))
        let size = SkinManifest.packedSheetSize(for: manifest.states, frameSize: manifest.frameSize)

        #expect(size == SkinSize(width: 6 * 64, height: 2 * 64))
    }

    @Test func packedSheetSizeIsNeverZero() {
        let frameSize = SkinSize(width: 64, height: 64)

        // No states at all.
        #expect(SkinManifest.packedSheetSize(for: [:], frameSize: frameSize)
            == SkinSize(width: 64, height: 64))

        // A state declared without a frame count yet (the hand-written manifest case).
        let unrecorded = SkinManifest.packedSheetSize(
            for: ["idle": StateSpec(fps: 6, loop: true)],
            frameSize: frameSize
        )
        #expect(unrecorded == SkinSize(width: 64, height: 64))
    }
}

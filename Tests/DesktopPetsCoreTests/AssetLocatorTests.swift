import Foundation
import Testing
@testable import DesktopPetsCore

@Suite struct AssetLocatorTests {
    // MARK: isResourcesRoot

    @Test func resourcesRootRequiresASkinsDirectory() throws {
        let temp = try TempDirectory()

        #expect(!AssetLocator.isResourcesRoot(temp.url), "empty dir is not a resources root")

        // A file named Skins is not good enough; it has to be a directory.
        try temp.write("Skins", "i am a file")
        #expect(!AssetLocator.isResourcesRoot(temp.url))

        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("Skins"))
        try temp.makeDirectory("Skins")
        #expect(AssetLocator.isResourcesRoot(temp.url))
    }

    // MARK: Walking up the tree

    @Test func nearestResourcesRootWalksUpFromADeepDirectory() throws {
        let temp = try TempDirectory()
        try temp.makeDirectory("Resources/Skins")
        let deep = try temp.makeDirectory("Sources/DesktopPetsCore/Nested/EvenDeeper")

        let found = try #require(AssetLocator.nearestResourcesRoot(startingAt: deep))

        let expected = temp.url.appendingPathComponent("Resources").resolvingSymlinksInPath().path
        #expect(found.resolvingSymlinksInPath().path == expected)
    }

    @Test func nearestResourcesRootReturnsNilWhenThereIsNone() throws {
        let temp = try TempDirectory()
        let deep = try temp.makeDirectory("a/b/c")

        #expect(AssetLocator.nearestResourcesRoot(startingAt: deep) == nil)
    }

    @Test func nearestResourcesRootHonoursTheLevelLimit() throws {
        let temp = try TempDirectory()
        try temp.makeDirectory("Resources/Skins")
        let deep = try temp.makeDirectory("a/b/c/d/e/f")

        // One level of lookahead is not enough to reach the root from here.
        #expect(AssetLocator.nearestResourcesRoot(startingAt: deep, maxLevels: 1) == nil)
        #expect(AssetLocator.nearestResourcesRoot(startingAt: deep, maxLevels: 16) != nil)
    }

    // MARK: Tier 1 — environment

    @Test func environmentOverrideWins() throws {
        let temp = try TempDirectory()
        let resources = try makeResourcesRoot(in: temp, named: "Resources")
        try temp.write("Resources/Skins/mySkin/skin.json", "{}")

        let locator = AssetLocator.resolve(environment: [AssetLocator.environmentKey: resources.path])

        #expect(locator?.source == .environment)
        #expect(locator?.resourcesRoot.path == resources.path)
    }

    @Test func environmentOverrideExpandsTilde() throws {
        // A path that does not resolve falls through rather than being trusted blindly.
        let locator = AssetLocator.resolve(
            environment: [AssetLocator.environmentKey: "~/definitely-not-here"],
            bundleResourceURL: nil
        )
        #expect(locator?.source != .environment, "a missing path must not win over a good tier")
    }

    @Test func blankEnvironmentOverrideIsIgnored() throws {
        let temp = try TempDirectory()
        let bundleRoot = try makeResourcesRoot(in: temp, named: "BundleResources")

        let locator = AssetLocator.resolve(
            environment: [AssetLocator.environmentKey: "   "],
            bundleResourceURL: bundleRoot
        )

        #expect(locator?.source == .bundle, "a blank override must not shadow a valid bundle")
    }

    @Test func unusableEnvironmentOverrideFallsThroughToTheBundle() throws {
        let temp = try TempDirectory()
        let bundleRoot = try makeResourcesRoot(in: temp, named: "BundleResources")

        let locator = AssetLocator.resolve(
            environment: [AssetLocator.environmentKey: "/nope/not/real"],
            bundleResourceURL: bundleRoot
        )

        #expect(locator?.source == .bundle)
    }

    // MARK: Tier 2 — bundle

    @Test func bundleResourceURLIsUsedWhenItContainsSkins() throws {
        let temp = try TempDirectory()
        let bundleRoot = try makeResourcesRoot(in: temp, named: "AppResources")

        let locator = try #require(AssetLocator.resolve(environment: [:], bundleResourceURL: bundleRoot))

        #expect(locator.source == .bundle)
        #expect(locator.resourcesRoot.path == bundleRoot.path)
        #expect(locator.skinsDirectory.path == bundleRoot.appendingPathComponent("Skins").path)
        #expect(locator.phrasesDirectory.path == bundleRoot.appendingPathComponent("Phrases").path)
    }

    @Test func bundleResourceURLWithoutSkinsIsRejected() throws {
        let temp = try TempDirectory()
        let empty = try temp.makeDirectory("EmptyResources")

        // With no bundle resources and no source tree match, resolution fails loudly rather
        // than pointing at a directory that cannot possibly work.
        let locator = AssetLocator.resolve(environment: [:], bundleResourceURL: empty)
        #expect(locator?.source != .bundle)
    }

    // MARK: Tier 3 — source tree

    @Test func sourceTreeTierResolvesInsideThisRepository() throws {
        // The real repo must be discoverable from this file's compile-time location, otherwise
        // `swift run` cannot find its art.
        let root = try #require(
            AssetLocator.sourceTreeResourcesRoot(),
            "Resources/Skins is missing from the source tree"
        )

        #expect(root.path.hasSuffix("/Resources"), "unexpected root: \(root.path)")
        #expect(AssetLocator.isResourcesRoot(root))
    }

    // MARK: Manifest precedence

    @Test func runtimeManifestPrefersThePackedBuildOutput() throws {
        let temp = try TempDirectory()
        let resources = try makeResourcesRoot(in: temp, named: "Resources")
        try temp.write("Resources/Skins/mySkin/skin.json", #"{ "hand": "written" }"#)

        let locator = AssetLocator(resourcesRoot: resources, source: .sourceTree)

        // Before packing, the hand-written manifest is the only one.
        #expect(locator.runtimeManifestURL(inSkin: "mySkin").deletingLastPathComponent().lastPathComponent
            == "mySkin")

        // After packing, the generated one takes over.
        try temp.write("Resources/Skins/mySkin/build/skin.json", #"{ "packed": true }"#)
        #expect(locator.runtimeManifestURL(inSkin: "mySkin").deletingLastPathComponent().lastPathComponent
            == "build")
        // The source manifest is still reachable for the packer itself.
        #expect(locator.sourceManifestURL(inSkin: "mySkin").deletingLastPathComponent().lastPathComponent
            == "mySkin")
    }

    @Test func sourceFramesDirectoryLayout() {
        let locator = AssetLocator(resourcesRoot: URL(fileURLWithPath: "/r"), source: .sourceTree)

        #expect(locator.sourceFramesDirectory(inSkin: "cat", state: "walk").path == "/r/Skins/cat/src/walk")
    }

    @Test func packedArtifactPathsSitBesideTheSourceArt() {
        let locator = AssetLocator(resourcesRoot: URL(fileURLWithPath: "/r"), source: .sourceTree)

        #expect(locator.sourceManifestURL(inSkin: "cat").path == "/r/Skins/cat/skin.json")
        #expect(locator.packedManifestURL(inSkin: "cat").path == "/r/Skins/cat/build/skin.json")
        #expect(locator.packedSheetURL(inSkin: "cat").path == "/r/Skins/cat/build/sheet.png")
        #expect(locator.previewDirectory(inSkin: "cat").path == "/r/Skins/cat/preview")
    }

    // MARK: Skin discovery

    @Test func availableSkinsListsDirectoriesSorted() throws {
        let temp = try TempDirectory()
        try temp.makeDirectory("Resources/Skins/zebra")
        try temp.makeDirectory("Resources/Skins/alpaca")
        // Files are not skins, and neither are hidden directories.
        try temp.write("Resources/Skins/notes.txt", "not a skin")
        try temp.makeDirectory("Resources/Skins/.git")

        let locator = AssetLocator(
            resourcesRoot: temp.url.appendingPathComponent("Resources"),
            source: .sourceTree
        )

        #expect(locator.availableSkins() == ["alpaca", "zebra"])
    }

    @Test func availableSkinsIsEmptyWhenSkinsIsMissing() throws {
        let temp = try TempDirectory()
        let locator = AssetLocator(resourcesRoot: temp.url, source: .sourceTree)

        #expect(locator.availableSkins().isEmpty)
    }

    // MARK: Helpers

    /// Creates `<temp>/<name>/Skins/placeholder` and returns `<temp>/<name>`.
    private func makeResourcesRoot(in temp: TempDirectory, named name: String) throws -> URL {
        try temp.makeDirectory("\(name)/Skins/placeholder")
        return temp.url.appendingPathComponent(name, isDirectory: true)
    }
}

// swift-tools-version: 5.9
import Foundation
import PackageDescription

// CommandLineTools ships the Swift Testing framework and its macro plugin, but SwiftPM does not
// always pass `-plugin-path` for the macro plugin (it lives in a `testing/` subdirectory that the
// default plugin search does not cover). Without it the `@Test` / `@Suite` / `#expect` macros fail
// to expand with "plugin for module 'TestingMacros' not found".
//
// Deriving the path from the active toolchain keeps this working whether the selected developer
// directory is CommandLineTools or a full Xcode install.
let testingMacroPluginPath: String? = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--find", "swiftc"]
    process.standardError = Pipe()
    let stdout = Pipe()
    process.standardOutput = stdout

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    let swiftc = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !swiftc.isEmpty else { return nil }

    // Walk up from the compiler to the toolchain root, then look for the plugin where it lives.
    // Note this is three levels above swiftc (`<root>/usr/bin/swiftc`), which is easy to get wrong.
    var directory = URL(fileURLWithPath: swiftc).deletingLastPathComponent()
    for _ in 0..<4 {
        let candidate = directory.appendingPathComponent("usr/lib/swift/host/plugins/testing").path
        if FileManager.default.fileExists(atPath: candidate) { return candidate }

        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path { break }
        directory = parent
    }
    return nil
}()

let testSwiftSettings: [SwiftSetting] = testingMacroPluginPath
    .map { [.unsafeFlags(["-plugin-path", $0])] } ?? []

let package = Package(
    name: "DesktopPets",
    // macOS 14 is the floor because the Swift Testing framework bundled with the toolchain is
    // built against 14.0; linking it from a 13.0 deployment target produces a load-command warning.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DesktopPets", targets: ["DesktopPets"]),
        // Build-time art tool. Not shipped in the app bundle.
        .executable(name: "SkinPacker", targets: ["SkinPacker"]),
        .library(name: "DesktopPetsCore", targets: ["DesktopPetsCore"]),
    ],
    targets: [
        // Pure logic: config, skin manifests, layout math, escaping, phrase picking.
        // Kept free of AppKit so it can be unit tested without a window server.
        .target(name: "DesktopPetsCore"),

        // AppKit UI shell.
        .executableTarget(
            name: "DesktopPets",
            dependencies: ["DesktopPetsCore"]
        ),

        // Packs `Skins/<name>/src/<state>/*.png` into a sprite sheet, and emits GIF previews.
        .executableTarget(
            name: "SkinPacker",
            dependencies: ["DesktopPetsCore"]
        ),

        .testTarget(
            name: "DesktopPetsCoreTests",
            dependencies: ["DesktopPetsCore"],
            swiftSettings: testSwiftSettings
        ),
    ]
)

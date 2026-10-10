import DesktopPetsCore
import Foundation

// SkinPacker [skin-name ...]
//
// Packs each named skin — or every skin found — from loose frames into a sprite sheet with GIF
// previews. See `Scripts/pack-skins.sh` for the usual entry point.

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        Usage: swift run SkinPacker [skin-name ...]

        Reads  Resources/Skins/<name>/src/<state>/*.png
        Writes Resources/Skins/<name>/build/sheet.png
               Resources/Skins/<name>/build/skin.json    (source manifest + row / frames)
               Resources/Skins/<name>/preview/<state>.gif

        With no arguments, every skin under Resources/Skins is packed.
        """)
    exit(0)
}

let requested = arguments.filter { !$0.hasPrefix("-") }

guard let locator = AssetLocator.resolve() else {
    FileHandle.standardError.write(
        Data("SkinPacker: could not find a Resources/Skins directory\n".utf8)
    )
    exit(1)
}

let names = requested.isEmpty ? locator.availableSkins() : requested

guard !names.isEmpty else {
    FileHandle.standardError.write(
        Data("SkinPacker: no skins found in \(locator.skinsDirectory.path)\n".utf8)
    )
    exit(1)
}

var failures = 0
for name in names {
    do {
        let result = try Packer.pack(skinNamed: name, from: locator)
        print("Packed \"\(result.skinName)\"")
        print("  sheet:    \(result.sheetURL.path)")
        print("  manifest: \(result.manifestURL.path)")
        for state in result.states {
            print("  \(state.name): \(state.frameCount) frame(s) at row \(state.row)"
                + " -> preview/\(state.previewURL.lastPathComponent)")
        }

        // Reading the sheet back and comparing against the source PNGs is the only way to know the
        // row/column/flip math is right; it is cheap, so it always runs.
        let report = try Packer.verifySheet(skinNamed: name, from: locator)
        if report.isIdentical {
            print("  verify:   \(report.comparisons.count) frame(s) identical to src/")
        } else {
            FileHandle.standardError.write(Data("""
                SkinPacker: \(name): sheet does not match src/ frames \
                (\(report.mismatches.count) of \(report.comparisons.count) differ, \
                worst channel delta \(report.worstDifference))

                """.utf8))
            for mismatch in report.mismatches.prefix(10) {
                FileHandle.standardError.write(Data(
                    "  \(mismatch.state) frame \(mismatch.frame): delta \(mismatch.maxChannelDifference)\n".utf8
                ))
            }
            failures += 1
        }
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        FileHandle.standardError.write(Data("SkinPacker: \(name): \(message)\n".utf8))
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)

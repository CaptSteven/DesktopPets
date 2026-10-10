import DesktopPetsCore
import Foundation
import ImageIO

/// Headless check that a skin on disk loads, printing what the runtime would draw.
///
/// The app target is an executable, so the test target cannot import it. This is how the loading
/// path gets verified without a window server, and it doubles as the smoke test that
/// `Scripts/build-app.sh` runs against a freshly built `.app`.
enum SkinVerifier {
    static func run() -> Never {
        do {
            guard let locator = AssetLocator.resolve() else {
                throw SpriteSourceError.noSkinsFound(
                    URL(fileURLWithPath: "Resources/Skins", isDirectory: true)
                )
            }

            print("Resources: \(locator.resourcesRoot.path) (via \(locator.source.rawValue))")

            let available = locator.availableSkins()
            print("Skins: \(available.isEmpty ? "<none>" : available.joined(separator: ", "))")

            guard let name = available.first else {
                throw SpriteSourceError.noSkinsFound(locator.skinsDirectory)
            }

            let skin = try SpriteSource.loadSkin(named: name, from: locator)
            let windowSize = PetLayout.windowSize(
                frameSize: skin.manifest.frameSize,
                scale: skin.manifest.scale
            )

            print("""
                Skin: \(skin.name) (from \(skin.origin.rawValue))
                  frame: \(skin.manifest.frameSize.width)x\(skin.manifest.frameSize.height) \
                @\(skin.manifest.scale)x -> window \(Int(windowSize.width))x\(Int(windowSize.height))
                  anchor: \(skin.manifest.anchor.rawValue), hit alpha >= \(skin.manifest.hitAlphaThreshold)
                """)

            for state in skin.animations.keys.sorted() {
                guard let animation = skin.animations[state] else { continue }
                let opacity = opaqueFraction(of: animation.masks[0])
                print("  \(state): \(animation.frameCount) frame(s) @ \(animation.spec.fps)fps "
                    + "loop=\(animation.spec.loop) opaque=\(Int(opacity * 100))%")
            }

            try reportPhrases(from: locator)

            print("OK")
            exit(0)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            Log.error(message)
            exit(1)
        }
    }

    /// Reports the phrase book, and checks that every category the pet can ask for exists.
    ///
    /// A missing category is not fatal — the pet falls back to `idle` — but it is worth flagging,
    /// because a typo in a `.json` key would otherwise only show up as "the pet never talks".
    private static func reportPhrases(from locator: AssetLocator) throws {
        let book = try PhraseBook.loadDirectory(at: locator.phrasesDirectory)

        if book.isEmpty {
            print("Phrases: none found in \(locator.phrasesDirectory.path) — the pet will stay quiet")
            return
        }

        print("Phrases: \(locator.phrasesDirectory.path)")
        for category in book.allCategories {
            print("  \(category): \(book.phrases(for: category).count) phrase(s)")
        }

        let missing = SpeechEvent.allCases
            .map(\.rawValue)
            .filter { book.isEmpty(for: $0) }
        if !missing.isEmpty {
            print("  note: no phrases for \(missing.joined(separator: ", ")); "
                + "those reactions will fall back to idle")
        }
    }

    /// Share of the frame that is clickable. A sprite with a fully opaque bounding box has no
    /// click-through, so this is worth surfacing.
    private static func opaqueFraction(of mask: AlphaMask) -> Double {
        guard mask.width > 0, mask.height > 0 else { return 0 }
        var opaque = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.alpha(atX: x, y: y) >= 16 {
                opaque += 1
            }
        }
        return Double(opaque) / Double(mask.width * mask.height)
    }
}

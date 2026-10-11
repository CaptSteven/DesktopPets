#!/usr/bin/env swift
//
// Generates the placeholder skin: a simple front-facing critter drawn with Core Graphics.
//
// This exists so the app is runnable and reviewable before real art exists. It writes
// Resources/Skins/placeholder/ in exactly the layout the runtime expects:
//
//   skin.json                  hand-written manifest (fps / loop / scale / anchor / threshold)
//   src/<state>/NNN.png        loose frames, sorted by filename
//
// Replace it with your own art whenever you like; deleting this directory is harmless.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Configuration

let frameSize = 64

/// Matches `SkinManifest.knownStates`. `click` is the one non-looping state.
let states: [(name: String, fps: Double, loop: Bool, frames: Int)] = [
    ("idle", 6, true, 4),
    // Ten frames rather than six: a walk cycle reads much better with a proper contact, down,
    // passing and up per step, and the packer does not care how many there are.
    ("walk", 12, true, 10),
    ("drag", 8, true, 4),
    ("sleep", 3, true, 4),
    ("click", 12, false, 6),
    ("climb", 8, true, 6),
    ("mine", 10, true, 8),
    ("fight", 10, true, 8),
    ("tnt", 10, false, 10),
]

// MARK: - Palette

struct Palette {
    let body: CGColor
    let belly: CGColor
    let accent: CGColor
    let ink: CGColor
    let z: CGColor
}

extension Palette {
    static let ginger = Palette(
        body: CGColor(red: 0.95, green: 0.65, blue: 0.35, alpha: 1),
        belly: CGColor(red: 1.0, green: 0.85, blue: 0.70, alpha: 1),
        accent: CGColor(red: 0.88, green: 0.55, blue: 0.30, alpha: 1),
        ink: CGColor(red: 0.23, green: 0.16, blue: 0.13, alpha: 1),
        z: CGColor(red: 0.55, green: 0.60, blue: 0.65, alpha: 1)
    )

    static let grey = Palette(
        body: CGColor(red: 0.60, green: 0.64, blue: 0.72, alpha: 1),
        belly: CGColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1),
        accent: CGColor(red: 0.46, green: 0.50, blue: 0.58, alpha: 1),
        ink: CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1),
        z: CGColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1)
    )
}

/// The example library this script writes.
///
/// Two layouts are demonstrated on purpose, because they are the two ways to organise art:
///
///   - `placeholder`       a skin at the top level of `Resources/Skins`
///   - `placeholder/grey`  a *variant* of the same character, one level down
///
/// Both appear in the right-click skin picker. The framing is identical between them and only the
/// palette differs, so a switch is obvious at a glance.
let skins: [(identifier: String, palette: Palette)] = [
    ("placeholder", .ginger),
    ("placeholder/grey", .grey),
]

// MARK: - Pose

/// Something the pet can be holding, used by the performance animations.
enum HeldItem {
    case none
    case pickaxe
    case sword
    case tnt
}

/// Every knob the drawing routine reacts to. Each state animates a few of these.
struct Pose {
    /// Vertical shift of the whole body, in points.
    var bodyOffsetY: Double = 0
    /// Vertical squash, 1.0 is neutral.
    var squash: Double = 1
    /// Horizontal stretch, 1.0 is neutral.
    var stretch: Double = 1
    /// How far the left and right foot lift off the ground.
    var leftFootLift: Double = 0
    var rightFootLift: Double = 0
    /// 1.0 = eyes wide open, 0.0 = shut.
    var eyeOpen: Double = 1
    /// 0 = arms tucked in, 1 = raised overhead.
    var armsUp: Double = 0
    /// Lying down for a nap: flattens the body and hides the feet.
    var lyingDown: Bool = false
    /// Sways the body, for dangling while dragged.
    var sway: Double = 0
    /// Draws sleeping "z"s, higher is further along the cycle.
    var sleepZPhase: Double? = nil
    /// Draws a surprise mark when > 0.
    var surprise: Double = 0
    /// What the pet is holding, if anything.
    var item: HeldItem = .none
    /// Swing angle of the held item, in radians. Negative is raised behind the head.
    var itemSwing: Double = 0
    /// Where a thrown item has flown to, relative to the pet. nil means still in hand.
    var thrownOffset: CGPoint? = nil
    /// Draws a blast, 1.0 being the brightest moment.
    var blast: Double = 0
    /// Both arms raised together, as when gripping a ladder.
    var climbing: Bool = false
}

// MARK: - Drawing

func makeContext() -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: frameSize,
        height: frameSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("could not create a drawing context")
    }
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: frameSize, height: frameSize))
    return context
}

func fillEllipse(_ context: CGContext, centreX: Double, centreY: Double, width: Double, height: Double, colour: CGColor) {
    context.setFillColor(colour)
    context.fillEllipse(in: CGRect(
        x: centreX - width / 2,
        y: centreY - height / 2,
        width: width,
        height: height
    ))
}

func drawCritter(_ context: CGContext, pose: Pose, palette: Palette) {
    let centreX = Double(frameSize) / 2 + pose.sway

    // Body. Lying down squashes it and drops it towards the floor.
    let bodyHeight = (pose.lyingDown ? 22.0 : 30.0) * pose.squash
    let bodyWidth = (pose.lyingDown ? 42.0 : 34.0) * pose.stretch
    let baseBodyY = pose.lyingDown ? 22.0 : 30.0
    let bodyY = baseBodyY + pose.bodyOffsetY
    let bodyTop = bodyY + bodyHeight / 2

    // Tail, off to one side so left/right facing is visible when the sprite is flipped.
    fillEllipse(context, centreX: centreX - bodyWidth / 2 - 2, centreY: bodyY - 2,
                width: 14, height: 9, colour: palette.accent)

    // Ears, behind the body.
    for direction in [-1.0, 1.0] {
        let earX = centreX + direction * bodyWidth * 0.28
        context.setFillColor(palette.accent)
        context.move(to: CGPoint(x: earX - 6, y: bodyTop - 4))
        context.addLine(to: CGPoint(x: earX + direction * 1.5, y: bodyTop + (pose.lyingDown ? 4 : 12)))
        context.addLine(to: CGPoint(x: earX + 6, y: bodyTop - 4))
        context.closePath()
        context.fillPath()
    }

    // Belly patch.
    fillEllipse(context, centreX: centreX, centreY: bodyY - bodyHeight * 0.12,
                width: bodyWidth * 0.5, height: bodyHeight * 0.45, colour: palette.belly)

    // Body.
    fillEllipse(context, centreX: centreX, centreY: bodyY,
                width: bodyWidth, height: bodyHeight, colour: palette.body)

    // Feet. Hidden while lying down, and lifted by the walk cycle.
    if !pose.lyingDown {
        fillEllipse(context, centreX: centreX - bodyWidth * 0.26, centreY: bodyY - bodyHeight / 2 + pose.leftFootLift,
                    width: 11, height: 7, colour: palette.accent)
        fillEllipse(context, centreX: centreX + bodyWidth * 0.26, centreY: bodyY - bodyHeight / 2 + pose.rightFootLift,
                    width: 11, height: 7, colour: palette.accent)
    }

    // Arms.
    if pose.climbing {
        // Both arms overhead, alternating which one is higher, as if reaching rung to rung.
        for (index, direction) in [-1.0, 1.0].enumerated() {
            let reach = 0.55 + 0.45 * pose.armsUp + (index == 0 ? 0.2 : -0.2)
            let armX = centreX + direction * (bodyWidth / 2 - 2)
            let armY = bodyY + bodyHeight * 0.15 + reach * (bodyHeight * 0.7)
            fillEllipse(context, centreX: armX, centreY: armY, width: 7, height: 7, colour: palette.body)
        }
    } else if pose.armsUp > 0.01 {
        for direction in [-1.0, 1.0] {
            let armX = centreX + direction * (bodyWidth / 2 - 1)
            let armY = bodyY + bodyHeight * 0.1 + pose.armsUp * (bodyHeight * 0.42)
            fillEllipse(context, centreX: armX + direction * pose.armsUp * 3, centreY: armY,
                        width: 8, height: 8, colour: palette.body)
        }
    }

    // Held tool, drawn over the body so the swing reads clearly.
    if pose.item != .none, pose.thrownOffset == nil {
        drawHeldItem(context, item: pose.item, swing: pose.itemSwing,
                     from: CGPoint(x: centreX + bodyWidth * 0.42, y: bodyY + bodyHeight * 0.05))
    }

    // A thrown item, on its way out.
    if let offset = pose.thrownOffset {
        let centre = CGPoint(x: centreX + offset.x, y: bodyY + offset.y)
        let bomb = CGColor(red: 0.85, green: 0.24, blue: 0.18, alpha: 1)
        fillEllipse(context, centreX: centre.x, centreY: centre.y, width: 11, height: 11, colour: bomb)
        context.setStrokeColor(palette.ink)
        context.setLineWidth(1.4)
        context.strokeEllipse(in: CGRect(x: centre.x - 5.5, y: centre.y - 5.5, width: 11, height: 11))
    }

    // Blast, for the moment the TNT goes off.
    if pose.blast > 0.01 {
        let radius = 8 + 18 * pose.blast
        let alpha = 0.85 * (1 - pose.blast * 0.4)
        let colours = [
            CGColor(red: 1.0, green: 0.92, blue: 0.55, alpha: alpha),
            CGColor(red: 1.0, green: 0.62, blue: 0.20, alpha: alpha * 0.9),
        ]
        for (index, colour) in colours.enumerated() {
            let scale = index == 0 ? 1.0 : 0.62
            fillEllipse(context, centreX: centreX + 12, centreY: bodyY + 4,
                        width: radius * 2 * scale, height: radius * 2 * scale, colour: colour)
        }
    }

    // Eyes.
    let eyeY = bodyY + bodyHeight * 0.18
    let eyeOffset = bodyWidth * 0.19
    if pose.eyeOpen < 0.15 {
        // Closed: a short horizontal stroke.
        context.setStrokeColor(palette.ink)
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        for direction in [-1.0, 1.0] {
            let x = centreX + direction * eyeOffset
            context.move(to: CGPoint(x: x - 3, y: eyeY))
            context.addLine(to: CGPoint(x: x + 3, y: eyeY))
        }
        context.strokePath()
    } else {
        let radius = 2.2 + 1.4 * pose.eyeOpen
        for direction in [-1.0, 1.0] {
            fillEllipse(context, centreX: centreX + direction * eyeOffset, centreY: eyeY,
                        width: radius * 2, height: radius * 2, colour: palette.ink)
        }
    }

    // Sleeping z's.
    if let phase = pose.sleepZPhase {
        drawSleepingZ(context, originX: centreX + bodyWidth * 0.35, originY: bodyTop + 2,
                      size: 6 + phase * 4, palette: palette)
    }

    // Surprise mark: a pair of vertical strokes above the head.
    if pose.surprise > 0.5 {
        context.setStrokeColor(palette.ink)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centreX + bodyWidth * 0.5, y: bodyTop + 4))
        context.addLine(to: CGPoint(x: centreX + bodyWidth * 0.5, y: bodyTop + 12))
        context.strokePath()
    }
}

/// The pickaxe, sword or block the pet is holding, rotated about the grip.
func drawHeldItem(_ context: CGContext, item: HeldItem, swing: Double, from grip: CGPoint) {
    context.saveGState()
    context.translateBy(x: grip.x, y: grip.y)
    context.rotate(by: swing)
    context.setLineCap(.round)

    let handle = CGColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
    let metal = CGColor(red: 0.62, green: 0.68, blue: 0.75, alpha: 1)
    let gold = CGColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1)

    switch item {
    case .none:
        break

    case .pickaxe:
        context.setStrokeColor(handle)
        context.setLineWidth(3)
        context.move(to: .zero)
        context.addLine(to: CGPoint(x: 0, y: 22))
        context.strokePath()

        context.setStrokeColor(metal)
        context.setLineWidth(3.5)
        context.move(to: CGPoint(x: -9, y: 20))
        context.addLine(to: CGPoint(x: 0, y: 25))
        context.addLine(to: CGPoint(x: 9, y: 20))
        context.strokePath()

    case .sword:
        context.setStrokeColor(metal)
        context.setLineWidth(3.5)
        context.move(to: .zero)
        context.addLine(to: CGPoint(x: 0, y: 20))
        context.strokePath()

        context.setStrokeColor(gold)
        context.setLineWidth(2.5)
        context.move(to: CGPoint(x: -5, y: 4))
        context.addLine(to: CGPoint(x: 5, y: 4))
        context.strokePath()

    case .tnt:
        let red = CGColor(red: 0.85, green: 0.24, blue: 0.18, alpha: 1)
        let white = CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)
        context.setFillColor(red)
        context.fill(CGRect(x: -7, y: 6, width: 14, height: 14))
        context.setFillColor(white)
        context.fill(CGRect(x: -7, y: 11, width: 14, height: 4))
    }

    context.restoreGState()
}

/// A "Z" drawn from three strokes, so no font handling is needed.
func drawSleepingZ(_ context: CGContext, originX: Double, originY: Double, size: Double, palette: Palette) {
    context.setStrokeColor(palette.z)
    context.setLineWidth(1.8)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: originX, y: originY + size))
    context.addLine(to: CGPoint(x: originX + size, y: originY + size))
    context.addLine(to: CGPoint(x: originX, y: originY))
    context.addLine(to: CGPoint(x: originX + size, y: originY))
    context.strokePath()
}

// MARK: - Poses per state

func pose(for state: String, frame: Int, of count: Int) -> Pose {
    // 0..<1 progress around the loop.
    let t = Double(frame) / Double(count)
    let wave = sin(t * 2 * .pi)

    switch state {
    case "idle":
        // Gentle breathing with a small bob.
        return Pose(
            bodyOffsetY: wave * 1.3,
            squash: 1 + wave * 0.03,
            stretch: 1 - wave * 0.02
        )

    case "walk":
        // Alternating foot lifts plus a two-beat bob, so it reads as a walk rather than a slide.
        let leftLift = max(0, sin(t * 2 * .pi)) * 5
        let rightLift = max(0, sin(t * 2 * .pi + .pi)) * 5
        let bob = abs(sin(t * 4 * .pi))
        let bobOffset = bob * 1.6
        let bobSquash = 1 - bob * 0.03
        return Pose(
            bodyOffsetY: bobOffset,
            squash: bobSquash,
            leftFootLift: leftLift,
            rightFootLift: rightLift
        )

    case "drag":
        // Held up by the scruff: arms up, body dangling and swaying.
        let sway = wave * 2.5
        return Pose(
            bodyOffsetY: 3,
            squash: 1.05,
            eyeOpen: 1.3,
            armsUp: 0.85,
            sway: sway
        )

    case "sleep":
        // Lying down, eyes shut, slow breathing, z's rising.
        return Pose(
            bodyOffsetY: abs(wave) * 0.8,
            squash: 1 + wave * 0.04,
            eyeOpen: 0,
            lyingDown: true,
            sleepZPhase: t
        )

    case "click":
        // A startled hop: fast squash then a stretch, with a surprise mark at the peak.
        let progress = Double(frame) / Double(count - 1)
        let hop = sin(progress * .pi)
        return Pose(
            bodyOffsetY: hop * 5,
            squash: 1 - hop * 0.14,
            stretch: 1 + hop * 0.10,
            leftFootLift: hop * 3,
            rightFootLift: hop * 3,
            eyeOpen: 1.6,
            surprise: hop
        )

    case "climb":
        // Reaching rung to rung: hands and feet alternate, and the body hangs slightly back.
        let leftLift = max(0, -wave) * 4 + 2
        let rightLift = max(0, wave) * 4 + 2
        let hang = 1 + wave * 0.8
        let reach = 0.5 - 0.5 * wave
        return Pose(
            bodyOffsetY: hang,
            leftFootLift: leftLift,
            rightFootLift: rightLift,
            eyeOpen: 1.05,
            armsUp: reach,
            climbing: true
        )

    case "mine":
        // Wind the pickaxe up behind the head, then bring it down: one swing per loop.
        let arc = 0.5 - 0.5 * cos(t * 2 * .pi)
        return Pose(
            bodyOffsetY: arc * 1.5,
            squash: 1 - arc * 0.05,
            stretch: 1 + arc * 0.04,
            eyeOpen: 0.8 + arc * 0.4,
            armsUp: 0.9 - arc * 1.5,
            item: .pickaxe,
            itemSwing: -1.25 + 2.3 * arc
        )

    case "fight":
        // A quicker, flatter slash than the pickaxe swing.
        let arc = 0.5 - 0.5 * cos(t * 2 * .pi)
        let chop = arc * 2
        let lean = 1 + 0.04 * (0.5 - arc)
        return Pose(
            bodyOffsetY: -1 + chop,
            squash: lean,
            eyeOpen: 1.2,
            armsUp: 0.7 - arc * 1.3,
            item: .sword,
            itemSwing: -1.0 + 2.0 * arc
        )

    case "tnt":
        // Hold, wind up, throw, blast, recover. Played once, so the last frame settles back toward
        // the first rather than jumping when the machine returns to idle.
        let progress = Double(frame) / Double(max(count - 1, 1))

        if progress < 0.3 {
            let hold = progress / 0.3
            return Pose(bodyOffsetY: -0.5, item: .tnt, itemSwing: -0.25 * hold)
        }

        if progress < 0.6 {
            let wind = (progress - 0.3) / 0.3
            let rise = -0.5 + wind * 1.5
            let squeeze = 1 - wind * 0.08
            let stretch = 1 + wind * 0.07
            let lift = 0.4 + wind * 0.6
            let flight = CGPoint(x: wind * 28, y: 14 + wind * 12)
            return Pose(
                bodyOffsetY: rise,
                squash: squeeze,
                stretch: stretch,
                eyeOpen: 1.3,
                armsUp: lift,
                thrownOffset: flight
            )
        }

        if progress < 0.85 {
            let blow = (progress - 0.6) / 0.25
            let flash = max(0, 1 - abs(blow - 0.35) * 2.4)
            let drift = CGPoint(x: 28 + blow * 10, y: 26 - blow * 6)
            return Pose(
                bodyOffsetY: 1.5,
                squash: 0.95,
                eyeOpen: 1.6,
                armsUp: 0.85,
                thrownOffset: drift,
                blast: flash
            )
        }

        let settle = (progress - 0.85) / 0.15
        let calm = 1 - settle
        let fall = 1.5 * calm
        let drop = 0.6 * calm
        let wide = 1 + 0.4 * calm
        return Pose(
            bodyOffsetY: fall,
            eyeOpen: wide,
            armsUp: drop,
            surprise: settle < 0.5 ? calm * 2 : 0
        )

    default:
        return Pose()
    }
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "make-placeholder-skin", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "could not create \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-placeholder-skin", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "could not write \(url.path)"])
    }
}

func manifestJSON(name: String) -> String {
    let stateEntries = states.map { state -> String in
        """
              "\(state.name)": { "fps": \(state.fps), "loop": \(state.loop) }
        """
    }.joined(separator: ",\n")

    return """
    {
      "name": "\(name)",
      "frameSize": { "width": \(frameSize), "height": \(frameSize) },
      "scale": 2,
      "anchor": "bottomCenter",
      "hitAlphaThreshold": 16,
      "states": {
    \(stateEntries)
      }
    }

    """
}

/// Writes one skin into `Resources/Skins/<identifier>`.
func writeSkin(identifier: String, palette: Palette, into skinsRoot: URL) throws {
    let skinDirectory = skinsRoot.appendingPathComponent(identifier, isDirectory: true)

    // Start from a clean slate so stale frames from an earlier run cannot linger.
    if FileManager.default.fileExists(atPath: skinDirectory.path) {
        try FileManager.default.removeItem(at: skinDirectory)
    }

    try FileManager.default.createDirectory(at: skinDirectory, withIntermediateDirectories: true)
    try Data(manifestJSON(name: identifier).utf8)
        .write(to: skinDirectory.appendingPathComponent("skin.json"))

    print("\(identifier)")

    for state in states {
        let directory = skinDirectory
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent(state.name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for frame in 0..<state.frames {
            let context = makeContext()
            drawCritter(
                context,
                pose: pose(for: state.name, frame: frame, of: state.frames),
                palette: palette
            )

            guard let image = context.makeImage() else {
                fatalError("could not render \(state.name) frame \(frame)")
            }

            // Zero-padded so filename sorting is also frame order.
            let name = String(format: "%03d.png", frame)
            try writePNG(image, to: directory.appendingPathComponent(name))
        }
        print("  \(state.name): \(state.frames) frame(s)")
    }
}

func main() throws {
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let skinsRoot = repoRoot.appendingPathComponent("Resources/Skins", isDirectory: true)

    for skin in skins {
        try writeSkin(identifier: skin.identifier, palette: skin.palette, into: skinsRoot)
    }

    print("\nWrote \(skins.count) skin(s) under \(skinsRoot.path)")
    print("Both should appear in the pet's right-click skin picker.")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("make-placeholder-skin: \(error.localizedDescription)\n".utf8))
    exit(1)
}

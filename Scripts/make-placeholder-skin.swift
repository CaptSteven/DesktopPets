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
let skinName = "placeholder"

/// Matches `SkinManifest.knownStates`. `click` is the one non-looping state.
let states: [(name: String, fps: Double, loop: Bool, frames: Int)] = [
    ("idle", 6, true, 4),
    ("walk", 10, true, 6),
    ("drag", 8, true, 4),
    ("sleep", 3, true, 4),
    ("click", 12, false, 6),
]

// MARK: - Palette

let bodyColour = CGColor(red: 0.95, green: 0.65, blue: 0.35, alpha: 1)
let bellyColour = CGColor(red: 1.0, green: 0.85, blue: 0.70, alpha: 1)
let earColour = CGColor(red: 0.88, green: 0.55, blue: 0.30, alpha: 1)
let inkColour = CGColor(red: 0.23, green: 0.16, blue: 0.13, alpha: 1)
let zColour = CGColor(red: 0.55, green: 0.60, blue: 0.65, alpha: 1)

// MARK: - Pose

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

func drawCritter(_ context: CGContext, pose: Pose) {
    let centreX = Double(frameSize) / 2 + pose.sway

    // Body. Lying down squashes it and drops it towards the floor.
    let bodyHeight = (pose.lyingDown ? 22.0 : 30.0) * pose.squash
    let bodyWidth = (pose.lyingDown ? 42.0 : 34.0) * pose.stretch
    let baseBodyY = pose.lyingDown ? 22.0 : 30.0
    let bodyY = baseBodyY + pose.bodyOffsetY
    let bodyTop = bodyY + bodyHeight / 2

    // Tail, off to one side so left/right facing is visible when the sprite is flipped.
    fillEllipse(context, centreX: centreX - bodyWidth / 2 - 2, centreY: bodyY - 2,
                width: 14, height: 9, colour: earColour)

    // Ears, behind the body.
    for direction in [-1.0, 1.0] {
        let earX = centreX + direction * bodyWidth * 0.28
        context.setFillColor(earColour)
        context.move(to: CGPoint(x: earX - 6, y: bodyTop - 4))
        context.addLine(to: CGPoint(x: earX + direction * 1.5, y: bodyTop + (pose.lyingDown ? 4 : 12)))
        context.addLine(to: CGPoint(x: earX + 6, y: bodyTop - 4))
        context.closePath()
        context.fillPath()
    }

    // Belly patch.
    fillEllipse(context, centreX: centreX, centreY: bodyY - bodyHeight * 0.12,
                width: bodyWidth * 0.5, height: bodyHeight * 0.45, colour: bellyColour)

    // Body.
    fillEllipse(context, centreX: centreX, centreY: bodyY,
                width: bodyWidth, height: bodyHeight, colour: bodyColour)

    // Feet. Hidden while lying down, and lifted by the walk cycle.
    if !pose.lyingDown {
        fillEllipse(context, centreX: centreX - bodyWidth * 0.26, centreY: bodyY - bodyHeight / 2 + pose.leftFootLift,
                    width: 11, height: 7, colour: earColour)
        fillEllipse(context, centreX: centreX + bodyWidth * 0.26, centreY: bodyY - bodyHeight / 2 + pose.rightFootLift,
                    width: 11, height: 7, colour: earColour)
    }

    // Arms.
    if pose.armsUp > 0.01 {
        for direction in [-1.0, 1.0] {
            let armX = centreX + direction * (bodyWidth / 2 - 1)
            let armY = bodyY + bodyHeight * 0.1 + pose.armsUp * (bodyHeight * 0.42)
            fillEllipse(context, centreX: armX + direction * pose.armsUp * 3, centreY: armY,
                        width: 8, height: 8, colour: bodyColour)
        }
    }

    // Eyes.
    let eyeY = bodyY + bodyHeight * 0.18
    let eyeOffset = bodyWidth * 0.19
    if pose.eyeOpen < 0.15 {
        // Closed: a short horizontal stroke.
        context.setStrokeColor(inkColour)
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
                        width: radius * 2, height: radius * 2, colour: inkColour)
        }
    }

    // Sleeping z's.
    if let phase = pose.sleepZPhase {
        drawSleepingZ(context, originX: centreX + bodyWidth * 0.35, originY: bodyTop + 2, size: 6 + phase * 4)
    }

    // Surprise mark: a pair of vertical strokes above the head.
    if pose.surprise > 0.5 {
        context.setStrokeColor(inkColour)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centreX + bodyWidth * 0.5, y: bodyTop + 4))
        context.addLine(to: CGPoint(x: centreX + bodyWidth * 0.5, y: bodyTop + 12))
        context.strokePath()
    }
}

/// A "Z" drawn from three strokes, so no font handling is needed.
func drawSleepingZ(_ context: CGContext, originX: Double, originY: Double, size: Double) {
    context.setStrokeColor(zColour)
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

func manifestJSON() -> String {
    let stateEntries = states.map { state -> String in
        """
              "\(state.name)": { "fps": \(state.fps), "loop": \(state.loop) }
        """
    }.joined(separator: ",\n")

    return """
    {
      "name": "\(skinName)",
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

func main() throws {
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let skinDirectory = repoRoot
        .appendingPathComponent("Resources/Skins", isDirectory: true)
        .appendingPathComponent(skinName, isDirectory: true)

    // Start from a clean slate so stale frames from an earlier run cannot linger.
    if FileManager.default.fileExists(atPath: skinDirectory.path) {
        try FileManager.default.removeItem(at: skinDirectory)
    }

    try FileManager.default.createDirectory(at: skinDirectory, withIntermediateDirectories: true)
    try Data(manifestJSON().utf8).write(to: skinDirectory.appendingPathComponent("skin.json"))

    for state in states {
        let directory = skinDirectory
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent(state.name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for frame in 0..<state.frames {
            let context = makeContext()
            drawCritter(context, pose: pose(for: state.name, frame: frame, of: state.frames))

            guard let image = context.makeImage() else {
                fatalError("could not render \(state.name) frame \(frame)")
            }

            // Zero-padded so filename sorting is also frame order.
            let name = String(format: "%03d.png", frame)
            try writePNG(image, to: directory.appendingPathComponent(name))
        }
        print("  \(state.name): \(state.frames) frame(s)")
    }

    print("Wrote placeholder skin to \(skinDirectory.path)")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("make-placeholder-skin: \(error.localizedDescription)\n".utf8))
    exit(1)
}

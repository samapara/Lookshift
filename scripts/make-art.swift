// Draws the app icon and the .dmg window background in Jive colours.
//
//   swift scripts/make-art.swift          writes Resources/AppIcon.icns and Resources/dmg-background.png
//
// Run it again after changing the drawing; the outputs are committed so builds don't need it.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(width: Int, height: Int, _ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// The icon on a 1024-point canvas: a blue tile with an eye whose pupil has
/// shifted to one side, the way your eyes move to another window.
func drawIcon(in canvas: CGRect) {
    let s = canvas.width / 1024
    // Apple's grid: an 824-point rounded tile centred on the canvas, with a soft shadow.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 28 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.set()
    color(0x0b63c4).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x4cb4ff), ending: color(0x0b4fa0))!.draw(in: shape, angle: -60)

    // The almond outline of the eye.
    let centre = CGPoint(x: tile.midX, y: tile.midY)
    let halfWidth = 300 * s, halfHeight = 175 * s
    let eye = NSBezierPath()
    eye.move(to: CGPoint(x: centre.x - halfWidth, y: centre.y))
    eye.curve(to: CGPoint(x: centre.x + halfWidth, y: centre.y),
              controlPoint1: CGPoint(x: centre.x - halfWidth * 0.45, y: centre.y + halfHeight * 1.55),
              controlPoint2: CGPoint(x: centre.x + halfWidth * 0.45, y: centre.y + halfHeight * 1.55))
    eye.curve(to: CGPoint(x: centre.x - halfWidth, y: centre.y),
              controlPoint1: CGPoint(x: centre.x + halfWidth * 0.45, y: centre.y - halfHeight * 1.55),
              controlPoint2: CGPoint(x: centre.x - halfWidth * 0.45, y: centre.y - halfHeight * 1.55))
    eye.close()
    color(0xffffff).setFill()
    eye.fill()

    // Iris and pupil, shifted right and clipped to the eye.
    NSGraphicsContext.saveGraphicsState()
    eye.addClip()
    let iris = CGPoint(x: centre.x + 105 * s, y: centre.y)
    let irisRadius = 128 * s
    color(0x0c0d10).setFill()
    NSBezierPath(ovalIn: CGRect(x: iris.x - irisRadius, y: iris.y - irisRadius,
                                width: irisRadius * 2, height: irisRadius * 2)).fill()
    let glint = 34 * s
    color(0xffffff).setFill()
    NSBezierPath(ovalIn: CGRect(x: iris.x + 30 * s, y: iris.y + 30 * s, width: glint, height: glint)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Motion lines behind the pupil show the shift.
    color(0x0b63c4, 0.55).setStroke()
    for (offset, length) in [(-48.0, 70.0), (0.0, 110.0), (48.0, 70.0)] {
        let line = NSBezierPath()
        let end = iris.x - irisRadius - 26 * s
        line.move(to: CGPoint(x: end - CGFloat(length) * s, y: centre.y + CGFloat(offset) * s))
        line.line(to: CGPoint(x: end, y: centre.y + CGFloat(offset) * s))
        line.lineWidth = 22 * s
        line.lineCapStyle = .round
        line.stroke()
    }
}

/// The .dmg window: the app on the left, Applications on the right, an arrow between.
/// Finder places the two icons at (165, 190) and (495, 190) in a 660 × 400 window.
func drawBackground(in canvas: CGRect) {
    let s = canvas.width / 660
    color(0xf7f8fa).setFill()
    canvas.fill()

    let title = NSAttributedString(string: "Drag Lookshift into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 20 * s, weight: .semibold), .foregroundColor: color(0x14161a),
    ])
    let titleSize = title.size()
    title.draw(at: CGPoint(x: canvas.midX - titleSize.width / 2, y: canvas.height - 64 * s))

    let note = NSAttributedString(string: "Then open it from Applications. It lives in the menu bar.", attributes: [
        .font: NSFont.systemFont(ofSize: 13 * s), .foregroundColor: color(0x586071),
    ])
    let noteSize = note.size()
    note.draw(at: CGPoint(x: canvas.midX - noteSize.width / 2, y: 52 * s))

    // Arrow between the icons (window y is measured from the top).
    let y = canvas.height - 190 * s
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 265 * s, y: y))
    arrow.line(to: CGPoint(x: 385 * s, y: y))
    arrow.move(to: CGPoint(x: 365 * s, y: y + 16 * s))
    arrow.line(to: CGPoint(x: 389 * s, y: y))
    arrow.line(to: CGPoint(x: 365 * s, y: y - 16 * s))
    arrow.lineWidth = 5 * s
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0x0b63c4).setStroke()
    arrow.stroke()
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try write(render(width: pixels, height: pixels, drawIcon), to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

try write(render(width: 1024, height: 1024, drawIcon), to: resources.appendingPathComponent("AppIcon-1024.png"))
// Retina background; make-dmg.sh tells Finder it's 660 × 400 points.
try write(render(width: 1320, height: 800, drawBackground), to: resources.appendingPathComponent("dmg-background.png"))
print("Wrote AppIcon.icns, AppIcon-1024.png and dmg-background.png to \(resources.path)")

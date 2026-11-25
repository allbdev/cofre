// Draws Cofre's app icon (a vault door) into the asset catalog, one PNG per size.
// Every size is drawn from the vector shapes, not scaled down from the big one.
//
//   swift scripts/make-icon.swift            # writes Cofre/Assets.xcassets/AppIcon.appiconset
//   swift scripts/make-icon.swift <dir>      # writes the PNGs somewhere else (previews)
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

struct IconError: Error, CustomStringConvertible {
    let description: String
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func gradient(_ colors: [CGColor]) -> CGGradient {
    guard let gradient = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil) else {
        preconditionFailure("CoreGraphics refused a gradient of \(colors.count) colors")
    }
    return gradient
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

/// Fills `path` with a linear gradient from top to bottom.
func fill(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from top: CGPoint, to bottom: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(colors), start: top, end: bottom, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// The icon on a 1024 × 1024 canvas (y grows upwards). macOS icons keep a margin around an
/// 824-point rounded square, which also leaves room for the shadow.
func drawIcon(_ ctx: CGContext) {
    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    // Background: the rounded square, with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1B2550))
    ctx.fillPath()
    ctx.restoreGState()
    fill(
        ctx, tilePath, [color(0x4157B2), color(0x1F2B63), color(0x0E1533)], from: CGPoint(x: 300, y: 924),
        to: CGPoint(x: 724, y: 100))
    // A faint glow behind the door.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient([color(0x7F95FF, 0.35), color(0x7F95FF, 0)]),
        startCenter: center, startRadius: 0, endCenter: center, endRadius: 420, options: [])
    ctx.restoreGState()

    // The door: a metal disc with a darker rim and rivets.
    let doorRadius: CGFloat = 318
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.45))
    ctx.setFillColor(color(0x8A95AD))
    ctx.fillEllipse(in: circle(center, doorRadius))
    ctx.restoreGState()
    fill(
        ctx, CGPath(ellipseIn: circle(center, doorRadius), transform: nil),
        [color(0xF4F6FB), color(0xC9D0DF), color(0x8D98B0)],
        from: CGPoint(x: center.x, y: center.y + doorRadius), to: CGPoint(x: center.x, y: center.y - doorRadius))
    let faceRadius: CGFloat = 268
    fill(
        ctx, CGPath(ellipseIn: circle(center, faceRadius), transform: nil),
        [color(0xA7B1C6), color(0xDCE1EC), color(0xEEF1F7)],
        from: CGPoint(x: center.x, y: center.y + faceRadius), to: CGPoint(x: center.x, y: center.y - faceRadius))
    for index in 0..<12 {
        let angle = CGFloat(index) / 12 * 2 * .pi + .pi / 12
        let rivet = CGPoint(x: center.x + cos(angle) * 293, y: center.y + sin(angle) * 293)
        fill(
            ctx, CGPath(ellipseIn: circle(rivet, 11), transform: nil),
            [color(0xFFFFFF), color(0x7C879F)],
            from: CGPoint(x: rivet.x, y: rivet.y + 11), to: CGPoint(x: rivet.x, y: rivet.y - 11))
    }

    // The handle wheel: three spokes with round grips.
    for index in 0..<3 {
        let angle = CGFloat(index) / 3 * 2 * .pi + .pi / 2
        let end = CGPoint(x: center.x + cos(angle) * 222, y: center.y + sin(angle) * 222)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: color(0x000000, 0.35))
        ctx.setStrokeColor(color(0x5B6680))
        ctx.setLineWidth(38)
        ctx.setLineCap(.round)
        ctx.move(to: center)
        ctx.addLine(to: end)
        ctx.strokePath()
        ctx.setFillColor(color(0x5B6680))
        ctx.fillEllipse(in: circle(end, 34))
        ctx.restoreGState()
        fill(
            ctx, CGPath(ellipseIn: circle(end, 30), transform: nil),
            [color(0xB9C2D6), color(0x56617A)],
            from: CGPoint(x: end.x, y: end.y + 30), to: CGPoint(x: end.x, y: end.y - 30))
    }

    // The dial: dark, with tick marks.
    let dialRadius: CGFloat = 150
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.5))
    ctx.setFillColor(color(0x1A2140))
    ctx.fillEllipse(in: circle(center, dialRadius))
    ctx.restoreGState()
    fill(
        ctx, CGPath(ellipseIn: circle(center, dialRadius), transform: nil),
        [color(0x3A4672), color(0x161C38)],
        from: CGPoint(x: center.x, y: center.y + dialRadius), to: CGPoint(x: center.x, y: center.y - dialRadius))
    ctx.setLineCap(.round)
    for index in 0..<40 {
        let angle = CGFloat(index) / 40 * 2 * .pi + .pi / 2
        let major = index % 5 == 0
        let inner: CGFloat = major ? 104 : 118
        ctx.setStrokeColor(major ? color(0xE9EDF7) : color(0xE9EDF7, 0.55))
        ctx.setLineWidth(major ? 9 : 5)
        ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        ctx.addLine(to: CGPoint(x: center.x + cos(angle) * 134, y: center.y + sin(angle) * 134))
        ctx.strokePath()
    }

    // The hub: the one warm accent.
    fill(
        ctx, CGPath(ellipseIn: circle(center, 58), transform: nil),
        [color(0xFFD978), color(0xF0A92E), color(0xB8761A)],
        from: CGPoint(x: center.x, y: center.y + 58), to: CGPoint(x: center.x, y: center.y - 58))
    ctx.setStrokeColor(color(0x8A5510, 0.6))
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: circle(center, 56))
    // The pointer at the top of the hub.
    ctx.setStrokeColor(color(0x8A5510))
    ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: center.x, y: center.y + 18))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + 44))
    ctx.strokePath()
}

func png(pixels: Int) throws -> Data {
    guard
        let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw IconError(description: "can't create a \(pixels) px bitmap") }
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(ctx)
    guard let image = ctx.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw IconError(description: "can't encode the \(pixels) px PNG") }
    return data
}

let output =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: "Cofre/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appending(path: name))
        images.append(
            "    { \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(points)x\(points)\" }"
        )
    }
}
let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
try contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(output.path)")

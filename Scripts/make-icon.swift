import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Renders the TrackerCam app icon (1024×1024 PNG): a tracking-bracket reticle locked onto a
// green subject with a motion trail, on a navy→teal gradient. Run with Xcode's toolchain:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift Scripts/make-icon.swift <out.png>

let S = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Background gradient (top-left navy → bottom-right teal).
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(0.04, 0.09, 0.20), rgb(0.05, 0.52, 0.52)] as CFArray,
                      locations: [0, 1])!
ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S)); ctx.clip()
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
ctx.restoreGState()

let green = rgb(0.23, 0.89, 0.48)
let greenSoft = rgb(0.23, 0.89, 0.48, 0.18)

// Motion trail (subject moving left→right; ghosts trail to the left).
func disc(_ x: Double, _ y: Double, _ r: Double, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}
disc(380, 512, 44, rgb(0.23, 0.89, 0.48, 0.16))
disc(452, 512, 60, rgb(0.23, 0.89, 0.48, 0.32))
disc(560, 512, 96, greenSoft)         // soft glow
disc(560, 512, 80, green)             // subject

// Tracking-bracket reticle (white corner Ls forming a centered square).
ctx.setStrokeColor(rgb(1, 1, 1, 0.96))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let lo = 288.0, hi = 736.0, L = 130.0
func bracket(_ cx: Double, _ cy: Double, _ hx: Double, _ vy: Double) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx + hx * L, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy + vy * L))
    ctx.strokePath()
}
bracket(lo, lo, 1, 1)
bracket(hi, lo, -1, 1)
bracket(lo, hi, 1, -1)
bracket(hi, hi, -1, -1)

// Subtle center crosshair ticks.
ctx.setStrokeColor(rgb(1, 1, 1, 0.55))
ctx.setLineWidth(8)
for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 512 + dx * 24, y: 512 + dy * 24))
    ctx.addLine(to: CGPoint(x: 512 + dx * 54, y: 512 + dy * 54))
    ctx.strokePath()
}

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, img, nil)
if CGImageDestinationFinalize(dest) { print("wrote \(out)") } else { fatalError("write failed") }

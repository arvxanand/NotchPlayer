// Draws the app icon: a waveform on a dark tile. Drawn in code so it can be
// redrawn without a design tool, and so it is plainly not Spotify's mark
// (docs/RECORDING.md §4).
//
//   swift tools/make-icon.swift            # writes assets/AppIcon.icns and assets/logo.png
import AppKit

let size: CGFloat = 1024

func png(_ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let data = png { cg in
    // Apple's macOS grid: an 824pt tile centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.addPath(shape); cg.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [
        CGColor(red: 0.20, green: 0.21, blue: 0.27, alpha: 1),
        CGColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // A waveform, shaped like the menu-bar glyph, in a warm gradient.
    let heights: [CGFloat] = [120, 230, 340, 470, 560, 470, 340, 230, 120]
    let bar: CGFloat = 44, gap: CGFloat = 30
    let left = 512 - (CGFloat(heights.count) * bar + CGFloat(heights.count - 1) * gap) / 2
    for (i, h) in heights.enumerated() {
        let r = CGRect(x: left + CGFloat(i) * (bar + gap), y: 512 - h / 2, width: bar, height: h)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: bar / 2, cornerHeight: bar / 2, transform: nil))
    }
    cg.clip()
    let art = CGGradient(colorsSpace: nil, colors: [
        CGColor(red: 1.00, green: 0.62, blue: 0.35, alpha: 1),
        CGColor(red: 0.88, green: 0.28, blue: 0.60, alpha: 1)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(art, start: CGPoint(x: 512, y: 792), end: CGPoint(x: 512, y: 232), options: [])
}

let assets = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("assets")
try! data.write(to: assets.appendingPathComponent("logo.png"))

// iconutil wants every size in an .iconset folder; sips does the scaling.
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit(); precondition(p.terminationStatus == 0, "\(tool) failed")
}
for px in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(px)x\(px).png" : "icon_\(px)x\(px)@2x.png"
        run("/usr/bin/sips", ["-z", "\(px * scale)", "\(px * scale)", assets.appendingPathComponent("logo.png").path,
                              "--out", set.appendingPathComponent(name).path])
    }
}
run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", assets.appendingPathComponent("AppIcon.icns").path])
print("wrote assets/logo.png and assets/AppIcon.icns")

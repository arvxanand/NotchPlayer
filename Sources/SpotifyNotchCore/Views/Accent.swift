import AppKit

/// The colour the progress line takes from the album cover.
///
/// **Taken once per cover, when it is decoded** (`ArtMemory.store`), never
/// per frame: the line redraws every second and the cover does not change.
///
/// Two rules, both measured by `AccentTests`:
///
/// - **A grey cover gives nil**, and the line stays white. Picking "the most
///   common colour" of a black-and-white photo gives a muddy grey that reads
///   as disabled.
/// - **Vivid, and at least 3:1 against the black panel.** The colour is
///   brightened to full first, so a dark red cover gives red rather than
///   maroon, then mixed toward white only if it still fails 3:1 on black
///   (pure blue does, a little).
///
/// **Deliberately not 3:1 against the unfilled track**, which the user chose
/// on 22 Sep 2026 after seeing both on real covers: that rule washed every
/// red and blue into pastel. The cost is that a red or blue fill is told
/// apart from the grey track by hue more than by brightness.
public enum Accent {
    /// The switch on the menu panel's settings page. On unless turned off.
    public static let enabledKey = "coverColourAccent"

    public struct RGB: Equatable, Sendable {
        public let r, g, b: Double
    }

    /// Pixels paler or darker than this say nothing about the cover's colour.
    static let minSaturation = 0.25
    static let minBrightness = 0.2
    /// Under this share of coloured pixels the cover counts as grey. A black
    /// and white photo with one red logo is still a grey cover.
    static let minColouredShare = 0.08
    /// 3:1 on black, with a little margin so a colour lands over the line
    /// rather than on it -- `Palette.trackLevel` explains why.
    static let minContrast = 3.1

    /// The side the cover is shrunk to before counting. 24x24 is 576 pixels:
    /// plenty to find the main colour, and cheap enough not to matter.
    static let sample = 24

    public static func of(_ image: NSImage) -> RGB? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = sample
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? of(rgba: bytes) : nil
    }

    static func of(rgba bytes: [UInt8]) -> RGB? { dominant(rgba: bytes).map { legible(brightened($0)) } }

    /// The same hue and saturation at full brightness.
    static func brightened(_ c: RGB) -> RGB {
        let high = max(c.r, c.g, c.b)
        guard high > 0 else { return c }
        return RGB(r: c.r / high, g: c.g / high, b: c.b / high)
    }

    /// The main colour of some RGBA bytes, as found. Pure, so a test can hand
    /// it pixels rather than a cover.
    ///
    /// Coloured pixels are sorted into twelve hue buckets, weighted by how
    /// saturated and bright they are, and the heaviest bucket's average wins.
    /// An average of the whole cover would turn a red and blue one purple.
    static func dominant(rgba bytes: [UInt8]) -> RGB? {
        let count = bytes.count / 4
        guard count > 0 else { return nil }
        var weight = [Double](repeating: 0, count: 12)
        var sum = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: 12)
        var coloured = 0
        for i in 0..<count {
            let r = Double(bytes[i * 4]) / 255, g = Double(bytes[i * 4 + 1]) / 255
            let b = Double(bytes[i * 4 + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            guard high >= minBrightness, high > 0 else { continue }
            let saturation = (high - low) / high
            guard saturation >= minSaturation else { continue }
            coloured += 1
            let bucket = min(11, Int(hue(r, g, b, high: high, low: low) * 12))
            let w = saturation * high
            weight[bucket] += w
            let s = sum[bucket]
            sum[bucket] = RGB(r: s.r + r * w, g: s.g + g * w, b: s.b + b * w)
        }
        guard Double(coloured) / Double(count) >= minColouredShare,
              let best = weight.indices.max(by: { weight[$0] < weight[$1] }) else { return nil }
        let w = weight[best], s = sum[best]
        return RGB(r: s.r / w, g: s.g / w, b: s.b / w)
    }

    /// Mixed toward white in small steps until it clears the floor. White
    /// itself clears it, so this always ends.
    static func legible(_ colour: RGB) -> RGB {
        var t = 0.0
        while true {
            let mixed = RGB(r: colour.r + (1 - colour.r) * t, g: colour.g + (1 - colour.g) * t,
                            b: colour.b + (1 - colour.b) * t)
            if t >= 1 || contrast(mixed, againstGrey: 0) >= minContrast {
                return mixed
            }
            t += 0.05
        }
    }

    /// WCAG 2.x contrast between a colour and a white level on black.
    static func contrast(_ c: RGB, againstGrey level: Double) -> Double {
        let a = luminance(c), b = luminance(RGB(r: level, g: level, b: level))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// 0..<1, red at 0.
    private static func hue(_ r: Double, _ g: Double, _ b: Double, high: Double, low: Double) -> Double {
        let d = high - low
        guard d > 0 else { return 0 }
        var h: Double
        if high == r { h = (g - b) / d } else if high == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h /= 6
        return h < 0 ? h + 1 : h
    }
}

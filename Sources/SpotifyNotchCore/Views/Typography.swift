import SwiftUI

/// Four type roles, all system faces. No bundled fonts: a native target gets
/// SF, and SF is what every other thing in the menu bar is set in.
public enum Type {
    /// The track title. The one piece of type in the panel with any weight.
    public static func title(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }
    /// Artist, album, and the permission sentence.
    public static func label(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
    /// Elapsed and remaining time. **Tabular figures, not merely monospaced
    /// digits by accident**: proportional digits change width as they tick, so
    /// a 1 following a 0 shifts the whole string and the clock visibly
    /// jitters once a second forever.
    public static func clock(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }
}

public enum Motion {
    /// One spring, everywhere: expand, collapse, bar envelope. Tuned to the
    /// Dynamic Island's feel, and borrowed wholesale from matchnotch where it
    /// is already tuned.
    ///
    /// Checked against TRAPS #53 before it was written rather than after: the
    /// panel travels 147pt in ~0.38s, which is ~390pt/s, or ~6.5pt per frame
    /// at 60Hz. A spring peaks at the *start*, so call it ~13pt on the worst
    /// frame -- well inside what the display can show. matchnotch's judder was
    /// a 300pt push at ~940pt/s; this is not that.
    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Honour the system setting rather than assuming everyone wants springs.
    public static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    public static var standard: Animation {
        reduced ? .easeInOut(duration: 0.18) : spring
    }
}

/// Black, white, two greys and exactly one chromatic colour.
///
/// Every level is declared as a white *opacity* constant and the `Color` is
/// derived from it, so `AuditReport` can compute the composited hex from the
/// same number the view draws with. Writing the hex out separately is how
/// matchnotch's contrast audit drifted from its UI and reported 100/100 while
/// never measuring six of the colours on screen.
public enum Palette {
    /// **Pure `#000`, not near-black and not a material.** The notch is
    /// physically black, and matching it exactly is what makes the panel read
    /// as part of the hardware instead of a window in front of it. This is the
    /// single highest-leverage decision in the design.
    public static let background = Color.black

    /// Track title, transport glyphs, the filled part of the progress line.
    public static let primaryLevel: Double = 1.0
    /// Artist, elapsed/remaining, secondary copy.
    public static let secondaryLevel: Double = 0.55
    /// The **unfilled** progress track. 0.36 and not matchnotch's 0.22,
    /// because 0.22 on black is 1.79:1 -- fine for a hairline divider, short
    /// of the 3:1 WCAG minimum for a non-text element that carries state.
    ///
    /// 0.36 and not 0.35 for an unglamorous reason: 0.35 composites to
    /// `#595959`, which measures **2.996:1** and only looks like a pass
    /// because the checker prints it rounded to `3.0`. A constant chosen to
    /// sit on a threshold sits on the wrong side of it half the time. 0.36 is
    /// `#5C5C5C` at 3.14:1, which is over the line without being asked twice.
    public static let trackLevel: Double = 0.36

    public static let primary = Color.white.opacity(primaryLevel)
    public static let secondary = Color.white.opacity(secondaryLevel)
    public static let track = Color.white.opacity(trackLevel)

    /// Every white level the views may draw, and whether it carries text.
    ///
    /// **One list, iterated by two consumers.** `AuditReport` emits a contrast
    /// check per text level from this, and `PaletteTests` asserts the WCAG
    /// floor per level from this -- so a level added here is audited and
    /// tested for free. Hand-keeping those two lists separately is precisely
    /// how matchnotch's audit came to report 100/100 while never measuring six
    /// of the colours on screen; a mutation test here proved the same gap
    /// existed in this file before the list did.
    ///
    /// A level declared *outside* this array is still invisible to both. That
    /// is the one thing to look for when the audit looks suspiciously clean.
    public static let levels: [(name: String, level: Double, text: Bool)] = [
        ("primary", primaryLevel, true),
        ("secondary", secondaryLevel, true),
        ("progress-track-unfilled", trackLevel, false),
    ]

    /// A hairline between rows, and the wash behind a row the pointer is on.
    ///
    /// **Both are deliberately under the 3:1 non-text floor**, which is
    /// allowed only because neither carries any information: the divider is
    /// decoration, and the hover wash is redundant beside text that brightens
    /// at the same moment. The wash also backs the cover slot in `MenuPanel`,
    /// so an album whose art has not arrived reads as an empty frame rather
    /// than a hole in the panel.
    public static let hairlineLevel: Double = 0.08
    public static let washLevel: Double = 0.07
    public static let hairline = Color.white.opacity(hairlineLevel)
    public static let wash = Color.white.opacity(washLevel)

    /// The levels that are under the floor on purpose.
    ///
    /// A second list rather than a flag on the first, so `levels` keeps
    /// answering exactly one question -- is every colour that means something
    /// audited -- and this one answers "and what about the rest". A grey that
    /// appears in neither is the thing to look for; `PaletteTests` asserts
    /// every entry here measures **under** 3:1, so a colour that carries state
    /// cannot be parked here to dodge the check.
    public static let decorationLevels: [(name: String, level: Double)] = [
        ("menu-divider", hairlineLevel),
        ("menu-row-wash", washLevel),
    ]

    /// The only chromatic colour in the app. Allowed on the Spotify mark, and
    /// on the playing dot in `MenuPanel` -- which is the same claim made twice
    /// (this is Spotify, this is live) rather than decoration borrowing a
    /// meaning. It appears nowhere else, and specifically never on a control. Everything else chromatic comes from the album
    /// art itself. Spotify's own green, 8.12:1 on black.
    public static let spotify = Color(red: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255)
    public static let spotifyHex = "#1DB954"

    /// Composite a white level onto black, as the compositor will.
    public static func hex(white level: Double) -> String {
        let v = Int((level * 255).rounded())
        return String(format: "#%02X%02X%02X", v, v, v)
    }
}

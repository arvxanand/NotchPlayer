import Foundation

/// The colour-contrast and hit-target checks, emitted as JSON for
/// `apple-hig-expert`'s `hig_checker.py batch`.
///
/// **Emitted from the app rather than hand-listed**, so the audit cannot drift
/// from the UI: every level comes from the same `Palette` constant the views
/// draw with, composited to hex by `Palette.hex(white:)`. matchnotch keeps its
/// list as literals and its own comments record that it drifted anyway --
/// reporting 100/100 while never measuring six of the colours on screen.
public enum AuditReport {
    public static func json() -> String {
        var checks: [String] = []

        func contrast(_ name: String, _ fg: String, _ bg: String = "#000000") {
            checks.append("""
            {"type": "contrast", "name": "\(name)", "fg": "\(fg)", "bg": "\(bg)"}
            """)
        }
        func target(_ name: String, _ w: Int, _ h: Int) {
            checks.append("""
            {"type": "target", "name": "\(name)", "w": \(w), "h": \(h)}
            """)
        }

        // Iterated, not listed. See `Palette.levels`.
        //
        // **Text levels only.** `hig_checker.py` knows WCAG's 4.5:1 rule for
        // normal text and nothing else, so submitting a non-text level here
        // would fail a check it actually passes and drag the required score
        // off 100. The 3:1 floor for those is asserted in
        // `PaletteTests.testEveryNonTextLevelMeetsTheNonTextMinimum` instead,
        // which is a real check rather than an omission.
        for entry in Palette.levels where entry.text {
            contrast(entry.name, Palette.hex(white: entry.level))
        }
        contrast("spotify-mark", Palette.spotifyHex)
        contrast("update-row", Palette.updateHex)

        // Computed from the constant the layout actually uses, so a shrunk
        // button cannot pass by being audited at its intended size.
        let hit = Int(NotchGeometry.minimumHitHeight)
        for name in ["shuffle", "previous", "playpause", "next", "repeat"] {
            target("transport-\(name)", hit, hit)
        }
        let plus = PanelView.plusGlyph + PanelView.plusOverhang * 2
        target("plus", Int(plus), Int(plus))

        return "{\n  \"checks\": [\n    " + checks.joined(separator: ",\n    ") + "\n  ]\n}"
    }
}

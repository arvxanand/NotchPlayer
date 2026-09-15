import XCTest
@testable import SpotifyNotchCore

/// WCAG 2.x relative luminance and contrast, written out here rather than
/// imported, so the palette is checked against the formula and not against
/// whatever the checker happens to print.
private func contrastOnBlack(_ level: Double) -> Double {
    let srgb = Double(Int((level * 255).rounded())) / 255
    let linear = srgb <= 0.03928 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
    return (linear + 0.05) / 0.05
}

final class PaletteTests: XCTestCase {
    func testEveryTextLevelClearsTheNormalTextMinimum() {
        for entry in Palette.levels where entry.text {
            XCTAssertGreaterThanOrEqual(contrastOnBlack(entry.level), 4.5,
                                        "\(entry.name) is text at \(entry.level)")
        }
    }

    /// The check `AuditReport` deliberately cannot make: `hig_checker.py` only
    /// knows the 4.5:1 text rule, and a non-text element's bar is 3:1.
    func testEveryNonTextLevelMeetsTheNonTextMinimum() {
        for entry in Palette.levels where !entry.text {
            XCTAssertGreaterThanOrEqual(contrastOnBlack(entry.level), 3.0,
                                        "\(entry.name) is non-text at \(entry.level)")
        }
    }

    /// Decoration is under the floor *on purpose*. The test is the boundary
    /// itself: anything here that measures 3:1 or better is not decoration, it
    /// is a real level that has dodged the audit by being filed as scenery.
    func testDecorationIsBelowTheNonTextFloorAndNotJustParkedThere() {
        for entry in Palette.decorationLevels {
            XCTAssertLessThan(contrastOnBlack(entry.level), 3.0,
                              "\(entry.name) at \(entry.level) carries enough contrast to " +
                              "mean something -- put it in Palette.levels and audit it")
        }
        let audited = Set(Palette.levels.map(\.level))
        for entry in Palette.decorationLevels {
            XCTAssertFalse(audited.contains(entry.level),
                           "\(entry.name) is in both lists")
        }
    }

    func testTheProgressTrackIsDimmerThanTheTextOnIt() {
        // Or it stops reading as the empty part of the bar.
        XCTAssertLessThan(Palette.trackLevel, Palette.secondaryLevel)
    }

    /// matchnotch's audit went stale because its hex strings were literals
    /// beside the colours rather than derived from them. This is the seam that
    /// stops that here, so it gets a test.
    func testCompositedHexMatchesTheLevelTheViewsDrawWith() {
        XCTAssertEqual(Palette.hex(white: 1.0), "#FFFFFF")
        XCTAssertEqual(Palette.hex(white: 0.0), "#000000")
        XCTAssertEqual(Palette.hex(white: Palette.secondaryLevel), "#8C8C8C")
        XCTAssertEqual(Palette.hex(white: Palette.trackLevel), "#5C5C5C")
    }

    /// **Derived from `Palette.levels`, not from a list written out here.** A
    /// hand-kept copy is how this test passed a mutation that added a whole
    /// new palette level and audited none of it.
    func testEveryTextLevelReachesTheAudit() {
        let json = AuditReport.json()
        for entry in Palette.levels where entry.text {
            XCTAssertTrue(json.contains(Palette.hex(white: entry.level)),
                          "\(entry.name) is drawn but never audited")
        }
        XCTAssertTrue(json.contains(Palette.spotifyHex))
        // The hit-target constant, not a repeat of the number.
        XCTAssertTrue(json.contains("\"w\": \(Int(NotchGeometry.minimumHitHeight))"))
    }

    func testTheLevelTableIsNotEmptyAndNamesAreUnique() {
        // A table this whole scheme depends on being complete should at least
        // be non-empty, and two entries sharing a name would silently collapse
        // to one check in the audit JSON.
        XCTAssertFalse(Palette.levels.isEmpty)
        XCTAssertEqual(Set(Palette.levels.map(\.name)).count, Palette.levels.count)
    }
}

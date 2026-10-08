import XCTest
import SwiftUI
@testable import NotchPlayerCore

final class WhatsNewTests: XCTestCase {
    func testShownOnceAfterAnUpdateAndNeverOnAFreshInstall() {
        let v = "0.6"
        XCTAssertNil(WhatsNew.pending(current: v, seen: nil, ranBefore: false), "a fresh install missed nothing")
        XCTAssertEqual(WhatsNew.pending(current: v, seen: nil, ranBefore: true)?.version, v,
                       "from v0.5 or older, which never wrote what it had shown")
        XCTAssertEqual(WhatsNew.pending(current: v, seen: "0.5", ranBefore: true)?.version, v)
        XCTAssertNil(WhatsNew.pending(current: v, seen: v, ranBefore: true), "already shown")
        XCTAssertNil(WhatsNew.pending(current: "0.1", seen: nil, ranBefore: true), "a version with no note")
    }

    /// With nothing to show, the version is recorded, so it never shows later.
    @MainActor func testNothingToShowCountsAsShown() {
        let name = "WhatsNewTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        _ = WhatsNew.atLaunch(current: "0.1", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: WhatsNew.seenKey), "0.1")
        WhatsNew.seen("0.6", defaults: defaults)
        XCTAssertNil(WhatsNew.atLaunch(current: "0.6", defaults: defaults))
    }

    /// Every line of every note fits on one line in the narrowest panel, and
    /// a note is never more than the card has room for.
    func testEveryNoteFits() {
        let narrow = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   notchWidth: 185, notchHeight: 32, hasNotch: true)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        for (version, lines) in WhatsNew.notes {
            XCTAssertLessThanOrEqual(lines.count, 3, "v\(version): room for three")
            for line in lines {
                let width = (line as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width, WhatsNewView.lineWidth(narrow), "v\(version): \(line)")
            }
        }
    }

    @MainActor func testTheCardFitsThePanel() {
        let narrow = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                   notchWidth: 0, notchHeight: 24, hasNotch: false)
        for (version, lines) in WhatsNew.notes {
            let card = WhatsNewView(geometry: narrow, note: .init(version: version, lines: lines))
                .fixedSize(horizontal: false, vertical: true)
            let fitting = NSHostingView(rootView: card).fittingSize.height
            XCTAssertLessThanOrEqual(fitting, narrow.openHeight + 0.5)
        }
    }

    @MainActor func testClosingTheNotchDismissesIt() {
        let expansion = Expansion()
        expansion.whatsNew = .init(version: "9.9", lines: ["x"])
        expansion.dismissWhatsNew()
        XCTAssertNil(expansion.whatsNew)
        XCTAssertEqual(UserDefaults.standard.string(forKey: WhatsNew.seenKey), "9.9")
        UserDefaults.standard.removeObject(forKey: WhatsNew.seenKey)
    }
}

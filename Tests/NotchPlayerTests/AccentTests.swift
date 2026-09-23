import XCTest
@testable import NotchPlayerCore

final class AccentTests: XCTestCase {
    /// `n` pixels of one colour, as RGBA bytes.
    private func pixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ n: Int) -> [UInt8] {
        Array([[r, g, b, 255]].joined()).repeated(n)
    }

    func testAGreyCoverKeepsTheLineWhite() {
        let photo = pixels(20, 20, 20, 300) + pixels(128, 128, 128, 200) + pixels(240, 240, 240, 76)
        XCTAssertNil(Accent.of(rgba: photo))
    }

    /// A black and white photo with a small red logo is still a grey cover.
    func testAFewColouredPixelsDoNotCount() {
        XCTAssertNil(Accent.of(rgba: pixels(30, 30, 30, 560) + pixels(230, 20, 20, 16)))
    }

    func testARedCoverGivesRed() {
        let c = Accent.of(rgba: pixels(200, 30, 40, 400) + pixels(10, 10, 10, 176))!
        XCTAssertGreaterThan(c.r, c.g + 0.2)
        XCTAssertGreaterThan(c.r, c.b + 0.2)
    }

    /// An average of the whole cover would turn red and blue purple.
    func testTheLargerColourWinsRatherThanAMix() {
        let c = Accent.of(rgba: pixels(210, 30, 30, 350) + pixels(30, 30, 210, 226))!
        XCTAssertGreaterThan(c.r, c.b + 0.2)
    }

    /// Navy on a black panel would vanish, so it is brightened -- and stays
    /// a real blue rather than a pastel.
    func testADarkCoverIsBrightenedAndStaysVivid() {
        let c = Accent.of(rgba: pixels(15, 25, 90, 576))!
        XCTAssertGreaterThanOrEqual(Accent.contrast(c, againstGrey: 0), 3.0)
        XCTAssertGreaterThan(c.b, 0.9)
        XCTAssertLessThan(c.r, 0.5, "washed toward white, not vivid")
    }

    /// Red needs no lightening at all on black: it stays pure.
    func testARedCoverIsNotWashedOut() {
        let c = Accent.of(rgba: pixels(150, 10, 10, 576))!
        XCTAssertEqual(c.r, 1, accuracy: 0.001)
        XCTAssertLessThan(c.g, 0.15)
    }

    /// Every hue, dark and bright, ends up over the floor on black.
    func testEveryColourClearsTheFloor() {
        for hue in stride(from: 0.0, to: 1.0, by: 1.0 / 24) {
            for brightness in [0.25, 0.5, 1.0] {
                let colour = NSColor(hue: hue, saturation: 0.9, brightness: brightness, alpha: 1)
                let px = pixels(UInt8(colour.redComponent * 255), UInt8(colour.greenComponent * 255),
                                UInt8(colour.blueComponent * 255), 100)
                let c = Accent.of(rgba: px)!
                XCTAssertGreaterThanOrEqual(Accent.contrast(c, againstGrey: 0), 3.0,
                                            "hue \(hue) brightness \(brightness)")
            }
        }
    }

    /// Through the real path: an `NSImage` drawn into the sample grid.
    func testAnImageGivesItsColour() {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: 0.1, green: 0.7, blue: 0.2, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let c = Accent.of(image)!
        XCTAssertGreaterThan(c.g, c.r + 0.2)
        XCTAssertGreaterThan(c.g, c.b + 0.2)
    }
}

private extension Array {
    func repeated(_ n: Int) -> [Element] { (0..<n).flatMap { _ in self } }
}

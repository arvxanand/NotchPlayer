import XCTest
@testable import NotchPlayerCore

final class BigCoverTests: XCTestCase {
    /// Reduce motion: big, and still.
    func testReduceMotionHoldsItStill() {
        for t in [0.0, 1.3, 50] {
            let angle = BigCover.tilt(time: t, pointer: CGPoint(x: 1, y: -1), reduced: true)
            XCTAssertEqual(angle.x, 0); XCTAssertEqual(angle.y, 0)
        }
    }

    func testWithThePointerInTheMiddleItOnlyDrifts() {
        let angle = BigCover.tilt(time: 0, pointer: .zero, reduced: false)
        XCTAssertEqual(angle.x, 0, accuracy: 0.001)
        XCTAssertEqual(angle.y, 9, accuracy: 0.001)
    }

    /// Leans toward the pointer, and never past drift plus lean, even with
    /// the pointer off the screen.
    func testItLeansTowardThePointerWithinLimits() {
        let right = BigCover.tilt(time: 0, pointer: CGPoint(x: 1, y: 0), reduced: false)
        XCTAssertGreaterThan(right.y, 9, "the right edge swings away")
        for t in stride(from: 0.0, to: 20, by: 0.37) {
            let angle = BigCover.tilt(time: t, pointer: CGPoint(x: -5, y: 5), reduced: false)
            XCTAssertLessThanOrEqual(abs(angle.x), 7 + 12)
            XCTAssertLessThanOrEqual(abs(angle.y), 9 + 14)
        }
    }

    func testThePointerIsMeasuredFromTheScreensMiddle() {
        let screen = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(BigCover.pointer(CGPoint(x: 100, y: 50), on: screen), .zero)
        XCTAssertEqual(BigCover.pointer(CGPoint(x: 200, y: 0), on: screen), CGPoint(x: 1, y: 1), "bottom right")
    }

    /// The big cover asks for Spotify's 640px file as is; everything else
    /// still gets the 300px swap.
    func testTheBigCoverFetchesTheFullSizeFile() {
        let url = URL(string: "https://i.scdn.co/image/ab67616d0000b273e045aa197ada995407bf92fc")!
        XCTAssertEqual(ArtworkCache.wanted(url, original: true), url)
        XCTAssertEqual(ArtworkCache.wanted(url, original: false).lastPathComponent,
                       "ab67616d00001e02e045aa197ada995407bf92fc")
    }

    /// Blurred once per cover, at the cover's own size; nothing for an
    /// image with no pixels.
    func testTheGlowIsTheCoverBlurredAtItsOwnSize() {
        let solid = NSImage(size: NSSize(width: 144, height: 144), flipped: false) { rect in
            NSColor.systemOrange.setFill(); rect.fill(); return true
        }
        XCTAssertEqual(BigCover.glow(solid)?.size, NSSize(width: 144, height: 144))
        XCTAssertNil(BigCover.glow(NSImage()))
    }
}

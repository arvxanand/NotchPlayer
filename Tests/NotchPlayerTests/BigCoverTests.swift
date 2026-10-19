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

    // MARK: - The record

    /// Pausing or playing never makes the record jump.
    func testTheRecordNeverJumpsWhenPlayFlips() {
        var spin = BigCover.Spin()
        spin.set(playing: true, at: 0)
        for t in [0.2, 1.7, 4.0] {
            let before = spin.angle(at: t)
            spin.set(playing: !spin.playing, at: t)
            XCTAssertEqual(spin.angle(at: t), before.truncatingRemainder(dividingBy: 360), accuracy: 0.01)
        }
    }

    /// Playing, it settles at its speed; paused, it comes to rest.
    func testItSettlesAtItsSpeedAndStopsWhenPaused() {
        var spin = BigCover.Spin()
        spin.set(playing: true, at: 0)
        XCTAssertEqual(spin.angle(at: 3) - spin.angle(at: 2), BigCover.Spin.speed, accuracy: 1)
        spin.set(playing: false, at: 3)
        XCTAssertLessThan(abs(spin.angle(at: 7) - spin.angle(at: 6)), 0.1)
        XCTAssertGreaterThan(spin.angle(at: 6), spin.angle(at: 3), "it coasts before it stops")
    }

    /// The cover and the lyrics beside it fit in the stage on a small, a
    /// middling and a large screen, with room for lines of real length.
    func testTheLyricsFitBesideTheCover() {
        for size in [CGSize(width: 1440, height: 900), CGSize(width: 1512, height: 982),
                     CGSize(width: 1920, height: 1243)] {
            let screen = CGRect(origin: .zero, size: size)
            let stage = BigCover.stageSize(on: screen)
            let row = BigCover.side(on: screen) + BigCover.lyricsGap(on: screen) + BigCover.lyricsWidth(on: screen)
            XCTAssertLessThanOrEqual(stage.width, size.width, "\(size)")
            XCTAssertLessThanOrEqual(row + 2 * BigCover.margin(on: screen), stage.width + 0.5, "\(size)")
            XCTAssertGreaterThanOrEqual(BigCover.lyricsWidth(on: screen), 500, "\(size)")
        }
    }
}

import XCTest
@testable import NotchPlayerCore

final class RepeatTests: XCTestCase {
    /// Spotify's own order.
    func testTheButtonCyclesOffAllOne() {
        XCTAssertEqual(Modes.next(after: .off), .all)
        XCTAssertEqual(Modes.next(after: .all), .one)
        XCTAssertEqual(Modes.next(after: .one), .off)
    }

    /// Repeat-one only means anything with Spotify repeating underneath it.
    func testTheModeComesFromSpotifysRepeatAndOurs() {
        XCTAssertEqual(Modes(shuffle: false, repeating: false).repeatMode, .off)
        XCTAssertEqual(Modes(shuffle: false, repeating: true).repeatMode, .all)
        XCTAssertEqual(Modes(shuffle: false, repeating: true, one: true).repeatMode, .one)
        XCTAssertEqual(Modes(shuffle: false, repeating: false, one: true).repeatMode, .off)
    }

    /// Jump back just before the end, never after it.
    func testTheLoopFiresJustBeforeTheEnd() {
        XCTAssertEqual(SpotifyService.loopDelay(duration: 200, position: 50)!,
                       200 - 50 - SpotifyService.loopLead, accuracy: 0.001)
        // Already past the point: at once, not a negative wait.
        XCTAssertEqual(SpotifyService.loopDelay(duration: 200, position: 199.9), 0)
        // A zero-length or tiny track has nothing to loop.
        XCTAssertNil(SpotifyService.loopDelay(duration: 0, position: 0))
    }
}

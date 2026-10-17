import XCTest
@testable import NotchPlayerCore

/// Spotify's restore file, rebuilt from invented protobuf pieces in the shape
/// measured on 15 Oct 2026 (TRAPS #78). Never a copy of a real one: it holds
/// the account's id and what it played.
final class QueueTests: XCTestCase {
    // MARK: - Building a file

    private func varint(_ value: Int) -> [UInt8] {
        var value = UInt64(value), out: [UInt8] = []
        repeat {
            out.append(UInt8(value & 0x7f) | (value > 0x7f ? 0x80 : 0))
            value >>= 7
        } while value > 0
        return out
    }

    private func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private func field(_ number: Int, _ text: String) -> [UInt8] { field(number, Array(text.utf8)) }

    /// A 16-byte id whose base62 is easy to predict: `n` in the last byte.
    private func song(_ n: UInt8) -> [UInt8] { Array(repeating: 0, count: 15) + [n] }
    private func id(_ n: UInt8) -> String { SpotifyQueue.base62(song(n)[...])! }
    private func localURI(_ n: UInt8) -> String { "spotify:local:Some+Artist::Song+%E2%80%99\(n)%3A+Live:197" }

    private func node(_ name: String, _ state: [UInt8]) -> [UInt8] {
        field(1, field(1, "spotify.player.proto." + name) + field(2, state))
    }

    /// Rows 1...6 of a playlist, played in `order`, with row `playing` on now
    /// and `queued` songs added by hand.
    /// Nil `playing` is a queued song on, when Spotify saves no row but its
    /// `place` in the order, already on the next one; 0 is left out, as
    /// protobuf does.
    private func file(queued: [UInt8] = [], order: [UInt8] = [1, 2, 3, 4, 5, 6], playing: UInt8? = 1,
                      place: Int = 0, local: Set<UInt8> = [], autoplay: String? = nil) -> [UInt8] {
        // A local file leaves the id empty and carries its URI in field 1.
        func entry(_ n: UInt8) -> [UInt8] {
            local.contains(n) ? field(1, localURI(n)) + field(3, []) : field(1, []) + field(3, song(n))
        }
        let rows = (1...6).map { n in field(4, entry(n) + field(2, "row\(n)")) }
        let row = playing.map { field(2, field(1, field(2, "row\($0)") + field(3, song($0)))) } ?? []
        let context = row
            + field(6, field(1, field(1, "spotify:playlist:abc") + field(5, rows.flatMap { $0 }))
                       + field(2, field(3, order.flatMap { field(2, field(2, "row\($0)")) }))
                       + (place == 0 ? [] : varint(5 << 3) + varint(place)))
        let queue = queued.enumerated().flatMap { index, n in
            field(1, entry(100 + n) + field(2, "q\(index)"))
        }
        // Autoplay: songs 51...53 from a radio context of their own, inside
        // `AutoplayNode`, with nothing of it played yet.
        let radio = autoplay.map { uri in
            field(6, field(1, field(1, uri) + field(5, (51...53).flatMap { n in
                                 field(4, field(1, []) + field(2, "a\(n)") + field(3, song(UInt8(n)))) }))
                       + field(2, field(3, (51...53).flatMap { field(2, field(2, "a\($0)")) })))
        }
        // A `GlobalNode` first, as Spotify saves it from the second autoplay
        // song on: the context must be found by name, not by place.
        let autoplayNode = radio.map {
            node("AutoplayNode", node("GlobalNode", field(2, field(1, "premium")))
                                 + field(1, field(1, "spotify.player.proto.ContextNode") + field(2, $0)))
        } ?? []
        // The nested autoplay context has no rows; it must not be taken.
        let nodes = autoplayNode + node("ContextNode", field(2, [])) + node("ContextNode", context) + node("PlayQueueNode", queue)
        let message = field(3, field(3, field(1, field(18, field(16, field(1, "player") + field(2, field(12, nodes)))))))
        return Array("1792115328087#".utf8) + message
    }

    // MARK: - The tests

    /// A file saved before the song changed lists the song now playing first;
    /// the page shows it moved on by one rather than waiting with nothing.
    func testAStaleFileIsShownMovedOnByOne() {
        let ids = (0..<12).map { "s\($0)" }
        let state = SpotifyQueue.State(queued: [], upcoming: ids, context: nil)
        XCTAssertEqual(QueueView.upNext(state, playing: "s0"), Array(ids[1...10]))
        XCTAssertEqual(QueueView.upNext(state, playing: "elsewhere"), Array(ids[0..<10]))
    }

    func testAutoplayComesAfterTheContextRunsOut() {
        let state = SpotifyQueue.parse(file(order: [1, 2], playing: 2, autoplay: "spotify:station:track:x"))
        XCTAssertEqual(state?.upcoming, [id(51), id(52), id(53)], "one song from search: all that's next is autoplay")
        XCTAssertEqual(SpotifyQueue.parse(file(playing: 4, autoplay: "spotify:station:track:x"))?.upcoming,
                       [id(5), id(6), id(51), id(52), id(53)])
    }

    func testAutoplayPlayingIsNotListedTwice() {
        let state = SpotifyQueue.parse(file(playing: 4, autoplay: "spotify:playlist:abc"))
        XCTAssertEqual(state?.upcoming, [id(5), id(6)])
    }

    func testALocalFileIsKeptInItsPlaceByItsURI() {
        let state = SpotifyQueue.parse(file(queued: [7], local: [3, 107]))
        XCTAssertEqual(state?.queued, [localURI(107)])
        XCTAssertEqual(state?.upcoming, [id(2), localURI(3), id(4), id(5), id(6)])
    }

    func testALocalFileIsNamedFromItsURI() throws {
        let song = try XCTUnwrap(QueueView.local(localURI(3)))
        XCTAssertEqual(song.name, "Song \u{2019}3: Live")
        XCTAssertEqual(song.artist, "Some Artist")
        XCTAssertNil(QueueView.local("spotify:track:abc"))
    }

    func testTheSongsComeAfterThePlayingRowInPlayOrder() {
        let state = SpotifyQueue.parse(file(order: [4, 2, 6, 1, 5, 3], playing: 6))
        XCTAssertEqual(state?.upcoming, [id(1), id(5), id(3)], "shuffled: the saved order, not the playlist's")
        XCTAssertEqual(state?.context, "spotify:playlist:abc")
        XCTAssertEqual(state?.queued, [])
    }

    /// Songs queued by hand play first, then the playlist; the page shows five.
    func testQueuedSongsComeFirstAndTheListStopsAtFive() {
        let state = SpotifyQueue.parse(file(queued: [7, 8], playing: 2))
        XCTAssertEqual(state?.queued, [id(107), id(108)])
        XCTAssertEqual(state?.next(5), [id(107), id(108), id(3), id(4), id(5)])
    }

    /// A row id, not a song: the same song twice in a playlist must not send
    /// the list back to its first copy.
    func testThePlaceIsTheRowNotTheSong() {
        XCTAssertEqual(SpotifyQueue.parse(file(playing: 4))?.upcoming, [id(5), id(6)])
        XCTAssertEqual(SpotifyQueue.parse(file(playing: 6))?.upcoming, [], "end of the playlist")
        XCTAssertEqual(SpotifyQueue.parse(file(order: [1, 2], playing: 6))?.upcoming, [],
                       "playing a row the order doesn't have: nothing guessed")
    }

    /// While a queued song plays there is no playing row; Spotify's place
    /// then already points at the next one (checked 15 Oct 2026).
    func testWithAQueuedSongOnThePlaceSaysWhatsNext() {
        let state = SpotifyQueue.parse(file(queued: [7], order: [4, 2, 6, 1, 5, 3], playing: nil, place: 3))
        XCTAssertEqual(state?.next(5), [id(107), id(1), id(5), id(3)])
        XCTAssertEqual(SpotifyQueue.parse(file(playing: nil))?.upcoming.first, id(1), "no place saved: the start")
    }

    func testAnythingElseIsUnreadable() {
        XCTAssertNil(SpotifyQueue.parse([]))
        XCTAssertNil(SpotifyQueue.parse(Array("no hash here".utf8)))
        XCTAssertNil(SpotifyQueue.parse(Array("1#".utf8) + [0xFF, 0xFF, 0xFF]), "not protobuf")
        XCTAssertNil(SpotifyQueue.parse(Array("1#".utf8) + field(3, "x")), "no player nodes")
    }

    func testIDsAreSpotifysBase62() {
        let one: [UInt8] = [0x14, 0xd4, 0x76, 0x33, 0x13, 0xdf, 0x47, 0xa1,
                            0xb5, 0x87, 0x8c, 0x51, 0x3b, 0x47, 0xc9, 0xf5]
        XCTAssertEqual(SpotifyQueue.base62(one[...]), "0DiWol3AO6WpXZgp0goxAV")
        XCTAssertEqual(SpotifyQueue.base62(song(1)[...]), "0000000000000000000001")
        XCTAssertEqual(SpotifyQueue.base62(Array(repeating: 0xFF, count: 16)[...]), "7N42dgm5tFLK9N8MT7fHC7")
        XCTAssertNil(SpotifyQueue.base62([1, 2, 3][...]), "not an id")
    }

    func testTheFileIsFoundUnderAnyAccount() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(SpotifyQueue.read(home: home.path), "no Spotify")
        let account = home.appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users/x-user")
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try Data(file(playing: 5)).write(to: account.appendingPathComponent("context_player_state_restore"))
        XCTAssertEqual(SpotifyQueue.read(home: home.path)?.upcoming, [id(6)])
    }
}

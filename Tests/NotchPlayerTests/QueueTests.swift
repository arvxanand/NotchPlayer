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

    func testTheFileIsFoundUnderAnyAccount() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let nothing = await SpotifyQueue.read(home: home.path)
        XCTAssertNil(nothing, "no Spotify")
        let account = home.appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users/x-user")
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        let old = account.appendingPathComponent("context_player_state_restore")
        try Data(file(playing: 5)).write(to: old)
        let before = await SpotifyQueue.read(home: home.path)
        XCTAssertEqual(before?.upcoming, [id(6)])

        // Spotify updated to 1.3.10, the old file left behind: the newer wins.
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: old.path)
        try Data(request(shuffle: "stable:d00d")).write(to: account.appendingPathComponent("list_player_play_request"))
        let after = await SpotifyQueue.read(home: home.path)
        XCTAssertEqual(after?.unshown, .shuffled)
        XCTAssertEqual(after?.context, "spotify:playlist:abc")
    }

    // MARK: - Spotify 1.3.10+

    /// `list_player_play_request` as measured on 19 Nov 2026, invented values.
    private func request(context: String = "spotify:playlist:abc", song: String = "spotify:track:B",
                         from: String = "context", shuffle: String? = nil) -> [UInt8] {
        field(1, field(1, context)
                 + field(4, field(1, field(1, "0123456789abcdef") + field(2, song) + field(4, from)))
                 + field(8, field(1, field(3, "0123456789abcdef") + (shuffle.map { field(4, $0) } ?? []))))
    }

    func testThePlayRequestSaysWhatPlaysAndWhetherShuffled() throws {
        let plain = try XCTUnwrap(SpotifyQueue.playRequest(request()))
        XCTAssertEqual(plain.context, "spotify:playlist:abc")
        XCTAssertEqual(plain.song, "spotify:track:B")
        XCTAssertFalse(plain.shuffled)
        XCTAssertEqual(plain.from, "context")
        XCTAssertEqual(SpotifyQueue.playRequest(request(shuffle: "stable:d4c95230(495d40f7.00000000)"))?.shuffled, true)
        XCTAssertEqual(SpotifyQueue.playRequest(request(from: "autoplay"))?.from, "autoplay")
        XCTAssertNil(SpotifyQueue.playRequest([0xFF, 0xFF]), "not protobuf")
        XCTAssertNil(SpotifyQueue.playRequest(field(1, field(1, "spotify:playlist:abc"))), "no song")
    }

    func testOnlyAPlaylistAlbumOrArtistHasAnEmbedPage() {
        XCTAssertEqual(SpotifyQueue.embedURL("spotify:album:X1")?.absoluteString, "https://open.spotify.com/embed/album/X1")
        XCTAssertNil(SpotifyQueue.embedURL("spotify:user:someone:collection"), "Liked Songs")
        XCTAssertNil(SpotifyQueue.embedURL("spotify:station:track:X1"))
        XCTAssertNil(SpotifyQueue.embedURL("spotify:playlist:a/../b"))
    }

    func testTheEmbedPageListsTheSongsInOrder() {
        let html = #"""
            <html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":
            {"entity":{"uri":"spotify:playlist:abc","trackList":[{"uri":"spotify:track:A","title":"One"},
            {"uri":"spotify:track:B"},{"uri":"spotify:track:C"},{"uri":"spotify:track:D"}]}}}}}}</script></html>
            """#
        XCTAssertEqual(SpotifyQueue.embedSongs(html),
                       ["spotify:track:A", "spotify:track:B", "spotify:track:C", "spotify:track:D"])
        XCTAssertNil(SpotifyQueue.embedSongs("<html>no data</html>"))
        // DJ and personal mixes: a page that says 404 with HTTP 200.
        let missing = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"status":404,"title":"Page not found"}}}</script>"#
        XCTAssertEqual(SpotifyQueue.embedSongs(missing), [])
    }

    private func playing(_ song: String, from: String = "context", context: String = "spotify:playlist:abc",
                         shuffled: Bool = false) -> SpotifyQueue.Playing {
        SpotifyQueue.Playing(context: context, song: song, shuffled: shuffled, from: from)
    }

    func testTheSongsAfterThePlayingOneOrWhyNot() {
        let four = ["A", "B", "C", "D"].map { "spotify:track:\($0)" }
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:B"), four)?.upcoming, ["C", "D"])
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:D"), four)?.unshown, .end, "autoplay may follow")
        XCTAssertNil(SpotifyQueue.state(playing("spotify:track:Z"), four), "the playlist changed under it")
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:B"), [])?.unshown, .notShared, "a 404 page")

        let hundred = (0..<100).map { "spotify:track:s\($0)" }
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:far"), hundred)?.unshown, .pastFirst100)
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:s99"), hundred)?.unshown, .pastFirst100,
                       "the 100th song: the 101st exists, unseen")
        XCTAssertEqual(SpotifyQueue.state(playing("spotify:track:s97"), hundred)?.upcoming, ["s98", "s99"])
    }

    func testWhatNeedsNoPage() {
        XCTAssertNil(SpotifyQueue.unshown(playing("spotify:track:B")), "a playlist: ask its page")
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:B", shuffled: true)), .shuffled)
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:X", from: "autoplay", shuffled: true)), .picked,
                       "autoplay is picked, shuffle or not")
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:X", context: "spotify:station:artist:Y")), .picked)
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:X", context: "spotify:track:X")), .end,
                       "one song from search")
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:X", context: "spotify:user:me:collection")), .notShared,
                       "Liked Songs")
        XCTAssertEqual(SpotifyQueue.unshown(playing("spotify:track:X", context: "spotify:list:jam-list:0d36")), .notShared)
    }
}

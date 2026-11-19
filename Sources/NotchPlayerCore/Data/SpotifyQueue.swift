import Foundation

/// What Spotify plays next.
///
/// **Spotify's dictionary has no queue, and its window shows it only while
/// on screen** (TRAPS #49), so this reads Spotify's own files instead.
///
/// **Spotify 1.3.10 and later** (TRAPS #78) save no play order at all:
/// `list_player_play_request` holds the playlist or album playing, the song
/// and, with shuffle on, only a seed (`stable:…`) the order is worked out
/// from in memory. So with shuffle off the order is the context's own,
/// read from its public embed page (`open.spotify.com/embed/…`, the first
/// 100 songs, one ~100KB fetch); anything else the page says why in
/// plain words (`Unshown`). Songs queued by hand come first either way.
///
/// **Before 1.3.10** it was `context_player_state_restore`: a timestamp,
/// `#`, then a protobuf whose player nodes include
///
/// - `PlayQueueNode`: field 1, the songs queued by hand, next first; field 2,
///   the queued song playing now.
/// - `ContextNode`: field 2.1, the row playing now (2 a row id, 3 the song),
///   absent while a queued song plays; field 6.1.1 the playlist or album;
///   6.1.5.4 its rows; 6.2.3.2 the order they play in, by row id -- shuffled
///   when shuffle is on; 6.5 the place in that order.
///
/// **Rewritten when the song changes or shuffle flips, not when a song is
/// queued**, so a song queued mid-song shows up when the next one starts.
/// Whichever of the two files is newer is read, so an old one left behind
/// by an update is not taken. Read-only, and anything unexpected is nil:
/// the page then says it can't read the queue rather than showing the
/// wrong songs.
public enum SpotifyQueue {
    public struct State: Equatable, Sendable {
        /// Song ids, base62, in the order they play. A local file has no id
        /// and is its whole `spotify:local:…` URI instead (`isLocal`).
        public var queued: [String]
        public var upcoming: [String]
        /// `spotify:playlist:…`, `spotify:album:…`; nil when none was saved.
        public var context: String?
        /// Set when there are no songs to show and the page says why (1.3.10+).
        public var unshown: Unshown?

        public init(queued: [String], upcoming: [String], context: String?, unshown: Unshown? = nil) {
            self.queued = queued; self.upcoming = upcoming; self.context = context; self.unshown = unshown
        }

        /// The queued songs, then the rest, as many as the page shows.
        public func next(_ limit: Int) -> [String] {
            Array((queued + upcoming).prefix(limit))
        }
    }

    /// Why 1.3.10+ shows no songs, each checked on 19 Nov 2026 (TRAPS #78).
    public enum Unshown: Equatable, Sendable {
        /// Shuffle on: Spotify saves only a seed, the order is in memory.
        case shuffled
        /// Autoplay or radio: Spotify picks each song as it goes.
        case picked
        /// No true public list: private playlists and Liked Songs (a
        /// `37i9dQZF1F…` playlist on 1.3.10) answer 404; DJ, Daily Mixes and
        /// radio are made per listener, so their public page lists other songs.
        case notShared
        /// The embed page lists a playlist's first 100 songs only.
        case pastFirst100
        /// The context's last song with repeat off (or one song played from
        /// search). Autoplay may follow; whether it is on isn't saved here.
        case end
    }

    /// The newest save under any account; nil if there is none or it does
    /// not read. Asks Spotify's embed page when the save is 1.3.10's.
    public static func read(home: String = NSHomeDirectory()) async -> State? {
        guard let file = newest(home: home), let data = try? Data(contentsOf: file) else { return nil }
        guard file.lastPathComponent == request else { return parse([UInt8](data)) }
        func sibling(_ name: String) -> [UInt8] {
            (try? Data(contentsOf: file.deletingLastPathComponent().appendingPathComponent(name))).map { [UInt8]($0) } ?? []
        }
        guard var playing = playRequest([UInt8](data)) else { return nil }
        playing.repeating = Proto.varint(5, in: sibling("list_player_playback_settings")[...]) == 1
        let queued = queue(sibling("list_player_queue_operations"), playing: playing)
        // A queued song is on: the context goes on from its own place.
        if playing.from == "queue" {
            guard let song = lastPlayed(sibling("list_player_play_history"), in: playing.context) else { return nil }
            playing.song = song
        }
        func adding(_ state: State?) -> State? { state.map { var state = $0; state.queued = queued; return state } }
        if let why = unshown(playing) { return adding(State(queued: [], upcoming: [], context: playing.context, unshown: why)) }
        guard let url = embedURL(playing.context), let html = await fetch(url),
              let songs = embedSongs(html) else { return nil }
        return adding(state(playing, songs))
    }

    /// When Spotify last saved the file, to tell a fresh save from a stale one.
    public static func saved(home: String = NSHomeDirectory()) -> Date? {
        newest(home: home).map(modified)
    }

    private static func newest(home: String) -> URL? {
        let users = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users")
        let files = ((try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [])
            .flatMap { [$0.appendingPathComponent("context_player_state_restore"), $0.appendingPathComponent(request)] }
        return files.filter { FileManager.default.fileExists(atPath: $0.path) }.max { modified($0) < modified($1) }
    }

    private static let request = "list_player_play_request"

    /// Ephemeral, as for song pages: no cookies, nothing cached on disk.
    private static let session = URLSession(configuration: .ephemeral)

    private static func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Pure, so a test can call them

    struct Playing: Equatable {
        var context: String, song: String, shuffled = false
        /// Where the song came from: "context", "queue", "autoplay".
        var from: String? = nil
        var repeating = false
    }

    /// 1.3.10's `list_player_play_request`, plain protobuf: 1.1 the context,
    /// 1.4.1.2 the song playing, 1.4.1.4 where it came from, 1.8.1.4
    /// `stable:…` only while shuffle is on (measured 19 Nov 2026: there within
    /// 3s of turning it on, even paused; the file rewritten within a second of
    /// a song change).
    static func playRequest(_ file: [UInt8]) -> Playing? {
        func text(_ path: [UInt64]) -> String? {
            Proto.path(path, in: file[...]).first.map { String(decoding: $0, as: UTF8.self) }
        }
        guard let context = text([1, 1]), let song = text([1, 4, 1, 2]) else { return nil }
        return Playing(context: context, song: song, shuffled: text([1, 8, 1, 4])?.hasPrefix("stable:") ?? false,
                       from: text([1, 4, 1, 4]))
    }

    /// Songs queued by hand, next first, from `list_player_queue_operations`:
    /// field 1 per song, 1.2 its URI. Saved within ~3s of queueing; the
    /// queued song playing stays first until the next one starts, so it is
    /// dropped here (measured 19 Nov 2026 against Spotify's queue panel).
    static func queue(_ file: [UInt8], playing: Playing) -> [String] {
        var uris = Proto.fields(1, in: file[...]).compactMap { Proto.field(2, in: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
        if playing.from == "queue", uris.first == playing.song { uris.removeFirst() }
        return uris.compactMap { uri in
            LocalCover.isLocal(uri) ? uri : uri.hasPrefix("spotify:track:") ? String(uri.dropFirst(14)) : nil
        }
    }

    /// The context's own song played last, which it goes on from after the
    /// queued ones: `list_player_play_history` is newest first, field 1 per
    /// play, 1.1 the song, 1.2 the context, 1.3 the row -- "q…" for a queued
    /// song. (1.4.13 in the play request looked like it, but is the row the
    /// context was started from: wrong after the first song, 19 Nov 2026.)
    static func lastPlayed(_ file: [UInt8], in context: String) -> String? {
        func text(_ number: UInt64, _ entry: ArraySlice<UInt8>) -> String? {
            Proto.field(number, in: entry).map { String(decoding: $0, as: UTF8.self) }
        }
        return Proto.fields(1, in: file[...])
            .first { text(2, $0) == context && !(text(3, $0)?.hasPrefix("q") ?? true) }
            .flatMap { text(1, $0) }
    }

    /// What needs no page to say.
    static func unshown(_ playing: Playing) -> Unshown? {
        if playing.from == "autoplay" || playing.context.hasPrefix("spotify:station:") { return .picked }
        if playing.shuffled { return .shuffled }
        if playing.context.hasPrefix("spotify:track:") { return .end }
        // ponytail: Spotify's per-listener playlists by id prefix (Daily
        // Mixes, radio, DJ, Discover Weekly); an editorial one (37i9dQZF1DX…)
        // is the same for everyone and is read.
        if ["spotify:playlist:37i9dQZF1E", "spotify:playlist:37i9dQZEVX"].contains(where: playing.context.hasPrefix) {
            return .notShared
        }
        return embedURL(playing.context) == nil ? .notShared : nil
    }

    /// The songs after the playing one, or why there are none. Nil if the
    /// song isn't in a short list -- the playlist changed under it.
    /// ponytail: the first copy of a song that is in the list twice.
    static func state(_ playing: Playing, _ songs: [String]) -> State? {
        func note(_ why: Unshown) -> State { State(queued: [], upcoming: [], context: playing.context, unshown: why) }
        let capped = songs.count >= 100
        if songs.isEmpty { return note(.notShared) }
        guard let index = songs.firstIndex(of: playing.song) else { return capped ? note(.pastFirst100) : nil }
        // Repeat on: round again from the top (Spotify did, 19 Nov 2026).
        let order = songs[(index + 1)...] + (playing.repeating && !capped ? songs[...index] : [])
        let after = order.map { String($0.split(separator: ":").last ?? "") }
        if after.isEmpty { return note(capped ? .pastFirst100 : .end) }
        return State(queued: [], upcoming: after, context: playing.context)
    }

    /// `spotify:playlist:X` to its embed page; nil for what has none, like
    /// Liked Songs (`spotify:user:…:collection`) or a radio station.
    static func embedURL(_ context: String) -> URL? {
        let parts = context.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", ["playlist", "album", "artist"].contains(parts[1]),
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: "https://open.spotify.com/embed/\(parts[1])/\(parts[2])")
    }

    /// The embed page's songs, in the context's order, from its
    /// `__NEXT_DATA__` JSON (`props.pageProps.state.data.entity.trackList`).
    /// Empty when the page says 404 (`props.pageProps.status`, with HTTP
    /// 200): DJ and the personal mixes, checked 19 Nov 2026.
    static func embedSongs(_ html: String) -> [String]? {
        guard let start = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)),
              let props = ["props", "pageProps"].reduce(json as Any?, { ($0 as? [String: Any])?[$1] }) as? [String: Any]
        else { return nil }
        if props["status"] as? Int == 404 { return [] }
        let entity = ["state", "data", "entity"].reduce(props as Any?, { ($0 as? [String: Any])?[$1] }) as? [String: Any]
        return (entity?["trackList"] as? [[String: Any]])?.compactMap { $0["uri"] as? String }
    }

    static func parse(_ file: [UInt8]) -> State? {
        // "1792115328087#": milliseconds, then the message.
        guard let hash = file.prefix(32).firstIndex(of: UInt8(ascii: "#")) else { return nil }
        let nodes = Proto.path([3, 3, 1, 18, 16, 2, 12, 1], in: file[(hash + 1)...])
        func state(_ name: String, in nodes: [ArraySlice<UInt8>] = nodes) -> [ArraySlice<UInt8>] {
            nodes.filter { node in
                Proto.field(1, in: node).map { String(decoding: $0, as: UTF8.self) } == "spotify.player.proto." + name
            }.compactMap { Proto.field(2, in: $0) }
        }
        // The playing context is the one with rows; the autoplay one nested
        // beside it has none.
        guard let queue = state("PlayQueueNode").first,
              let context = state("ContextNode").first(where: { !Proto.path([6, 1, 5, 4], in: $0).isEmpty })
        else { return nil }

        let queued = Proto.fields(1, in: queue).compactMap(song)
        let uri = Proto.path([6, 1, 1], in: context).first.map { String(decoding: $0, as: UTF8.self) }
        // **Then autoplay**, Spotify's radio picks for when the context runs
        // out: one song played from search, the end of an album. They are a
        // second context inside `AutoplayNode`, among nodes like the top
        // level's -- found by name, because a `GlobalNode` comes first in some
        // saves and not others. Without them a single song read as "nothing
        // after this" while Spotify's queue showed fifty (owner's file, 17 Oct
        // 2026). If that context ever becomes the top-level one it is not
        // added twice.
        let autoplay = state("AutoplayNode").first
            .flatMap { state("ContextNode", in: Proto.fields(1, in: $0)).first }
        let autoplayURI = autoplay.flatMap { Proto.path([6, 1, 1], in: $0).first }.map { String(decoding: $0, as: UTF8.self) }
        let more = autoplay.flatMap { autoplayURI != uri ? upcoming(in: $0) : nil } ?? []
        return State(queued: queued, upcoming: (upcoming(in: context) ?? []) + more, context: uri)
    }

    /// A context's songs after the one playing, in play order; nil when the
    /// place in the order can't be found.
    static func upcoming(in context: ArraySlice<UInt8>) -> [String]? {
        var songs: [String: String] = [:]
        for row in Proto.path([6, 1, 5, 4], in: context) {
            if let id = Proto.field(2, in: row), let song = song(in: row) {
                songs[String(decoding: id, as: UTF8.self)] = song
            }
        }
        let order = Proto.path([6, 2, 3, 2], in: context)
            .compactMap { Proto.field(2, in: $0).map { String(decoding: $0, as: UTF8.self) } }
        let playing = Proto.path([2, 1, 2], in: context).first.map { String(decoding: $0, as: UTF8.self) }
        // Where the order goes on from: after the playing row, or -- while a
        // queued song plays and no row is -- the place Spotify keeps (6.5),
        // which then already points at the next row. Zero is left out of a
        // protobuf, so a missing place is the first row.
        let from = playing.map { order.firstIndex(of: $0).map { $0 + 1 } }
            ?? Proto.path([6], in: context).first.map { Int(Proto.varint(5, in: $0) ?? 0) }
        return from.map { order.dropFirst($0).compactMap { songs[$0] } }
    }

    /// A row's or queued entry's song: its id (3), or -- for a local file,
    /// which has none and leaves 3 empty -- its URI (1). Measured on the
    /// owner's file, 16 Oct 2026; before this a local song was dropped and
    /// the page skipped straight past it.
    static func song(in entry: ArraySlice<UInt8>) -> String? {
        if let id = Proto.field(3, in: entry).flatMap(base62) { return id }
        return Proto.field(1, in: entry).map { String(decoding: $0, as: UTF8.self) }
            .flatMap { LocalCover.isLocal($0) ? $0 : nil }
    }

    /// A 16-byte song id as the 22 characters a `spotify:track:` URI uses.
    static func base62(_ bytes: ArraySlice<UInt8>) -> String? {
        guard bytes.count == 16 else { return nil }
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var number = Array(bytes), out: [Character] = []
        // Long division by 62, most significant byte first, 22 times.
        for _ in 0..<22 {
            var remainder = 0
            for i in number.indices {
                let value = remainder << 8 | Int(number[i])
                number[i] = UInt8(value / 62)
                remainder = value % 62
            }
            out.append(alphabet[remainder])
        }
        return String(out.reversed())
    }

    // MARK: - Protobuf, just enough

    enum Varint {
        static func read<C: RandomAccessCollection>(_ bytes: C, _ i: inout C.Index) -> UInt64?
            where C.Element == UInt8 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < bytes.endIndex, shift < 64 {
                let byte = bytes[i]; i = bytes.index(after: i)
                result |= UInt64(byte & 0x7f) << shift
                if byte < 0x80 { return result }
                shift += 7
            }
            return nil
        }
    }

    /// Just enough protobuf to find length-delimited fields.
    enum Proto {
        static func field(_ number: UInt64, in bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
            fields(number, in: bytes).first
        }

        /// Every value of a repeated field, in order. Stops at the first byte
        /// that is not protobuf, keeping what came before it.
        static func fields(_ number: UInt64, in bytes: ArraySlice<UInt8>) -> [ArraySlice<UInt8>] {
            var i = bytes.startIndex, found: [ArraySlice<UInt8>] = []
            while i < bytes.endIndex {
                guard let tag = Varint.read(bytes, &i) else { return found }
                switch tag & 7 {
                case 0: guard Varint.read(bytes, &i) != nil else { return found }
                case 1: i += 8
                case 5: i += 4
                case 2:
                    guard let length = Varint.read(bytes, &i), length <= UInt64(bytes.endIndex - i) else { return found }
                    if tag >> 3 == number { found.append(bytes[i..<i + Int(length)]) }
                    i += Int(length)
                default: return found
                }
            }
            return found
        }

        /// A number field's first value.
        static func varint(_ number: UInt64, in bytes: ArraySlice<UInt8>) -> UInt64? {
            var i = bytes.startIndex
            while i < bytes.endIndex {
                guard let tag = Varint.read(bytes, &i) else { return nil }
                switch tag & 7 {
                case 0:
                    guard let value = Varint.read(bytes, &i) else { return nil }
                    if tag >> 3 == number { return value }
                case 1: i += 8
                case 5: i += 4
                case 2:
                    guard let length = Varint.read(bytes, &i), length <= UInt64(bytes.endIndex - i) else { return nil }
                    i += Int(length)
                default: return nil
                }
            }
            return nil
        }

        /// Every value at the end of a path of fields, each level repeated.
        static func path(_ numbers: [UInt64], in bytes: ArraySlice<UInt8>) -> [ArraySlice<UInt8>] {
            numbers.reduce([bytes]) { level, number in level.flatMap { fields(number, in: $0) } }
        }
    }
}

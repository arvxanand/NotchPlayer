import Foundation

/// What Spotify plays next, read from the file it keeps to resume after a
/// restart: `PersistentCache/Users/<id>-user/context_player_state_restore`.
///
/// **Spotify's dictionary has no queue, and its window shows it only while
/// on screen** (TRAPS #49), so this file is the one way to see it with
/// Spotify in full screen on another Space. Undocumented (TRAPS #78): a
/// timestamp, `#`, then a protobuf whose player nodes include
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
/// Read-only, and anything unexpected is nil: the page then says it can't read
/// the queue rather than showing the wrong songs.
public enum SpotifyQueue {
    public struct State: Equatable, Sendable {
        /// Song ids, base62, in the order they play. A local file has no id
        /// and is its whole `spotify:local:…` URI instead (`isLocal`).
        public var queued: [String]
        public var upcoming: [String]
        /// `spotify:playlist:…`, `spotify:album:…`; nil when none was saved.
        public var context: String?

        public init(queued: [String], upcoming: [String], context: String?) {
            self.queued = queued; self.upcoming = upcoming; self.context = context
        }

        /// The queued songs, then the rest, as many as the page shows.
        public func next(_ limit: Int) -> [String] {
            Array((queued + upcoming).prefix(limit))
        }
    }

    /// The newest restore file under any account; nil if there is none or it
    /// does not read.
    public static func read(home: String = NSHomeDirectory()) -> State? {
        let users = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users")
        let files = ((try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("context_player_state_restore") }
        let newest = files.max { modified($0) < modified($1) }
        return newest.flatMap { try? Data(contentsOf: $0) }.flatMap { parse([UInt8]($0)) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Pure, so a test can call them

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

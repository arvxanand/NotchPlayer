import Foundation

/// A song's words, from LRCLIB (lrclib.net): a free, public lyrics database
/// that needs no account. Spotify's own lyrics need a Spotify login, which
/// this app never asks for.
///
/// **Timed when they can be.** LRCLIB's `syncedLyrics` is LRC: one line per
/// sung line, each starting with the time it is sung, `[01:23.45]`. Some songs
/// only have the words (`plainLyrics`), and some are marked instrumental.
///
/// The app's network calls are listed in the README; this is one of them,
/// made only while lyrics are on screen, once per song per launch, and kept
/// on disk after that. It sends the song's name, artist, album and length.
public enum Lyrics: Equatable, Sendable, Codable {
    case synced([Line])
    case plain([String])
    case instrumental
    case none

    public struct Line: Equatable, Sendable, Codable {
        /// Seconds, like `Track.duration`.
        public let time: TimeInterval
        /// Empty for a gap in the singing, drawn as a note.
        public let text: String

        public init(time: TimeInterval, text: String) { self.time = time; self.text = text }
    }

    /// How early a line lights up. The position the player reports is a
    /// moment behind what is heard, and reading a line just before it is sung
    /// is easier than just after.
    ///
    /// ponytail: one fixed lead for every song. A per-song nudge in settings
    /// if timings ever feel off; LRCLIB's are typed in by hand.
    public static let lead: TimeInterval = 0.25

    /// Outside data is untrusted (`docs/SECURITY.md`): a reply with thousands
    /// of lines is cut, rather than laid out.
    static let maxLines = 500
    static let maxLineLength = 300

    // MARK: - Reading LRC

    /// Every timed line, in order. Untimed lines and tags like `[ar:Zedd]` are
    /// dropped; a line with several times (a repeated chorus) appears once at
    /// each.
    public static func parse(lrc: String) -> [Line] {
        var lines: [(order: Int, line: Line)] = []
        for raw in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]"),
                  let time = time(rest[rest.index(after: rest.startIndex)..<close]) {
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = String(rest.trimmingCharacters(in: .whitespaces).prefix(maxLineLength))
            for time in times { lines.append((lines.count, Line(time: time, text: text))) }
        }
        // Ties keep the file's order, so two lines at the same time read as written.
        return lines.sorted { ($0.line.time, $0.order) < ($1.line.time, $1.order) }
            .prefix(maxLines).map(\.line)
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`, in seconds. Nil for anything else,
    /// which is how a tag like `ar:Zedd` is told apart from a time.
    static func time(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), (0..<600).contains(minutes),
              parts[1].allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let seconds = Double(parts[1]), seconds < 60 else { return nil }
        return Double(minutes) * 60 + seconds
    }

    /// The line being sung at `position`, or nil before the first one.
    public static func index(of lines: [Line], at position: TimeInterval) -> Int? {
        let at = position + lead
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= at { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    // MARK: - LRCLIB

    /// One song as LRCLIB answers it, from `/api/get` or each `/api/search` result.
    struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func lyrics(from record: Record) -> Lyrics {
        if let synced = record.syncedLyrics {
            let lines = parse(lrc: synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics {
            let lines = plain.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { String($0.trimmingCharacters(in: .whitespaces).prefix(maxLineLength)) }
            if lines.contains(where: { !$0.isEmpty }) { return .plain(Array(lines.prefix(maxLines))) }
        }
        return record.instrumental == true ? .instrumental : .none
    }

    /// How far a version's length may be from the song's. LRCLIB keeps many
    /// copies of a song from different albums, a second or two apart; past
    /// this it is likely a live or extended cut, timed for something else.
    static let window: TimeInterval = 3

    /// The best of a search's versions: timed words first, then plain ones,
    /// then "instrumental", each from the version closest in length.
    static func best(in records: [Record], duration: TimeInterval) -> Lyrics {
        let near = records
            .filter { duration <= 0 || abs(($0.duration ?? -.infinity) - duration) <= window }
            .sorted { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
            .map(lyrics(from:))
        return near.first { if case .synced = $0 { true } else { false } }
            ?? near.first { if case .plain = $0 { true } else { false } }
            ?? near.first { $0 == .instrumental }
            ?? .none
    }

    /// The song's lyrics, from disk if seen before. Nil when LRCLIB could not
    /// be reached or was busy -- not the same as `.none`, and never saved.
    public static func find(_ track: Track) async -> Lyrics? {
        let file = cacheFile(for: track)
        if let saved = try? Data(contentsOf: file), let lyrics = try? JSONDecoder().decode(Lyrics.self, from: saved) {
            return lyrics
        }
        guard let found = await fetch(track) else { return nil }
        // `.none` stays in memory only, so words added to LRCLIB later are
        // found after a restart.
        if found != .none,
           (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
           let bytes = try? JSONEncoder().encode(found) {
            try? bytes.write(to: file, options: .atomic)
        }
        return found
    }

    /// The exact match first. It needs the album named as LRCLIB has it, which
    /// often differs (a single, a deluxe edition): then a search by title and
    /// artist, picking by length. A search is also tried when the exact match
    /// has no timings, since another copy of the song often does.
    static func fetch(_ track: Track) async -> Lyrics? {
        var exact: Lyrics?
        switch await request("get", [
            "artist_name": track.artist, "track_name": track.name, "album_name": track.album,
            "duration": String(Int(track.duration.rounded())),
        ]) {
        case .found(let body):
            guard let record = try? JSONDecoder().decode(Record.self, from: body) else { return nil }
            exact = lyrics(from: record)
            if case .synced = exact { return exact }
        case .missing:
            break
        case .failed:
            return nil
        }
        switch await request("search", ["artist_name": track.artist, "track_name": track.name]) {
        case .found(let body):
            guard let records = try? JSONDecoder().decode([Record].self, from: body) else { return exact }
            let searched = best(in: records, duration: track.duration)
            if case .synced = searched { return searched }
            return exact ?? searched
        case .missing:
            return exact ?? Lyrics.none
        case .failed:
            return exact
        }
    }

    enum Reply { case found(Data), missing, failed }

    /// 404 is "LRCLIB has no such song". Anything else that is not a 200 --
    /// a 503 "server busy" comes back for a miss when it is loaded, as do
    /// timeouts and no network -- is "ask again later".
    static func request(_ endpoint: String, _ query: [String: String]) async -> Reply {
        guard var components = URLComponents(string: "https://lrclib.net/api/" + endpoint) else { return .failed }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return .failed }
        var request = URLRequest(url: url, timeoutInterval: 6)
        // LRCLIB asks apps to say who they are.
        request.setValue("NotchPlayer/\(Updater.current) (https://github.com/arvxanand/NotchPlayer)",
                         forHTTPHeaderField: "User-Agent")
        guard let (body, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        return status == 200 ? .found(body) : status == 404 ? .missing : .failed
    }

    /// Ephemeral, like `StoreCover`: no cookies, no URL cache. The answer
    /// itself is kept in `directory`.
    private static let session = URLSession(configuration: .ephemeral)

    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchPlayer/lyrics", isDirectory: true)

    /// Named for the song's id, made safe as a filename the way
    /// `ArtworkCache.filename(for:)` does.
    public static func cacheFile(for track: Track) -> URL {
        let safe = track.id.replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent(String(safe.suffix(120)) + ".json")
    }
}

/// Lyrics already found this launch, on the main actor, so a view can read
/// them synchronously -- the same job `ArtMemory` does for covers.
@MainActor
public final class LyricsStore: ObservableObject {
    public static let shared = LyricsStore()

    /// ponytail: never emptied. A few KB a song, and only songs whose lyrics
    /// were shown; cap it like `ArtMemory` if that ever adds up.
    @Published private(set) var found: [String: Lyrics] = [:]
    @Published private(set) var failed: Set<String> = []
    private var inFlight: Set<String> = []

    public init() {}

    public func content(for track: Track) -> LyricsPage.Content {
        if let lyrics = found[track.id] { return .lyrics(lyrics) }
        return failed.contains(track.id) ? .failed : .loading
    }

    /// Fire and forget; publishes when the answer arrives. A song that failed
    /// is asked again, so showing the lyrics again after the network is back
    /// finds them.
    public func load(_ track: Track) {
        let key = track.id
        guard found[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        failed.remove(key)
        Task { [weak self] in
            let lyrics = await Lyrics.find(track)
            guard let self else { return }
            inFlight.remove(key)
            if let lyrics { found[key] = lyrics } else { failed.insert(key) }
        }
    }
}

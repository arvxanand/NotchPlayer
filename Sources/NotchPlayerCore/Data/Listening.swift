import Combine
import Foundation

/// What was listened to, kept on this Mac only, for the stats page.
///
/// **Counted from what the app already sees.** Both services publish every
/// state change, so a play is a run of one song from when it started to when
/// another took over. Its time is the seconds it was actually playing, added
/// up on a timer while it plays -- paused time, and time the Mac slept, never
/// count. Only while NotchPlayer is running: it cannot see what played
/// without it.
public struct Play: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let started: Date
    public var seconds: TimeInterval

    public init(id: String, name: String, artist: String, started: Date, seconds: TimeInterval) {
        self.id = id; self.name = name; self.artist = artist; self.started = started; self.seconds = seconds
    }
}

@MainActor
public final class Listening: ObservableObject {
    @Published public private(set) var plays: [Play]

    private let file: URL?
    /// The play each app is on, by index into `plays`, and when it was last
    /// counted up to.
    private var current: [Source: (index: Int, counted: Date?)] = [:]
    private var tick: Timer?
    private var bag: [AnyCancellable] = []

    /// How often a playing song's time is added, and the most one tick may add.
    /// The cap is what keeps a sleep from counting: the timer does not fire
    /// while the Mac is asleep, so the first tick after waking would otherwise
    /// add the whole night.
    static let every: TimeInterval = 10
    static let cap: TimeInterval = 15

    /// `nil` keeps everything in memory, for tests.
    public init(file: URL? = Listening.defaultFile) {
        self.file = file
        plays = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Play].self, from: $0) } ?? []
    }

    public nonisolated static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotchPlayer/listening.json")
    }

    public func follow(_ players: Players) {
        for service in [players.spotify, players.music] {
            let source = service.source
            bag.append(service.$now.sink { [weak self] now in
                MainActor.assumeIsolated { self?.saw(now, from: source) }
            })
        }
        let timer = Timer(timeInterval: Self.every, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.count(at: Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// A state change from one app.
    func saw(_ now: Now, from source: Source, at date: Date = Date()) {
        count(source, at: date)
        guard let track = now.track, !track.id.hasPrefix("spotify:ad:") else {
            current[source] = nil
            return save()
        }
        if let open = current[source], plays.indices.contains(open.index), plays[open.index].id == track.id {
            current[source]?.counted = now.isPlaying ? date : nil
        } else {
            plays.append(Play(id: track.id, name: track.name, artist: track.artist, started: date, seconds: 0))
            current[source] = (plays.count - 1, now.isPlaying ? date : nil)
        }
        save()
    }

    /// Adds what has played since the last count, for every app that is playing.
    func count(at date: Date) {
        for source in current.keys { count(source, at: date) }
        // ponytail: rewrites the whole file each tick while playing; a year
        // is ~20k plays, ~3MB. Daily totals for old plays if that ever shows.
        if current.values.contains(where: { $0.counted != nil }) { save() }
    }

    private func count(_ source: Source, at date: Date) {
        guard let open = current[source], let since = open.counted, plays.indices.contains(open.index)
        else { return }
        plays[open.index].seconds += min(max(0, date.timeIntervalSince(since)), Self.cap)
        current[source]?.counted = date
    }

    public func flush() {
        count(at: Date())
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(plays) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// The numbers the stats page shows, worked out from the plays. Pure.
public enum Stats {
    public enum Range: CaseIterable, Sendable {
        case today, week, month, all

        public var title: String {
            switch self {
            case .today: "Today"
            case .week: "Week"
            case .month: "Month"
            case .all: "All"
            }
        }
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let seconds: TimeInterval
        public let plays: Int
    }

    public struct Summary: Equatable, Sendable {
        public let seconds: TimeInterval
        public let songs: Int
        public let artists: [Entry]
        public let tracks: [Entry]
    }

    /// Spotify's own rule for counting a play: 30 seconds. Shorter is a skip;
    /// its time still counts.
    public static let playedAfter: TimeInterval = 30

    /// Today, this week and this month are the calendar's, in the user's
    /// own calendar and first weekday.
    public static func summary(_ plays: [Play], _ range: Range, now: Date = Date(),
                               calendar: Calendar = .current, top: Int = 3) -> Summary {
        let start: Date? = switch range {
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: calendar.dateInterval(of: .month, for: now)?.start
        case .all: nil
        }
        let inRange = plays.filter { play in start.map { play.started >= $0 } ?? true }
        let counted = inRange.filter { $0.seconds >= playedAfter }

        var artists: [String: (seconds: TimeInterval, plays: Int)] = [:]
        for play in inRange where !play.artist.isEmpty {
            artists[play.artist, default: (0, 0)].seconds += play.seconds
            if play.seconds >= playedAfter { artists[play.artist, default: (0, 0)].plays += 1 }
        }
        var tracks: [String: (name: String, seconds: TimeInterval, plays: Int)] = [:]
        for play in counted {
            tracks[play.id, default: (play.name, 0, 0)].seconds += play.seconds
            tracks[play.id, default: (play.name, 0, 0)].plays += 1
        }
        return Summary(
            seconds: inRange.reduce(0) { $0 + $1.seconds },
            songs: counted.count,
            artists: artists.map { Entry(name: $0.key, seconds: $0.value.seconds, plays: $0.value.plays) }
                .filter { $0.seconds >= 1 }
                .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
                .prefix(top).map { $0 },
            tracks: tracks.values.map { Entry(name: $0.name, seconds: $0.seconds, plays: $0.plays) }
                .sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }
                .prefix(top).map { $0 })
    }

    /// "2h 14m", "14m", "0m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

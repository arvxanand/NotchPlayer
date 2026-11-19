import Foundation

/// The last song each app played, kept so the notch can show it -- and play
/// it -- while that app is closed.
///
/// A friend opened his laptop, looked for the notch and found nothing,
/// because Spotify was closed. Now the notch shows the song he last played,
/// paused, and pressing play starts the app in the background
/// (`QuietLaunch`). Kept for good, until something else plays; one small
/// record per app in UserDefaults. The cover is already on disk
/// (`ArtworkCache`), so nothing is fetched to draw it.
///
/// **Never put into `now`.** The listening stats, the audio tap and the app
/// picker all follow `now`, and a song that is not playing must not count as
/// one that is.
public enum LastPlayed {
    /// The settings switch, on unless turned off.
    public static let enabledKey = "showLastWhenClosed"
    public static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Which app played last, so a restart picks the right one's song.
    static let sourceKey = "lastPlayedSource"

    static func key(_ source: Source) -> String { "lastPlayed." + source.name }

    public static func load(_ source: Source, defaults: UserDefaults = .standard) -> Track? {
        defaults.data(forKey: key(source)).flatMap { try? JSONDecoder().decode(Track.self, from: $0) }
    }

    /// Ads are not songs anyone wants back.
    public static func save(_ track: Track, defaults: UserDefaults = .standard) {
        guard !track.id.hasPrefix("spotify:ad:"), let data = try? JSONEncoder().encode(track) else { return }
        defaults.set(data, forKey: key(track.source))
    }

    static func lastSource(defaults: UserDefaults = .standard) -> Source? {
        defaults.string(forKey: sourceKey).flatMap { name in Source.allCases.first { $0.name == name } }
    }

    static func setLastSource(_ source: Source, defaults: UserDefaults = .standard) {
        defaults.set(source.name, forKey: sourceKey)
    }
}

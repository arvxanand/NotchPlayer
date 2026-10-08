import Foundation

/// A playlist or album on the notch's second page. Tapping it plays it.
///
/// **There is no way to list someone's playlists without the Web API**, which
/// this app does not use (5-user cap). So the user adds each one: Share →
/// Copy link in Spotify, then the page's + reads the clipboard. Playing needs
/// nothing more than Spotify's own `play track "<uri>"`, which works from the
/// background, in full screen, with no Accessibility. Measured 8 Oct 2026,
/// including DJ and Liked Songs.
public struct Pick: Codable, Equatable, Identifiable, Sendable {
    public let uri: String
    public let name: String
    /// Nil for the built-ins, which draw an icon, and for a playlist whose
    /// preview did not answer (private, or offline), which draws the mark.
    public let cover: URL?
    public var id: String { uri }

    public init(uri: String, name: String, cover: URL? = nil) {
        self.uri = uri; self.name = name; self.cover = cover
    }

    /// **DJ is a playlist id like any other**, but personal: the public preview
    /// answers 404 for it, so it gets a name and an icon of its own. Premium only.
    public static let dj = Pick(uri: "spotify:playlist:37i9dQZF1EYkqdzj48dyYq", name: "DJ")
    /// The short form plays the user's own Liked Songs without their username.
    /// The preview answers 400 for it.
    public static let liked = Pick(uri: "spotify:collection:tracks", name: "Liked Songs")
    public static let builtIns = [dj, liked]

    /// The built-ins' icons, an SF Symbol name. Nil for everything else.
    public var symbol: String? {
        switch uri {
        case Self.dj.uri: "headphones"
        case Self.liked.uri: "heart.fill"
        default: nil
        }
    }
}

/// The user's picks, kept in UserDefaults.
@MainActor
public final class Picks: ObservableObject {
    public static let key = "picks"

    @Published public private(set) var all: [Pick]
    private let defaults: UserDefaults

    /// Seeded with DJ and Liked Songs the first time. Removing them is just
    /// removing; pasting their link brings them back.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        all = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Pick].self, from: $0) } ?? Pick.builtIns
    }

    public enum Added: Equatable, Sendable { case added, already, notALink }

    /// What the page's + does with whatever is on the clipboard.
    public func add(link text: String?) async -> Added {
        guard let text, let uri = Self.uri(fromLink: text) else { return .notALink }
        guard !all.contains(where: { $0.uri == uri }) else { return .already }
        let pick: Pick
        if let builtIn = Pick.builtIns.first(where: { $0.uri == uri }) {
            pick = builtIn
        } else {
            let preview = await Self.preview(for: uri)
            pick = Pick(uri: uri, name: preview?.name ?? Self.fallbackName(uri), cover: preview?.cover)
        }
        // Asked again: two taps can both be waiting on the preview.
        guard !all.contains(where: { $0.uri == uri }) else { return .already }
        all.append(pick)
        save()
        return .added
    }

    public func remove(_ uri: String) {
        all.removeAll { $0.uri == uri }
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    nonisolated static let kinds = ["playlist", "album"]

    /// A Spotify link or URI to a `spotify:` URI, or nil.
    ///
    /// **The trust boundary.** Clipboard text ends up inside an AppleScript,
    /// so only `spotify:<kind>:<letters and digits>` or a built-in gets out of
    /// here. Takes the share link (`https://open.spotify.com/playlist/<id>?si=…`)
    /// and the `spotify:playlist:<id>` form.
    public nonisolated static func uri(fromLink text: String) -> String? {
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Pick.builtIns.contains(where: { $0.uri == link }) { return link }
        for kind in kinds {
            if let uri = SpotifyLinks.Page.uri(link, kind: kind) { return uri.absoluteString }
            let prefix = "spotify:\(kind):"
            if link.hasPrefix(prefix), SpotifyLinks.isID(link.dropFirst(prefix.count)) { return link }
        }
        return nil
    }

    nonisolated static func fallbackName(_ uri: String) -> String {
        uri.hasPrefix("spotify:album:") ? "Album" : "Playlist"
    }

    // MARK: - Name and cover

    /// The name and cover from Spotify's public link preview, the one chat
    /// apps use. No login. Answers for public playlists and albums; 404 for a
    /// private one, which is then added with `fallbackName` and still plays.
    ///
    /// The app's third network call, after the cover and the album/artist
    /// lookup, and like that one it happens only on a tap.
    nonisolated static func preview(for uri: String) async -> (name: String, cover: URL?)? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3,
              var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url",
                                              value: "https://open.spotify.com/\(parts[1])/\(parts[2])")]
        guard let url = components.url,
              let (body, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(body)
    }

    nonisolated static func parse(_ body: Data) -> (name: String, cover: URL?)? {
        struct Embed: Decodable {
            let title: String
            let thumbnail_url: String?
        }
        guard let embed = try? JSONDecoder().decode(Embed.self, from: body),
              !embed.title.isEmpty else { return nil }
        return (embed.title, embed.thumbnail_url.flatMap(URL.init(string:)))
    }

    /// Ephemeral, like `SpotifyLinks`: no cookies and no cache on disk.
    private nonisolated static let session = URLSession(configuration: .ephemeral)
}

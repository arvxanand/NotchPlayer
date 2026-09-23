import AppKit

/// Clicking the title, the artist or the cover opens that thing in Spotify.
///
/// **Spotify hands over a track ID and nothing else.** The notification and
/// the AppleScript dictionary both carry `spotify:track:…`, but the album and
/// the artist are plain text names -- checked against `sdef` on this machine.
/// So the track is exact and free, and the other two need one lookup: the
/// public page `open.spotify.com/track/<id>` names both in its meta tags.
///
/// That lookup is the app's second network call, after the cover. It happens
/// **only on a click**, never in the background, and a failed one falls back to
/// a Spotify search for the name -- a click that lands on search results beats
/// a click that does nothing.
@MainActor
public enum SpotifyLinks {
    /// `save` is the panel's +, which is not a link at all -- see
    /// `SpotifyPlus`. It rides this path so the view needs no second callback.
    public enum Target: Equatable, Sendable { case track, album, artist, save }

    /// Album and artist pages, per track, so a second click costs nothing.
    private static var found: [String: Page] = [:]

    /// **The title opens the album with the song highlighted, not the song.**
    /// Opening `spotify:track:…` *plays* it -- measured: a paused Spotify
    /// started playing -- and clicking a title is not asking for that. An
    /// album or artist URI only navigates (also measured).
    public static func open(_ target: Target, for track: Track) {
        // Read by `tools/hit_probe.sh`: the + and the title both land in
        // Spotify, so only this line says which one was clicked.
        print("link: \(target)")
        if target == .save { return SpotifyPlus.save(track) }
        let fallback = search(fallbackTerm(target, track))
        guard let page = pageURL(for: track.id) else { return openOr(nil, fallback) }
        if let cached = found[track.id] {
            return openOr(cached.link(target, track: track.id), fallback)
        }
        Task {
            let result = await fetch(page)
            if let result { found[track.id] = result }
            openOr(result?.link(target, track: track.id), fallback)
        }
    }

    nonisolated static func fallbackTerm(_ target: Target, _ track: Track) -> String {
        switch target {
        case .track, .save: "\(track.name) \(track.artist)"
        case .album: "\(track.album) \(track.artist)"
        case .artist: track.artist
        }
    }

    private static func openOr(_ link: URL?, _ fallback: URL?) {
        if let url = link ?? fallback { NSWorkspace.shared.open(url) }
    }

    /// Ephemeral: no cookies and no cache on disk, so the lookup leaves no
    /// record of what was playing.
    private static let session = URLSession(configuration: .ephemeral)

    private static func fetch(_ url: URL) async -> Page? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        let page = Page.parse(html)
        return page.album == nil && page.artist == nil ? nil : page
    }

    // MARK: - Pure, so a test can call them

    /// The web page for a track, or nil for anything that has none -- a local
    /// file is `spotify:local:…`, an episode has no album or artist.
    public nonisolated static func pageURL(for id: String) -> URL? {
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track",
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return URL(string: "https://open.spotify.com/track/\(parts[2])")
    }

    /// A search inside Spotify, for when the page did not answer.
    public nonisolated static func search(_ term: String) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "spotify:search:\(encoded)")
    }

    public struct Page: Equatable, Sendable {
        public let album: URL?
        /// The first `music:musician`, which is the primary artist.
        public let artist: URL?

        public func link(_ target: Target, track id: String) -> URL? {
            switch target {
            case .album: album
            case .artist: artist
            case .track, .save: album.flatMap { URL(string: "\($0.absoluteString):highlight:\(id)") }
            }
        }

        /// Reads `<meta name="music:album" content="https://open.spotify.com/album/X">`
        /// and the first `music:musician`, and turns each into a `spotify:` URI
        /// so it opens in the app rather than the browser.
        public nonisolated static func parse(_ html: String) -> Page {
            var album: URL?, artist: URL?
            for tag in html.matches(of: #/<meta\s[^>]*>/#) {
                let text = String(tag.output)
                guard let name = attribute("name", in: text) ?? attribute("property", in: text),
                      let content = attribute("content", in: text) else { continue }
                if name == "music:album", album == nil { album = uri(content, kind: "album") }
                if name == "music:musician", artist == nil { artist = uri(content, kind: "artist") }
            }
            return Page(album: album, artist: artist)
        }

        private nonisolated static func attribute(_ key: String, in tag: String) -> String? {
            guard let range = tag.range(of: " \(key)=\"") else { return nil }
            let rest = tag[range.upperBound...]
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }

        /// `https://open.spotify.com/album/X` to `spotify:album:X`, or nil if
        /// the link is not the kind it claims to be.
        nonisolated static func uri(_ link: String, kind: String) -> URL? {
            guard let url = URL(string: link), url.host == "open.spotify.com" else { return nil }
            let path = url.pathComponents.filter { $0 != "/" }
            guard path.count == 2, path[0] == kind,
                  path[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            return URL(string: "spotify:\(kind):\(path[1])")
        }
    }
}

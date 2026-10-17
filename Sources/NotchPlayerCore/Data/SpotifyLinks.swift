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
/// `save` is the panel's +, which is not a link at all -- see `SpotifyPlus`. It
/// rides this path so the view needs no second callback.
public enum LinkTarget: Equatable, Sendable { case track, album, artist, save }

@MainActor
public enum SpotifyLinks {
    /// Album and artist pages, per track, so a second click costs nothing.
    private static var found: [String: Page] = [:]

    /// **The title opens the album with the song highlighted, not the song.**
    /// Opening `spotify:track:…` *plays* it -- measured: a paused Spotify
    /// started playing -- and clicking a title is not asking for that. An
    /// album or artist URI only navigates (also measured).
    public static func open(_ target: LinkTarget, for track: Track) {
        // Music has no page to lookup; its titles and covers are not links.
        guard track.source == .spotify else { return }
        // Read by `tools/hit_probe.sh`: the + and the title both land in
        // Spotify, so only this line says which one was clicked.
        print("link: \(target)")
        if target == .save { return SpotifyPlus.save(track) }
        let fallback = search(fallbackTerm(target, track))
        if let cached = found[track.id] {
            return openOr(cached.link(target, track: track.id), fallback)
        }
        Task { openOr(await page(track.id)?.link(target, track: track.id), fallback) }
    }

    /// The public page for `spotify:track:…`, read once per session. Also the
    /// queue page's names and covers (`QueueView`), asked only while it shows.
    /// A page already fetched this session, without asking for it.
    public static func cachedPage(_ id: String) -> Page? { found[id] }

    public static func page(_ id: String) async -> Page? {
        if let cached = found[id] { return cached }
        guard let url = pageURL(for: id), let page = await fetch(url) else { return nil }
        found[id] = page
        return page
    }

    nonisolated static func fallbackTerm(_ target: LinkTarget, _ track: Track) -> String {
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
        return page.album == nil && page.artist == nil && page.title == nil ? nil : page
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
        /// The song's name, every artist's name ("Flo Rida, Sia"), and its
        /// cover, from the `og:` tags.
        public var title: String? = nil
        public var byline: String? = nil
        public var cover: URL? = nil

        public init(album: URL?, artist: URL?, title: String? = nil, byline: String? = nil, cover: URL? = nil) {
            self.album = album; self.artist = artist
            self.title = title; self.byline = byline; self.cover = cover
        }

        public func link(_ target: LinkTarget, track id: String) -> URL? {
            switch target {
            case .album: album
            case .artist: artist
            case .track, .save: album.flatMap { URL(string: "\($0.absoluteString):highlight:\(id)") }
            }
        }

        /// Reads `<meta name="music:album" content="https://open.spotify.com/album/X">`
        /// and the first `music:musician`, and turns each into a `spotify:` URI
        /// so it opens in the app rather than the browser. `og:description` is
        /// "Artists · Title · Song · Year"; the byline is its first part.
        public nonisolated static func parse(_ html: String) -> Page {
            var page = Page(album: nil, artist: nil)
            var album: URL?, artist: URL?
            for tag in html.matches(of: #/<meta\s[^>]*>/#) {
                let text = String(tag.output)
                guard let name = attribute("name", in: text) ?? attribute("property", in: text),
                      let content = attribute("content", in: text) else { continue }
                switch name {
                case "music:album" where album == nil: album = uri(content, kind: "album")
                case "music:musician" where artist == nil: artist = uri(content, kind: "artist")
                case "og:title": page.title = unescape(content)
                case "og:description":
                    page.byline = content.components(separatedBy: " · ").first.map(unescape)
                case "og:image": page.cover = URL(string: content)
                default: break
                }
            }
            return Page(album: album, artist: artist, title: page.title, byline: page.byline, cover: page.cover)
        }

        /// The page's HTML escapes: `&amp;`, `&gt;`, `&#x27;`, `&#39;`.
        nonisolated static func unescape(_ text: String) -> String {
            var out = text
            for (code, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'")] {
                out = out.replacingOccurrences(of: code, with: character)
            }
            return out.replacingOccurrences(of: "&amp;", with: "&")
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

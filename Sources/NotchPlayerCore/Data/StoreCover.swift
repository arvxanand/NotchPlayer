import Foundation

/// An Apple Music song's cover, from Apple's public iTunes Search.
///
/// **Music won't give it out.** `raw data of artwork 1` answers -1728 for a
/// song streamed from Apple Music, or added to the library from it: Music
/// fetches that cover itself and AppleScript cannot reach it (Doug's
/// AppleScripts, "Yes, There is Still an Artwork Issue"; Apple's forums). It
/// only works for songs whose own file carries a cover. So when Music has
/// nothing, the song is looked up by artist and title, no account needed.
///
/// The app's network calls are listed in the README; this is one of them,
/// made once per song per launch, and only for Apple Music songs without a
/// cover of their own.
enum StoreCover {
    /// The cover's address, at 300px like Spotify's (`ArtworkCache`), or nil.
    static func url(for track: Track) async -> URL? {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.name)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url,
              let (body, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return best(in: body, for: track)
    }

    /// The same song on the same album first, then the same title by the same
    /// artist, then nothing: a cover from the wrong record is worse than the
    /// Music mark it replaces.
    static func best(in body: Data, for track: Track) -> URL? {
        struct Reply: Decodable { let results: [Result] }
        struct Result: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let artworkUrl100: String?
        }
        guard let results = try? JSONDecoder().decode(Reply.self, from: body).results else { return nil }
        func same(_ a: String?, _ b: String) -> Bool {
            a?.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let byArtist = results.filter { same($0.artistName, track.artist) }
        let pick = byArtist.first { same($0.collectionName, track.album) && same($0.trackName, track.name) }
            ?? byArtist.first { same($0.collectionName, track.album) }
            ?? byArtist.first { same($0.trackName, track.name) }
        guard let small = pick?.artworkUrl100, small.hasSuffix("100x100bb.jpg") else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100bb.jpg", with: "300x300bb.jpg"))
    }

    /// Ephemeral, like `SpotifyLinks`: no cookies and no cache on disk; the
    /// cover itself is cached by `ArtworkCache`.
    private static let session = URLSession(configuration: .ephemeral)
}

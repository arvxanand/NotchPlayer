import Foundation

/// A song's name and cover from Spotify's public link preview, the one chat
/// apps use. No login.
///
/// The queue page's lookup, asked only while that page is showing, so like
/// `SpotifyLinks` it follows something the user did. Kept in memory for the
/// session; nothing is written to disk.
@MainActor
public enum SpotifyPreview {
    public struct Song: Equatable, Sendable {
        public let name: String
        public let cover: URL?
    }

    private static var found: [String: Song] = [:]

    /// Nil when Spotify does not answer (an episode, a song gone from the
    /// catalogue, no network).
    public static func song(_ id: String) async -> Song? {
        if let known = found[id] { return known }
        guard let url = url(for: id), let song = await fetch(url) else { return nil }
        found[id] = song
        return song
    }

    nonisolated static func url(for id: String) -> URL? {
        // Base62 from `SpotifyQueue`, checked again since it goes into a URL.
        guard id.count == 22, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(id)")]
        return components?.url
    }

    nonisolated static func parse(_ body: Data) -> Song? {
        struct Embed: Decodable {
            let title: String
            let thumbnail_url: String?
        }
        guard let embed = try? JSONDecoder().decode(Embed.self, from: body),
              !embed.title.isEmpty else { return nil }
        return Song(name: embed.title, cover: embed.thumbnail_url.flatMap(URL.init(string:)))
    }

    private nonisolated static func fetch(_ url: URL) async -> Song? {
        guard let (body, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 4)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(body)
    }

    /// Ephemeral, like `SpotifyLinks`: no cookies and no cache on disk.
    private nonisolated static let session = URLSession(configuration: .ephemeral)
}

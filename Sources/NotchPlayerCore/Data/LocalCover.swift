import AVFoundation
import Foundation

/// The cover of a Spotify **local file**, read from the file itself.
///
/// **Spotify hands over no artwork for `spotify:local:…` songs** -- `artwork
/// url` is "missing value" (measured 25 Sep 2026) -- and the id carries no
/// path, only artist, album, title and seconds. Spotify shows the cover
/// embedded in the file, and so can this: its own local-file index,
/// `Users/<id>-user/local-files.bnk`, pairs each title and artist with the
/// file's full path.
///
/// **That index is not a public format.** Measured on Spotify 1.3.0: fields
/// are length-prefixed strings, title then artist then album then path. If
/// Spotify changes it, nothing matches and the song shows the Spotify mark,
/// as it did before this existed.
///
/// Files in the folders macOS guards (Downloads, Documents, Desktop, iCloud
/// Drive, external drives) are never opened, so this can't cause a prompt:
/// those songs keep the mark (the owner's call, 25 Sep 2026).
public enum LocalCover {
    public nonisolated static func isLocal(_ id: String) -> Bool { id.hasPrefix("spotify:local:") }

    /// The song's file, if Spotify's index knows it and it can be read quietly.
    public nonisolated static func file(for track: Track) -> URL? {
        guard isLocal(track.id) else { return nil }
        let files = FileManager.default
        let users = files.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Spotify/Users")
        let accounts = (try? files.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        var skipped = false
        for account in accounts {
            guard let index = try? Data(contentsOf: account.appendingPathComponent("local-files.bnk"))
            else { continue }
            for path in paths(in: index, title: track.name, artist: track.artist)
            where files.fileExists(atPath: path) {
                guard readable(path) else { skipped = true; continue }
                return URL(fileURLWithPath: path)
            }
        }
        // No song names in the log: it goes into bug reports.
        print("local cover: " + (skipped ? "file is in a folder macOS guards, skipped"
                                         : "not in Spotify's local-file index"))
        return nil
    }

    /// The picture embedded in a song file, or nil.
    public nonisolated static func artwork(in file: URL) async -> Data? {
        guard let items = try? await AVURLAsset(url: file).load(.commonMetadata),
              let art = AVMetadataItem.metadataItems(from: items,
                                                     filteredByIdentifier: .commonIdentifierArtwork).first
        else { return nil }
        return try? await art.load(.dataValue)
    }

    // MARK: - Pure, so a test can call them

    /// Every path the index gives for this title and artist, in order. More
    /// than one when the index still lists a deleted copy, which it does:
    /// three of the owner's four entries pointed at files that were gone.
    ///
    /// The title and the artist must each be a whole field (its length byte
    /// right before it), so "Texas" can't match inside "Choosin' Texas", and
    /// the artist must follow the title directly. The path is the next string
    /// starting with "/", up to the first control byte, which no path contains.
    /// ponytail: title and artist only, not album. Two files sharing both give
    /// the first that exists.
    public nonisolated static func paths(in index: Data, title: String, artist: String) -> [String] {
        let bytes = [UInt8](index), title = Array(title.utf8), artist = Array(artist.utf8)
        guard !title.isEmpty, !artist.isEmpty else { return [] }
        var found: [String] = [], from = 0
        while let t = field(title, in: bytes, from: from) {
            from = t + 1
            let afterTitle = t + title.count
            guard let a = field(artist, in: bytes, from: afterTitle), a - afterTitle <= 4,
                  let slash = bytes[(a + artist.count)...].firstIndex(of: UInt8(ascii: "/"))
            else { continue }
            let end: Int = bytes[slash...].firstIndex(where: { $0 < 0x20 }) ?? bytes.count
            if let path = String(bytes: bytes[slash..<end], encoding: .utf8) { found.append(path) }
        }
        return found
    }

    /// Where `needle` starts as a whole length-prefixed field, at or after `from`.
    /// A length of 128 or more takes more than one byte, whose encoding hasn't
    /// been seen, so a long field is matched without the check.
    private nonisolated static func field(_ needle: [UInt8], in bytes: [UInt8], from: Int) -> Int? {
        var i = from
        while i + needle.count <= bytes.count {
            if bytes[i] == needle[0], Array(bytes[i..<i + needle.count]) == needle,
               needle.count >= 128 || (i > 0 && Int(bytes[i - 1]) == needle.count) {
                return i
            }
            i += 1
        }
        return nil
    }

    /// False for the folders macOS asks about before an app may read them.
    public nonisolated static func readable(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let guarded = ["Downloads", "Documents", "Desktop", "Library/Mobile Documents"]
            .map { home + "/" + $0 + "/" } + ["/Volumes/"]
        return !guarded.contains { path.hasPrefix($0) }
    }
}

import SwiftUI

/// The open panel's third page, Spotify only: the next ten songs, the first
/// one large, the rest in a list that scrolls.
///
/// Look, don't touch. Anything that tells Spotify to play a particular song
/// brings it forward (TRAPS #75), so tapping does nothing; queueing and
/// removing stay in Spotify.
///
/// Same frame and camera band as `StatsView`. The order comes from Spotify's
/// restore file (`SpotifyQueue`), names and covers from each song's public
/// page (`SpotifyLinks.page`), both asked only while this page shows. A
/// sideways swipe still flips pages; only an up-and-down scroll moves the list.
public struct QueueView: View {
    public struct Song: Equatable, Sendable {
        public let name: String
        public let artist: String
        public let cover: URL?

        public init(name: String, artist: String, cover: URL?) {
            self.name = name; self.artist = artist; self.cover = cover
        }
    }

    public enum Content: Equatable, Sendable {
        case loading
        /// The file is missing or not what it was (TRAPS #78).
        case unreadable
        /// Nil while a song's page is on its way, or if it never answers.
        case songs([Song?])
    }

    let geometry: NotchGeometry
    let track: Track
    let showing: Bool
    /// Previews: shown as is, nothing read.
    let fixed: Content?

    @State private var content = Content.loading
    @ObservedObject private var memory = ArtMemory.shared
    @AppStorage(Accent.enabledKey) private var coverAccent = true

    public init(geometry: NotchGeometry, track: Track, showing: Bool, fixed: Content? = nil) {
        self.geometry = geometry; self.track = track; self.showing = showing; self.fixed = fixed
    }

    /// The playing cover's colour, as on the stats page.
    private var accent: Color {
        memory.accent(for: coverAccent ? track.artworkURL : nil).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
            ?? Palette.primary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            list(fixed ?? content)
        }
        .padding(.horizontal, PanelView.inset)
        .padding(.bottom, PanelView.bottomGap)
        .frame(width: geometry.openWidth, height: geometry.openHeight, alignment: .top)
        .task(id: fixed == nil && showing ? track.id : nil) {
            guard fixed == nil, showing else { return }
            await load()
        }
    }

    @ViewBuilder
    private func list(_ content: Content) -> some View {
        switch content {
        case .loading:
            header
        case .unreadable:
            header
            note("Can't read Spotify's queue right now.")
        case .songs(let songs) where songs.isEmpty:
            header
            note("Nothing after this song")
        case .songs(let songs):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        row(song, first: index == 0)
                    }
                }
                .padding(.bottom, Self.endGap)
            }
        }
    }

    private var header: some View {
        Text("Up next")
            .font(Type.label(11, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .frame(height: Self.headerHeight)
            .padding(.top, StatsView.topGap)
    }

    private func row(_ song: Song?, first: Bool) -> some View {
        HStack(spacing: first ? 10 : 8) {
            let side = first ? Self.firstCover : Self.cover, corner: CGFloat = first ? 6 : 4
            if let song {
                ArtworkView(url: song.cover, side: side, corner: corner)
            } else {
                // On its way: a quiet slot, not the Spotify mark, which reads
                // as a song with no cover.
                RoundedRectangle(cornerRadius: corner).fill(Palette.wash).frame(width: side, height: side)
            }
            VStack(alignment: .leading, spacing: 1) {
                if first {
                    Text("Next")
                        .font(Type.label(11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text(song?.name ?? " ")
                    .font(Type.label(first ? 13 : 12, weight: first ? .semibold : .medium))
                    .foregroundStyle(Palette.primary)
                Text(song?.artist ?? " ")
                    .font(Type.label(11))
                    .foregroundStyle(Palette.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: first ? Self.firstHeight : Self.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Type.label(12))
            .foregroundStyle(Palette.secondary)
            .frame(height: StatsView.lineHeight)
    }

    /// **Shown at once, then corrected.** Spotify rewrites the file a moment
    /// after the song changes, so a read right then is the list before: the
    /// song now playing first. That list minus it is almost always the right
    /// answer, so it goes up straight away and the file is watched until
    /// Spotify saves (up to `staleWait`) -- not a fixed second's wait with an
    /// empty page. Songs already looked up this session, and local files,
    /// show without waiting; only new ones ask their page (~300KB and about
    /// a second each, all at once), still only while this page shows.
    private func load() async {
        let playing = LocalCover.isLocal(track.id) ? track.id : track.id.split(separator: ":").last.map(String.init)
        let saved = SpotifyQueue.saved()
        guard let state = SpotifyQueue.read() else { content = .unreadable; return }
        var ids = Self.upNext(state, playing: playing)
        var songs = ids.map(Self.known)
        content = .songs(songs)
        if state.next(1).first == playing {
            let deadline = Date().addingTimeInterval(Self.staleWait)
            while SpotifyQueue.saved() == saved, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            if let fresh = SpotifyQueue.read() {
                ids = Self.upNext(fresh, playing: playing)
                songs = ids.map(Self.known)
                content = .songs(songs)
            }
        }
        await withTaskGroup(of: (Int, Song?).self) { group in
            for (index, id) in ids.enumerated() where songs[index] == nil {
                group.addTask {
                    let page = await SpotifyLinks.page("spotify:track:\(id)")
                    return (index, page?.title.map { Song(name: $0, artist: page?.byline ?? "", cover: page?.cover) })
                }
            }
            for await (index, song) in group where !Task.isCancelled {
                songs[index] = song
                content = .songs(songs)
            }
        }
    }

    /// The next songs, without the one playing if a stale file still lists it.
    nonisolated static func upNext(_ state: SpotifyQueue.State, playing: String?) -> [String] {
        let all = state.next(count + 1)
        return Array((all.first == playing ? all.dropFirst() : all[...]).prefix(count))
    }

    /// A song that needs no lookup: a local file, or a page fetched before.
    private static func known(_ id: String) -> Song? {
        if LocalCover.isLocal(id) { return local(id) }
        return SpotifyLinks.cachedPage("spotify:track:\(id)").flatMap { page in
            page.title.map { Song(name: $0, artist: page.byline ?? "", cover: page.cover) }
        }
    }

    /// A local file has no public page; its URI is the page.
    /// `spotify:local:artist:album:title:seconds`, `+` for a space, the rest
    /// percent-encoded -- so a `:` in a name arrives as `%3A` and the split
    /// is safe. The cover is the file's own, as for the playing song.
    nonisolated static func local(_ uri: String) -> Song? {
        guard LocalCover.isLocal(uri) else { return nil }
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
        }
        guard parts.count == 6 else { return nil }
        let track = Track(id: uri, name: parts[4], artist: parts[2], album: parts[3],
                          duration: Double(parts[5]) ?? 0, hasArtwork: false)
        return Song(name: track.name, artist: track.artist, cover: LocalCover.file(for: track))
    }

    // MARK: - Metrics

    nonisolated static let count = 10
    /// How long to wait for Spotify to save after a song change. Its saves
    /// come within a second or two; past this the moved-on list stands.
    static let staleWait: TimeInterval = 5
    static let headerHeight: CGFloat = 18
    static let firstCover: CGFloat = 40
    static let firstHeight: CGFloat = 50
    static let cover: CGFloat = 24
    static let rowHeight: CGFloat = 32
    /// Room under the last row, so it scrolls clear of the page dots.
    static let endGap: CGFloat = 8
}

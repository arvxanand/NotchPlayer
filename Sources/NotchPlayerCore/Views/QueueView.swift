import SwiftUI

/// The open panel's third page, Spotify only: the next songs, as covers.
///
/// Look, don't touch. Anything that tells Spotify to play a particular song
/// brings it forward (TRAPS #75), so tapping does nothing; queueing and
/// removing stay in Spotify.
///
/// Same frame and camera band as `StatsView`. The order comes from Spotify's
/// restore file (`SpotifyQueue`), names and covers from its public preview
/// (`SpotifyPreview`), both asked only while this page shows.
public struct QueueView: View {
    public enum Content: Equatable, Sendable {
        case loading
        /// The file is missing or not what it was (TRAPS #78).
        case unreadable
        /// Nil where Spotify's preview did not answer.
        case songs([SpotifyPreview.Song?])
    }

    let geometry: NotchGeometry
    let track: Track
    let showing: Bool
    /// Previews: shown as is, nothing read.
    let fixed: Content?

    @State private var content = Content.loading

    public init(geometry: NotchGeometry, track: Track, showing: Bool, fixed: Content? = nil) {
        self.geometry = geometry; self.track = track; self.showing = showing; self.fixed = fixed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            Text("Up next")
                .font(Type.label(11, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(height: StatsView.tabHeight)
                .padding(.top, StatsView.topGap)
            row(fixed ?? content)
                .padding(.top, StatsView.rowGap)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelView.inset)
        .padding(.bottom, PanelView.bottomGap)
        .frame(width: geometry.openWidth, height: geometry.openHeight)
        .task(id: fixed == nil && showing ? track.id : nil) {
            guard fixed == nil, showing else { return }
            await load()
        }
    }

    @ViewBuilder
    private func row(_ content: Content) -> some View {
        switch content {
        case .loading:
            Color.clear.frame(height: side + Self.nameGap + Self.nameHeight)
        case .unreadable:
            note("Can't read Spotify's queue right now.")
        case .songs(let songs) where songs.isEmpty:
            note("Nothing after this song")
        case .songs(let songs):
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(songs.enumerated()), id: \.offset) { _, song in
                    VStack(alignment: .leading, spacing: Self.nameGap) {
                        ArtworkView(url: song?.cover, side: side, corner: Self.corner)
                        Text(song?.name ?? " ")
                            .font(Type.label(11))
                            .foregroundStyle(Palette.primary)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: side, height: Self.nameHeight, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Type.label(12))
            .foregroundStyle(Palette.secondary)
            .frame(height: StatsView.lineHeight)
    }

    /// Spotify rewrites the file as the song changes, so a read right then
    /// can still be the one before: the song now playing listed as next.
    /// One more read a second later settles it.
    private func load() async {
        let playing = track.id.split(separator: ":").last.map(String.init)
        var state = SpotifyQueue.read()
        if let first = state?.next(1).first, first == playing {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            state = SpotifyQueue.read()
        }
        guard let state else { content = .unreadable; return }
        var songs: [SpotifyPreview.Song?] = []
        for id in state.next(Self.count) {
            songs.append(await SpotifyPreview.song(id))
            guard !Task.isCancelled else { return }
        }
        content = .songs(songs)
    }

    // MARK: - Metrics

    static let count = 5
    static let gap: CGFloat = 10
    static let corner: CGFloat = 6
    static let nameGap: CGFloat = 4
    static let nameHeight: CGFloat = 14

    /// Five covers across the panel, no bigger than the player's.
    private var side: CGFloat {
        let across = (geometry.openWidth - 2 * PanelView.inset - CGFloat(Self.count - 1) * Self.gap) / CGFloat(Self.count)
        return min(across.rounded(.down), PanelView.artSide)
    }
}

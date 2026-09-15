import SwiftUI

/// What the menu-bar item opens.
///
/// **A panel, not a menu.** The first version of this was an `NSMenu` with
/// three lines of text, which is the right answer for a utility that has
/// nothing to show -- and the wrong one here, because this app's whole subject
/// is an album cover. A menu of words about a picture is a worse menu.
///
/// Black, like the notch panel and like matchnotch's popover: the surface is
/// the app's identity, and a vibrancy-backed sheet with system text would look
/// like a different program's settings window.
public struct MenuPanel: View {
    let track: Track?
    let playing: Bool
    let subtitle: String
    let hidden: Bool
    let toggleHidden: () -> Void
    let quit: () -> Void

    public init(track: Track?, playing: Bool, subtitle: String, hidden: Bool,
                toggleHidden: @escaping () -> Void, quit: @escaping () -> Void) {
        self.track = track; self.playing = playing; self.subtitle = subtitle
        self.hidden = hidden; self.toggleHidden = toggleHidden; self.quit = quit
    }

    public static let width: CGFloat = 268
    /// Fixed, so the window cannot resize under the pointer when a track
    /// changes while the panel is open. matchnotch's popover states its height
    /// for the same reason.
    public static let height: CGFloat = 162
    static let margin: CGFloat = 14
    static let coverSide: CGFloat = 56

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            divider
            Row(title: hidden ? "Show in the Notch" : "Hide from the Notch",
                symbol: hidden ? "eye" : "eye.slash", action: toggleHidden)
            divider
            Row(title: "Quit SpotifyNotch", symbol: "power", action: quit)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(Palette.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // A 56pt black square would read as a hole in the panel while the
            // cover is still downloading, so the slot is washed rather than
            // black here. In the peek it stays black -- see `ArtworkView.fill`.
            ArtworkView(url: track?.artworkURL, side: Self.coverSide, corner: 8,
                        fill: Palette.wash)
            VStack(alignment: .leading, spacing: 3) {
                Text(track?.name ?? "Nothing playing")
                    .font(Type.label(13, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1).truncationMode(.tail)
                if let artist = track?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(Type.label(11))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                state
            }
            Spacer(minLength: 0)
        }
        .padding(Self.margin)
    }

    /// The one coloured thing in the panel, and only while the music is
    /// actually running -- the same rule the waveform follows. A dot that is
    /// green whatever is happening stops meaning anything.
    private var state: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(playing ? Palette.spotify : Palette.track)
                .frame(width: 6, height: 6)
            Text(subtitle)
                .font(Type.label(11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 0.5)
    }

    /// Dim until pointed at, like every row in matchnotch's popover. Quit is
    /// the one destructive thing here and a red row would be the loudest pixel
    /// in a window whose job is to be glanced at.
    private struct Row: View {
        let title: String
        let symbol: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(title).font(Type.label(11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
            .padding(.horizontal, MenuPanel.margin)
            .frame(height: 38)
            .background(hovering ? Palette.wash : .clear)
            // Last, after every sizing modifier, or the live area is whatever
            // the content happens to cover -- TRAPS #21, which every hit
            // target in matchnotch had backwards.
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
        }
    }
}

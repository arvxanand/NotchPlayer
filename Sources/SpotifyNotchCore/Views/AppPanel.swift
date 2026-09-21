import AppKit
import SwiftUI

/// The expanded panel for something that is not Spotify.
///
/// **It shows what it knows and stops.** An app icon, a name, and three
/// buttons that send media keys. No progress bar, because there is no
/// position to put in it -- macOS gated the API that would have supplied one
/// (`docs/TRAPS.md`), and a bar that never moves is worse than no bar. No
/// artist line, no duration, no invented "Now playing".
///
/// Same metrics as `PanelView` -- `inset`, `artSide`, `gap`, `topGap` -- so
/// the two panels are the same shape and the footprint check holds for both.
public struct AppPanel: View {
    let geometry: NotchGeometry
    let name: String
    let icon: NSImage?
    let send: (MediaKeys.Key) -> Void

    public init(geometry: NotchGeometry, name: String, icon: NSImage?,
                send: @escaping (MediaKeys.Key) -> Void = { _ in }) {
        self.geometry = geometry; self.name = name; self.icon = icon; self.send = send
    }

    /// One intent, one key. Its own function so the mapping can be called by
    /// a test -- three constants that look right whichever way round they are.
    public static func key(for transport: Transport) -> MediaKeys.Key {
        switch transport {
        case .previous: return .previous
        case .playpause: return .playpause
        case .next: return .next
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: PanelView.gap) {
                SourceIcon(image: icon, side: PanelView.artSide, corner: PanelView.artCorner)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(Type.title())
                        .foregroundStyle(Palette.primary)
                        .lineLimit(1).truncationMode(.tail)
                    Text("Playing audio")
                        .font(Type.label(13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(height: PanelView.artSide, alignment: .top)

            Spacer(minLength: 0)

            // The same row and the same 44pt targets as Spotify's panel, on a
            // different wire: these become system media keys rather than
            // Apple Events, because there is no app-specific way to talk to
            // "whatever is playing".
            TransportRow(playing: true) { send(Self.key(for: $0)) }
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PanelView.inset)
        .padding(.top, geometry.notchExclusionTop + PanelView.topGap)
        .padding(.bottom, PanelView.bottomGap)
        .frame(width: geometry.collapsedWidth, height: NotchGeometry.panelHeight,
               alignment: .top)
    }
}

/// An app's own icon, in the slot the album cover takes.
///
/// Separate from `ArtworkView`, which is about fetching and caching a URL.
/// This one is handed an `NSImage` that already exists -- the same one the
/// Dock draws -- so there is nothing to load and nothing to cache.
public struct SourceIcon: View {
    let image: NSImage?
    let side: CGFloat
    let corner: CGFloat

    public init(image: NSImage?, side: CGFloat, corner: CGFloat) {
        self.image = image; self.side = side; self.corner = corner
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Palette.wash)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        // App icons ship with their own transparent margin, so
                        // they are drawn slightly large to sit optically the
                        // same size as an album cover, which has none.
                        .padding(-side * 0.06)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

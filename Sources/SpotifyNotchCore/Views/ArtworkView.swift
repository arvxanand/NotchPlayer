import SwiftUI

/// The album cover, or the Spotify mark where there isn't one.
///
/// **Three cases, not two**, which is the whole subtlety:
///
/// | | drawn here | peek's standalone mark |
/// |---|---|---|
/// | cover loaded | the cover | shown |
/// | cover pending | nothing | shown |
/// | no artwork URL at all | the mark | hidden by `PeekView` |
///
/// Pending draws *nothing* rather than the mark. Drawing the mark there would
/// put two Spotify logos side by side for however long the download takes --
/// and on a cold cache for a podcast it would be two permanently. Found by
/// capturing the `noart` state and looking at it; the code read fine.
///
/// An empty square is invisible against a black shell, so nothing shifts when
/// the cover lands -- which is the placeholder matchnotch TRAPS #24 says to
/// plan for rather than discover.
public struct ArtworkView: View {
    let url: URL?
    let side: CGFloat
    let corner: CGFloat

    @ObservedObject private var memory = ArtMemory.shared

    /// The slot behind the cover. Black in the notch, where the shell is
    /// black and an empty square must be invisible; `Palette.wash` in the menu
    /// panel, where a 56pt black square reads as a hole rather than as a frame
    /// waiting for art.
    let fill: Color

    public init(url: URL?, side: CGFloat, corner: CGFloat, fill: Color = Palette.background) {
        self.url = url; self.side = side; self.corner = corner; self.fill = fill
    }

    private var image: NSImage? { memory.image(for: url) }

    /// Whether the mark stands in for the cover. See
    /// `PeekView.showsStandaloneMark` for why this is a function and not an
    /// `if` in a view body.
    ///
    /// **Pending is not the same as absent.** A cover still downloading draws
    /// nothing -- an empty square, invisible against the black shell, so
    /// nothing shifts when it lands. Drawing the mark there would put two
    /// logos side by side for the length of the download.
    public static func showsPlaceholderMark(url: URL?, hasImage: Bool) -> Bool {
        !hasImage && url == nil
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if Self.showsPlaceholderMark(url: url, hasImage: false) {
                    SpotifyMark().frame(width: side * 0.62, height: side * 0.62)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Scoped with `.animation(_:value:)` rather than `withAnimation`,
            // which writes into the transaction dispatched from the root and
            // re-animates things hundreds of points away that nobody touched
            // (matchnotch TRAPS #52).
            .animation(.easeOut(duration: 0.18), value: image != nil)
            // `.task(id:)` so a track change re-runs it. Loading is
            // idempotent and keyed by URL, so this is safe to call often.
            .task(id: url) { memory.load(url) }
    }
}

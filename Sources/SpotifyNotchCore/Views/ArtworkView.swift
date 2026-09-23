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

    /// What is drawn: the current cover on top, and while a change is fading,
    /// the one before it underneath.
    ///
    /// **A cross-dissolve, not a cross-fade.** The old cover stays fully
    /// opaque underneath while the new one fades in over it, then is dropped.
    /// Fading both at once dips through the black slot at the midpoint -- two
    /// half-transparent covers -- which is matchnotch TRAPS #22 in picture form.
    /// And the old cover stays up while the new one downloads, rather than
    /// the slot going black for the length of the fetch.
    @State private var layers: [Layer] = []
    private struct Layer: Identifiable {
        let id: URL
        let image: NSImage
    }
    static let fade = Animation.easeOut(duration: 0.35 * Motion.slow)

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
                ZStack {
                    ForEach(layers) { layer in
                        Image(nsImage: layer.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // Fades in; leaves instantly, because by then the
                            // layer above covers it completely.
                            .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    }
                }
                if layers.isEmpty, Self.showsPlaceholderMark(url: url, hasImage: false) {
                    SpotifyMark().frame(width: side * 0.62, height: side * 0.62)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Scoped with `.animation(_:value:)` rather than `withAnimation`,
            // which writes into the transaction dispatched from the root and
            // re-animates things hundreds of points away that nobody touched
            // (matchnotch TRAPS #52).
            .animation(Self.fade, value: layers.last?.id)
            // `.task(id:)` so a track change re-runs it. Loading is
            // idempotent and keyed by URL, so this is safe to call often.
            .task(id: url) { memory.load(url) }
            // **The first draw never animates** (matchnotch's rule for its
            // score animations): a panel that appears shows its cover, it
            // does not fade one in.
            .onAppear { sync(animated: false) }
            .onChange(of: url) { sync(animated: true) }
            .onChange(of: image) { sync(animated: true) }
    }

    /// What a change of URL or image does to the layers. Pure, so the rules
    /// are asserted rather than restated (`ArtworkTests`).
    enum Change: Equatable { case keep, clear, show, dissolve }
    static func change(showing: URL?, url: URL?, ready: Bool, appearing: Bool) -> Change {
        guard let url else { return .clear }
        // Still downloading, or already on screen: leave what is showing.
        guard ready, showing != url else { return .keep }
        return appearing ? .show : .dissolve
    }

    private func sync(animated: Bool) {
        switch Self.change(showing: layers.last?.id, url: url, ready: image != nil,
                           appearing: !animated) {
        case .keep: return
        case .clear: layers = []
        case .show:
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { layers = [Layer(id: url!, image: image!)] }
        case .dissolve: dissolve(to: Layer(id: url!, image: image!))
        }
    }

    private func dissolve(to layer: Layer) {
        let url = layer.id
        layers.append(layer)
        // Drop what is underneath once the new cover has fully arrived.
        Task {
            try? await Task.sleep(for: .seconds(0.4 * Motion.slow))
            if layers.last?.id == url { layers.removeFirst(layers.count - 1) }
        }
    }
}

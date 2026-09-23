import SwiftUI

/// The collapsed peek: album art and the Spotify mark in the left wing,
/// waveform in the right, and **nothing at all** across the cutout.
///
/// One black shape spanning all three, not two separate wings. That is what
/// makes it read as a widened notch rather than as two rectangles either side
/// of the camera -- and it is also what lets the footprint check assert the
/// housing band is unlit, since there is something of ours there to be black.
public struct PeekView: View {
    let geometry: NotchGeometry
    let track: Track
    let playing: Bool
    /// Fixed bar values for a reproducible capture; nil animates.
    let holdBands: [Float]?
    /// False when nothing is known about playback. A row of flat bars would
    /// claim the track is merely paused, which is a different answer.
    let showsWaveform: Bool

    public init(geometry: NotchGeometry, track: Track, playing: Bool,
                holdBands: [Float]? = nil, showsWaveform: Bool = true) {
        self.geometry = geometry; self.track = track
        self.playing = playing; self.holdBands = holdBands
        self.showsWaveform = showsWaveform
    }

    /// Stands in for a track we cannot read. No artwork URL, so the cover slot
    /// draws the mark and the standalone mark stays hidden -- the one-mark
    /// rule holds here too.
    public static let unknownTrack = Track(id: "", name: "", artist: "", album: "",
                                           duration: 0, hasArtwork: false)

    public var body: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: NotchGeometry.collapsedSideWidth, alignment: .trailing)
            // The cutout. Nothing may be drawn here, ever -- it is behind the
            // camera housing, which is physical.
            Color.clear.frame(width: geometry.notchWidth)
            rightWing.frame(width: NotchGeometry.collapsedSideWidth, alignment: .leading)
        }
        .frame(width: geometry.collapsedWidth, height: geometry.collapsedHeight)
    }

    private var leftWing: some View {
        HStack(spacing: Self.markGap) {
            // Outboard of the art, so the art is what sits against the cutout.
            // The cover is the identity; the mark only says which app this is.
            //
            // **Hidden when there is no cover**, because then the mark is what
            // `ArtworkView` draws in the square and two of them side by side
            // read as a rendering bug. The mark appears exactly once, always.
            if Self.showsStandaloneMark(artworkURL: track.artworkURL) {
                SpotifyMark().frame(width: Self.markSide, height: Self.markSide)
            }
            ArtworkView(url: track.artworkURL, side: Self.artSide, corner: Self.artCorner)
        }
        .padding(.trailing, Self.cutoutInset)
    }

    private var rightWing: some View {
        // Settled flat when paused: a row of dots reads as stopped without
        // needing a second glyph to say so.
        //
        // **The else branch is not optional.** `Group { if x { View() } }` with
        // `x` false produces an `EmptyView`, which occupies no space at all --
        // and a `.frame(width:)` on nothing is still nothing. The HStack then
        // measured 280pt inside its 352pt frame and SwiftUI re-centred the
        // lot, sliding the left wing 36pt right, straight under the camera
        // housing. Nothing errored; the peek simply became invisible on real
        // hardware. `tools/check_notch.sh` is what noticed.
        Group {
            if showsWaveform {
                WaveformView(hold: playing ? holdBands : Bands.silent)
            } else {
                Color.clear.frame(width: WaveformView.width, height: 1)
            }
        }
        .padding(.leading, Self.cutoutInset)
    }

    // MARK: - Metrics

    /// The cover, and the dominant element in the strip.
    ///
    /// 25 in a 37pt strip leaves exactly 6pt above and below. Chosen by
    /// rendering 24 and 26 against two alignments and looking at all four:
    /// 24 left the strip looking underfilled, 26 was tight against a shell
    /// whose bottom corners already curve.
    public static let artSide: CGFloat = 25
    /// 5 on 25 is a fifth. At 6 on 24 it read as an iOS app icon rather than
    /// a record sleeve -- visible in the comparison, invisible in the number.
    public static let artCorner: CGFloat = 5
    public static let markSide: CGFloat = 12
    public static let markGap: CGFloat = 7
    /// How far the innermost content sits from the cutout's edge.
    public static let cutoutInset: CGFloat = 8
    // MARK: - The one-mark rule

    /// Whether the small mark outboard of the cover is drawn.
    ///
    /// Lifted out of the view body so it can be *called* by a test rather than
    /// restated in one. A test that re-declares a rule it cannot reach stays
    /// green through any change to the real code, and the belief that it
    /// covers something is what does the damage (matchnotch TRAPS #82).
    ///
    /// Paired with `ArtworkView.showsPlaceholderMark` by
    /// `PeekTests.testExactlyOneSpotifyMarkIsEverDrawn` -- the invariant is
    /// that across every combination of "has a URL" and "image decoded yet",
    /// exactly one of the two is true. Two marks side by side read as a
    /// rendering bug, and none reads as an unbranded black box.
    public static func showsStandaloneMark(artworkURL: URL?) -> Bool {
        artworkURL != nil
    }

    /// How much a wing needs for its content, the wider of the two winning --
    /// the wings are equal so the shape stays centred on the cutout.
    public static var contentWidth: CGFloat {
        max(markSide + markGap + artSide, WaveformView.width)
    }
}


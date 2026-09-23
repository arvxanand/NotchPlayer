import SwiftUI

/// The Spotify mark, drawn rather than bundled.
///
/// No asset for the same reason matchnotch draws its own app icon: a bundled
/// PNG is a resource to lose, a scale to get wrong and a thing that cannot
/// take a colour. Three arcs and a circle is less code than the plumbing to
/// load an image would be.
///
/// Geometry is in a unit square and scaled, so one shape serves the 11pt mark
/// in the peek and the 12pt one in the panel. The arcs share a centre of
/// curvature *below* the mark, which is what makes them bulge upward the way
/// the real logo's do.
public struct SpotifyMark: View {
    public init() {}

    /// Centre of curvature, in unit space, y down.
    ///
    /// Solved rather than eyeballed. Each arc is specified by where its apex
    /// and its endpoints should sit inside the circle, and the radius and
    /// sweep fall out of that: for an arc centred at `(0.5, cy)`, the apex is
    /// at `cy - r` and an endpoint at half-sweep `t` is at
    /// `(0.5 + r sin t, cy - r cos t)`. Picking `cy = 1.0` puts all three
    /// centres on the circle's bottom edge, which is what makes the three
    /// bars share a family resemblance instead of looking like three
    /// unrelated curves.
    ///
    /// Apexes at y = 0.30 / 0.45 / 0.585, endpoints out to x = 0.86 / 0.80 /
    /// 0.74. That leaves ~0.30 of clear green above the top bar and ~0.34
    /// below the bottom one, which is the balance the real mark has -- the
    /// first attempt filled the circle edge to edge and read as a wifi glyph.
    private static let curveCenterY: CGFloat = 1.0

    /// Radius, half-sweep in degrees, and stroke width -- outermost first.
    private static let arcs: [(radius: CGFloat, sweep: CGFloat, width: CGFloat)] = [
        (0.700, 31.0, 0.095),
        (0.550, 33.0, 0.082),
        (0.415, 35.3, 0.070),
    ]

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Palette.spotify)
                ForEach(Array(Self.arcs.enumerated()), id: \.offset) { _, arc in
                    Path { path in
                        path.addArc(center: CGPoint(x: 0.5 * s, y: Self.curveCenterY * s),
                                    radius: arc.radius * s,
                                    startAngle: .degrees(-90 - Double(arc.sweep)),
                                    endAngle: .degrees(-90 + Double(arc.sweep)),
                                    clockwise: false)
                    }
                    .stroke(Palette.background,
                            style: StrokeStyle(lineWidth: arc.width * s, lineCap: .round))
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

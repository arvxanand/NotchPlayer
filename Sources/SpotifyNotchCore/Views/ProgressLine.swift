import SwiftUI

/// The playback position, as a line.
///
/// **Built as a fraction and a rect, deliberately.** Scrubbing was deferred,
/// not rejected, and `player position` is writable -- so the drag that turns
/// this interactive is a gesture plus one write rather than a rewrite. The
/// geometry it would need is already the geometry it draws with.
public struct ProgressLine: View {
    let fraction: Double

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public static let thickness: CGFloat = 3

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(Palette.primary)
                    .frame(width: Self.filled(fraction, in: width))
            }
        }
        .frame(height: Self.thickness)
    }

    /// Pure, so the clamping can be asserted. A stale interpolator or a
    /// duration of zero must not draw a bar wider than its track or a
    /// negative frame, which SwiftUI turns into a runtime complaint.
    public static func filled(_ fraction: Double, in width: CGFloat) -> CGFloat {
        guard width > 0, fraction.isFinite else { return 0 }
        return width * CGFloat(min(1, max(0, fraction)))
    }
}

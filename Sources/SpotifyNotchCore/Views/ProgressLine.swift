import SwiftUI

/// The playback position, as a line you can drag.
///
/// **Built as a fraction and a rect from the start.** Scrubbing was deferred
/// in v1, not rejected, and `player position` is writable -- so turning this
/// interactive was a gesture and one write rather than a rewrite, which is
/// what that decision bought.
///
/// The line itself is 3pt tall and nobody can hit a 3pt target. The gesture
/// therefore lives on a band `hitHeight` tall, added with padding and taken
/// straight back off, so the hit area grows without the layout moving --
/// exactly the mistake `docs/TRAPS.md` #21 is about, made on purpose and in
/// the right order.
public struct ProgressLine: View {
    let fraction: Double
    /// nil when the track cannot be controlled: no drag, no knob, no hover
    /// growth. A control that looks live and does nothing is worse than one
    /// that looks inert.
    let onScrub: ((Double) -> Void)?
    let onCommit: ((Double) -> Void)?

    @State private var dragging = false

    public init(fraction: Double,
                onScrub: ((Double) -> Void)? = nil,
                onCommit: ((Double) -> Void)? = nil) {
        self.fraction = fraction
        self.onScrub = onScrub
        self.onCommit = onCommit
    }

    public static let thickness: CGFloat = 3
    /// What it grows to when the pointer is on it. Two points, which is the
    /// smallest change that reads as "this is a control" without shifting the
    /// text under it -- the row's height is fixed by `thickness`, and the line
    /// grows about its centre.
    public static let activeThickness: CGFloat = 5
    /// **Always drawn, not revealed on hover.**
    ///
    /// `.onHover` never fires here: tracking areas want an active application
    /// and this one is `.accessory` and never activates -- captured with the
    /// pointer sitting on the line, and the line was its resting 3pt with no
    /// knob. So the affordance cannot be a hover state. A small permanent knob
    /// says "draggable" without one, and marks the exact playhead while it is
    /// at it.
    ///
    /// 7pt, not 9: a permanent dot is on screen the whole time the panel is
    /// open, and at 9 it read as a bead on a string rather than a playhead.
    public static let knobSide: CGFloat = 7
    /// The draggable band. 20pt is a comfortable pointer target without
    /// reaching the times below or the cover beside it; the 44pt rule is for
    /// the transport buttons, which are the things a click can get wrong.
    public static let hitHeight: CGFloat = 20

    private var live: Bool { onScrub != nil }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = Self.filled(fraction, in: width)
            // **Both capsules state their own height, and the knob is an
            // overlay.** A `ZStack` sizes to its tallest child, and a shape
            // inside one fills whatever that comes to -- so adding a 7pt knob
            // to the stack quietly made the 3pt bar 7pt tall along its whole
            // length. An outer `.frame` does not fix that: it positions the
            // oversized content, it does not shrink it. Measured off a capture
            // rather than noticed by eye.
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track).frame(height: barHeight)
                Capsule().fill(Palette.primary).frame(width: filled, height: barHeight)
            }
            .frame(height: Self.thickness)
            .overlay(alignment: .leading) {
                if live {
                    Circle()
                        .fill(Palette.primary)
                        .frame(width: Self.knobSide, height: Self.knobSide)
                        // Centred on the playhead, and allowed past both ends,
                        // so it marks the position rather than the edge of the
                        // space it has to move in.
                        .offset(x: filled - Self.knobSide / 2)
                }
            }
            .animation(.easeOut(duration: 0.12), value: dragging)
            .contentShape(Rectangle())
            .gesture(live ? drag(width: width) : nil)
        }
        // The row's height never changes; only the band that answers the
        // pointer does.
        .frame(height: Self.thickness)
        .padding(.vertical, (Self.hitHeight - Self.thickness) / 2)
        .contentShape(Rectangle())
        .padding(.vertical, -(Self.hitHeight - Self.thickness) / 2)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }

    /// Thickens while being dragged -- which works without an active app,
    /// because a drag is events rather than tracking.
    private var barHeight: CGFloat { dragging ? Self.activeThickness : Self.thickness }

    /// `minimumDistance: 0` so a plain click seeks to where it landed. A
    /// scrubber you have to drag is a scrubber that ignores half the clicks
    /// aimed at it.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragging = true
                onScrub?(Self.fraction(atX: value.location.x, width: width))
            }
            .onEnded { value in
                dragging = false
                onCommit?(Self.fraction(atX: value.location.x, width: width))
            }
    }

    /// Pure, so the clamping can be asserted. A stale interpolator or a
    /// duration of zero must not draw a bar wider than its track or a
    /// negative frame, which SwiftUI turns into a runtime complaint.
    public static func filled(_ fraction: Double, in width: CGFloat) -> CGFloat {
        guard width > 0, fraction.isFinite else { return 0 }
        return width * CGFloat(min(1, max(0, fraction)))
    }

    /// Where a pointer at `x` lands in the track, 0...1.
    ///
    /// Clamped rather than guarded: a drag that continues past either end of
    /// the line is a drag to the start or to the end, which is what the user
    /// means by it. Pure for the same reason `filled` is.
    public static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return Double(min(width, max(0, x)) / width)
    }
}

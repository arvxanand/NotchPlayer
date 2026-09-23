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
    /// The filled part and the knob. The cover's colour (`Accent`), or white
    /// when the cover is grey or not loaded.
    let accent: Color

    @State private var dragging = false

    public init(fraction: Double, accent: Color = Palette.primary,
                onScrub: ((Double) -> Void)? = nil,
                onCommit: ((Double) -> Void)? = nil) {
        self.fraction = fraction
        self.accent = accent
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
    /// The draggable band, centred on the line.
    ///
    /// **30pt for a 3pt line.** Twenty was the first guess and it was not
    /// enough in the hand: a pointer tip has to be within a few points of a
    /// hairline, and missing feels like the control is broken rather than like
    /// a miss. Thirty reaches from 14pt above the line to 14pt below, which
    /// still clears the transport row's top edge by a comfortable margin --
    /// `PanelTests` asserts that clearance rather than trusting this comment.
    ///
    /// Nothing else in that band is interactive: the elapsed and remaining
    /// times sit under the line and are text.
    public static let hitHeight: CGFloat = 30

    private var live: Bool { onScrub != nil }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = Self.filled(fraction, in: width)
            bar(filled: filled)
                // **The gesture goes on the tall box, and this is the whole
                // point of the tall box.** It was attached to the 3pt line
                // with an enlarged `contentShape` on an outer view that had no
                // gesture on it -- which does nothing at all, so only the 3pt
                // line answered. Reported as "it works about half the time",
                // which is exactly what aiming at three points feels like.
                //
                // The box overflows its 3pt layout slot equally above and
                // below, so the line stays where it was drawn and only the
                // target grows. `.contentShape` last, after every sizing
                // modifier (`docs/TRAPS.md` #21).
                // **Symmetric padding, then the shape, then the gesture, then
                // the padding taken back off.** Two earlier attempts at the
                // same band were both wrong in ways only a live probe showed:
                // a `.contentShape` on an outer view with no gesture on it
                // does nothing at all, and `.frame(height:)` plus `.offset`
                // inside a `GeometryReader` left the band hanging below the
                // line -- a click 11pt above was dead while one 22pt below,
                // in the transport row's territory, seeked.
                //
                // Padding is symmetric by construction, so the band is centred
                // on the line whatever the reader does with alignment; the
                // negative padding afterwards keeps the row's layout at 3pt.
                .padding(.vertical, Self.pad)
                .contentShape(Rectangle())
                .gesture(live ? drag(width: width) : nil)
                .padding(.vertical, -Self.pad)
        }
        // The row's height never changes; only the band that answers the
        // pointer does.
        .frame(height: Self.thickness)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }

    /// **Both capsules state their own height, and the knob is an overlay.** A
    /// `ZStack` sizes to its tallest child, and a shape inside one fills
    /// whatever that comes to -- so adding a 7pt knob to the stack quietly
    /// made the 3pt bar 7pt tall along its whole length. An outer `.frame`
    /// does not fix that: it positions oversized content, it does not shrink
    /// it. Measured off a capture rather than noticed by eye.
    private func bar(filled: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.track).frame(height: barHeight)
            // The animation sits between the fill and the frame, so it only
            // covers the colour: a new song's colour fades in, while the width
            // jumping back to the start is not animated along with it.
            Capsule().fill(accent).animation(Self.fade, value: accent)
                .frame(width: filled, height: barHeight)
        }
        .frame(height: Self.thickness)
        .overlay(alignment: .leading) {
            if live {
                Circle()
                    .fill(accent).animation(Self.fade, value: accent)
                    .frame(width: Self.knobSide, height: Self.knobSide)
                    // Centred on the playhead, and allowed past both ends, so
                    // it marks the position rather than the edge of the space
                    // it has to move in.
                    .offset(x: filled - Self.knobSide / 2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: dragging)
    }

    static let fade = Animation.easeOut(duration: 0.4)

    /// Thickens while being dragged -- which works without an active app,
    /// because a drag is events rather than tracking.
    private var barHeight: CGFloat { dragging ? Self.activeThickness : Self.thickness }

    /// Half the band, minus the line it is centred on.
    static var pad: CGFloat { (hitHeight - thickness) / 2 }

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

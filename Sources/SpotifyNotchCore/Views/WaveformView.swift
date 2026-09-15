import SwiftUI

/// The bars in the right wing.
///
/// **Source-agnostic on purpose.** It takes numbers, not audio. That is what
/// lets the synthetic generator ship first and the Core Audio tap replace it
/// behind the same view later, instead of debugging Core Audio and layout at
/// the same time.
public struct WaveformView: View {
    /// Non-nil pins the bars to fixed values, which is what makes a preview
    /// capture reproducible. Nil animates.
    let hold: [Float]?
    let barHeight: ClosedRange<CGFloat>

    public init(hold: [Float]? = nil,
                barHeight: ClosedRange<CGFloat> = WaveformView.defaultHeight) {
        self.hold = hold
        self.barHeight = barHeight
    }

    /// 2pt when silent -- a row of dots, which reads as paused on its own --
    /// up to 22pt, near the 25pt cover so the two sides of the cutout carry
    /// the same visual weight.
    public static let defaultHeight: ClosedRange<CGFloat> = 2...22
    public static let barWidth: CGFloat = 2
    public static let gap: CGFloat = 2

    /// What the bars occupy: the last bar has no gap after it.
    public static var width: CGFloat {
        CGFloat(Bands.count) * barWidth + CGFloat(Bands.count - 1) * gap
    }

    public var body: some View {
        if let hold {
            bars(hold)
        } else {
            // **Not `Timer.publish` in an initialiser.** One created there dies
            // when the parent re-renders, and the bars would stop for no
            // visible reason (matchnotch TRAPS #6). TimelineView owns its own
            // schedule and survives the parent rebuilding.
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                bars(Bands.synthetic(at: context.date.timeIntervalSinceReferenceDate))
            }
        }
    }

    /// No SwiftUI animation on the heights, deliberately. The smoothing lives
    /// in the numbers -- `Bands.synthetic` is already continuous, and the real
    /// tap gets `Bands.envelope`. Animating a value that changes 30 times a
    /// second means every frame interrupts the last one's spring, which is how
    /// a waveform ends up looking like jelly rather than like audio.
    private func bars(_ values: [Float]) -> some View {
        HStack(alignment: .center, spacing: Self.gap) {
            ForEach(values.indices, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Palette.primary)
                    .frame(width: Self.barWidth, height: height(values[i]))
            }
        }
        .frame(width: Self.width, height: barHeight.upperBound)
    }

    private func height(_ value: Float) -> CGFloat {
        let clamped = CGFloat(max(0, min(1, value)))
        return barHeight.lowerBound
            + clamped * (barHeight.upperBound - barHeight.lowerBound)
    }
}

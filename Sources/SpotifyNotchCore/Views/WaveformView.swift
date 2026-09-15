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
    ///
    /// **It also outranks the live tap**, so a capture cannot be changed by
    /// whatever is coming out of the speakers while it is taken.
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

    /// The live tap, when there is one. Passed through the environment rather
    /// than down four initialisers: `RootView` and `PeekView` are functions of
    /// plain values, which is what lets every preview state render through the
    /// production hierarchy, and an observable object in their signatures
    /// would end that.
    @Environment(\.liveBands) private var tap

    public var body: some View {
        if let hold {
            Bars(values: hold, barHeight: barHeight)
        } else if let tap {
            LiveBars(tap: tap, barHeight: barHeight)
        } else {
            SyntheticBars(barHeight: barHeight)
        }
    }
}

/// Real audio when it is arriving, the synthetic generator when it is not.
///
/// The fallback is silent on purpose. A waveform is decoration; a user whose
/// audio-recording permission is off should see bars that move, not an
/// explanation of Core Audio.
private struct LiveBars: View {
    @ObservedObject var tap: AudioTap
    let barHeight: ClosedRange<CGFloat>

    var body: some View {
        if let bands = tap.bands {
            Bars(values: bands, barHeight: barHeight)
        } else {
            SyntheticBars(barHeight: barHeight)
        }
    }
}

private struct SyntheticBars: View {
    let barHeight: ClosedRange<CGFloat>

    var body: some View {
        // **Not `Timer.publish` in an initialiser.** One created there dies
        // when the parent re-renders, and the bars would stop for no visible
        // reason (matchnotch TRAPS #6). TimelineView owns its own schedule and
        // survives the parent rebuilding.
        TimelineView(.periodic(from: .now, by: 1.0 / AudioTap.frameRate)) { context in
            Bars(values: Bands.synthetic(at: context.date.timeIntervalSinceReferenceDate),
                 barHeight: barHeight)
        }
    }
}

/// No SwiftUI animation on the heights, deliberately. The smoothing lives in
/// the numbers -- `Bands.synthetic` is already continuous, and the real tap
/// goes through `Bands.envelope`. Animating a value that changes 30 times a
/// second means every frame interrupts the last one's spring, which is how a
/// waveform ends up looking like jelly rather than like audio.
private struct Bars: View {
    let values: [Float]
    let barHeight: ClosedRange<CGFloat>

    var body: some View {
        HStack(alignment: .center, spacing: WaveformView.gap) {
            ForEach(values.indices, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Palette.primary)
                    .frame(width: WaveformView.barWidth, height: height(values[i]))
            }
        }
        .frame(width: WaveformView.width, height: barHeight.upperBound)
    }

    private func height(_ value: Float) -> CGFloat {
        let clamped = CGFloat(max(0, min(1, value)))
        return barHeight.lowerBound
            + clamped * (barHeight.upperBound - barHeight.lowerBound)
    }
}

/// How the live tap reaches the one view that wants it.
private struct LiveBandsKey: EnvironmentKey {
    static let defaultValue: AudioTap? = nil
}

extension EnvironmentValues {
    /// nil everywhere except the live app: previews, captures and tests all
    /// draw synthetic bars, which is what makes a captured peek reproducible.
    public var liveBands: AudioTap? {
        get { self[LiveBandsKey.self] }
        set { self[LiveBandsKey.self] = newValue }
    }
}

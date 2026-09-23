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
    /// production hierarchy, and an object in their signatures would end that.
    @Environment(\.liveBands) private var tap

    public var body: some View {
        if let hold {
            // A capture: fixed values, drawn once, no timer anywhere.
            Bars(values: hold, barHeight: barHeight)
        } else {
            // Everything that moves goes through Core Animation. The tap
            // returns nil when there is no live audio and `BarsView` draws
            // synthetic bars instead, so the fallback never reaches SwiftUI.
            BarsLayer(source: { [tap] in tap?.frame() }, barHeight: barHeight)
                .frame(width: Self.width, height: barHeight.upperBound)
                // Decoration. A screen reader announcing fourteen bar heights
                // thirty times a second is worse than silence, and the track is
                // named in the panel and in the menu bar.
                .accessibilityHidden(true)
        }
    }
}

/// The still version, for a capture. Nothing here animates, so it can stay
/// SwiftUI -- the moving bars are `BarsLayer`, which exists because SwiftUI's
/// per-frame update is what the waveform could not afford.
private struct Bars: View {
    let values: [Float]
    let barHeight: ClosedRange<CGFloat>

    var body: some View {
        // **Drawn into an overlay of a fixed-size spacer, not laid out.** A
        // view whose content can change its own size makes every ancestor
        // stack re-run layout when it does -- thirty times a second, which a
        // `sample` of the running agent showed as `StackLayout.sizeThatFits`
        // and `LayoutEngineBox` at the top of the profile. An overlay cannot
        // influence its parent's size, so the layout pass stops here.
        Color.clear
            .frame(width: WaveformView.width, height: barHeight.upperBound)
            .overlay { canvas }
    }

    private var canvas: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let width = WaveformView.barWidth
            let pitch = width + WaveformView.gap
            for (index, value) in values.enumerated() {
                let bar = height(value)
                let rect = CGRect(x: CGFloat(index) * pitch,
                                  y: (size.height - bar) / 2,
                                  width: width, height: bar)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .color(Palette.primary))
            }
        }
        // Decoration. A screen reader announcing fourteen bar heights thirty
        // times a second is worse than silence, and the track is named in the
        // panel and in the menu bar.
        .accessibilityHidden(true)
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

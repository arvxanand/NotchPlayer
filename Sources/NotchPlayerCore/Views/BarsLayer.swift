import AppKit
import SwiftUI

/// The waveform's bars, drawn as Core Animation layers and driven by a timer
/// this view owns.
///
/// **Why not SwiftUI.** The bars change thirty times a second for as long as
/// music plays. Published through SwiftUI that meant thirty view-tree updates
/// a second: measured at **8.8% of a core**, against **0.8%** for the tap and
/// the FFT feeding it. Two things that should have helped did not -- a
/// `Canvas` instead of fourteen `Capsule`s, and taking the bars out of the
/// layout -- because the cost was not the drawing or the layout but SwiftUI's
/// per-frame update itself, at roughly 0.3% of a core per frame per second
/// whatever the frame contained.
///
/// So the per-frame path goes around SwiftUI entirely: fourteen `CALayer`s
/// whose `frame`s are set in place, inside a transaction with implicit
/// animation off. SwiftUI builds this view once when the peek appears and is
/// not involved again until it disappears.
///
/// The view *pulls* each frame rather than being pushed one, so there is a
/// single timer for the whole feature: the tap does its arithmetic when a
/// frame is about to be drawn, and does none when nothing is drawing.
struct BarsLayer: NSViewRepresentable {
    /// Where a frame comes from. Returns nil for "no live audio", which the
    /// view answers with synthetic bars -- the fallback lives here so the
    /// switch costs nothing on the SwiftUI side.
    let source: () -> [Float]?
    let barHeight: ClosedRange<CGFloat>

    func makeNSView(context: Context) -> BarsView {
        BarsView(source: source, barHeight: barHeight)
    }

    func updateNSView(_ view: BarsView, context: Context) {
        // Only the closure, and only because SwiftUI may hand over a fresh one
        // when an unrelated part of the panel changes. No frame data crosses
        // this boundary.
        view.source = source
    }

    static func dismantleNSView(_ view: BarsView, coordinator: ()) { view.stop() }
}

final class BarsView: NSView {
    var source: () -> [Float]?
    private let barHeight: ClosedRange<CGFloat>
    private var bars: [CALayer] = []
    private var timer: Timer?
    /// The last values drawn, so an unchanged frame costs nothing. A paused
    /// stream settles to a flat row and then stops touching the layers.
    private var shown: [Float] = []

    init(source: @escaping () -> [Float]?, barHeight: ClosedRange<CGFloat>) {
        self.source = source
        self.barHeight = barHeight
        super.init(frame: CGRect(x: 0, y: 0, width: WaveformView.width,
                                 height: barHeight.upperBound))
        wantsLayer = true
        layer?.masksToBounds = false
        let colour = NSColor.white.withAlphaComponent(Palette.primaryLevel).cgColor
        for index in 0..<Bands.count {
            let bar = CALayer()
            bar.backgroundColor = colour
            bar.cornerRadius = WaveformView.barWidth / 2
            bar.frame = rect(for: index, value: 0)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        shown = [Float](repeating: -1, count: Bands.count)   // force a first draw
        start()
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    private func start() {
        // `.common` so the bars keep moving while a menu is open: the default
        // mode stops during event tracking, and a frozen waveform reads as a
        // crashed app.
        let timer = Timer(timeInterval: 1 / AudioTap.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func draw() {
        let values = source() ?? Bands.synthetic(at: Date().timeIntervalSinceReferenceDate)
        guard values.count == bars.count, values != shown else { return }
        shown = values
        // **Implicit animation off.** Core Animation animates a layer's frame
        // over 0.25s by default, so thirty frames a second would each start a
        // quarter-second animation and the bars would lag the music by about
        // eight frames while looking like jelly. The smoothing that belongs
        // here is `Bands.envelope`, in the numbers, where it can be tested.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, value) in values.enumerated() {
            bars[index].frame = rect(for: index, value: value)
        }
        CATransaction.commit()
    }

    /// AppKit's origin is bottom-left and the bars grow about their centre, so
    /// each one is placed rather than anchored.
    private func rect(for index: Int, value: Float) -> CGRect {
        let clamped = CGFloat(max(0, min(1, value)))
        let height = barHeight.lowerBound
            + clamped * (barHeight.upperBound - barHeight.lowerBound)
        let x = CGFloat(index) * (WaveformView.barWidth + WaveformView.gap)
        return CGRect(x: x, y: (barHeight.upperBound - height) / 2,
                      width: WaveformView.barWidth, height: height)
    }
}

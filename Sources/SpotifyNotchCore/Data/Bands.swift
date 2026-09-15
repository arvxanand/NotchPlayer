import Foundation

/// The waveform's numbers, kept apart from the view that draws them and from
/// the Core Audio tap that will eventually feed them.
///
/// The split is the test seam: everything here is a pure function over
/// `[Float]`, so it can be asserted. The tap is the part that cannot be.
public enum Bands {
    /// How many bars the peek draws. Small on purpose -- there are ~54pt to
    /// draw them in, and a 2048-point FFT at 60Hz to fill fourteen bars would
    /// be absurd.
    public static let count = 14

    public static let silent = [Float](repeating: 0, count: count)

    /// Attack/decay smoothing, per band.
    ///
    /// Raw magnitudes read as noise: they jump a full band height between
    /// frames and the eye sees flicker rather than music. Attack is fast so a
    /// transient still lands; decay is slow so the bar falls like a meter
    /// needle. Unused until the tap arrives in the milestone that needs it,
    /// and written now because it is the half that can be tested.
    public static func envelope(_ previous: [Float], toward target: [Float],
                                attack: Float = 0.5, decay: Float = 0.12) -> [Float] {
        guard previous.count == target.count else { return target }
        return zip(previous, target).map { was, now in
            let rate = now > was ? attack : decay
            return max(0, min(1, was + (now - was) * rate))
        }
    }

    /// Bars that look like music, from a clock rather than from audio.
    ///
    /// **Deterministic, with no randomness anywhere.** A preview render has to
    /// be identical run to run or the footprint check compares two different
    /// pictures and reports whichever it feels like. It also means a captured
    /// peek can be diffed against a later one.
    ///
    /// Bass-tilted, because real spectra are: a flat distribution reads as a
    /// row of identical twitching sticks, not as a spectrum.
    public static func synthetic(at t: Double, count: Int = count) -> [Float] {
        guard count > 1 else { return [Float](repeating: 0.5, count: max(0, count)) }
        return (0..<count).map { i in
            let f = Double(i) / Double(count - 1)
            let tilt = pow(1 - f, 0.8) * 0.68 + 0.32
            let fast = sin(t * (1.7 + 2.3 * f) + Double(i) * 1.1)
            let slow = sin(t * (0.6 + 0.9 * f) + Double(i) * 2.7)
            let mixed = (fast * 0.6 + slow * 0.4 + 1) / 2
            return Float(max(0, min(1, mixed * tilt)))
        }
    }
}

import Accelerate
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

// MARK: - Real audio

extension Bands {
    /// 1024 samples at 48kHz is 21ms of audio and 47Hz-wide bins. Wide enough
    /// that a bass note lands in one bin rather than smearing across four,
    /// short enough that a transient is still visible in the frame it happens
    /// in.
    public static let fftSize = 1024
    /// What the process tap reported on this machine. Not assumed at runtime
    /// -- `AudioTap` reads `kAudioTapPropertyFormat` and passes the real rate
    /// in -- but it is the default everything here is sized around.
    public static let sampleRate: Double = 48_000

    /// The range the bars cover. Below 40Hz is rumble no laptop speaker
    /// reproduces, and above 12kHz is cymbal shimmer that never moves a bar
    /// far enough to see. Spending bands there wastes them.
    public static let lowHz: Double = 40
    public static let highHz: Double = 12_000

    /// Quietest magnitude that still lifts a bar off the floor. -60dB is
    /// roughly the noise floor of a lossy stream, so anything quieter is
    /// nothing worth drawing.
    public static let floorDB: Float = -60

    /// Which FFT bins belong to each bar, spaced logarithmically.
    ///
    /// **Linear spacing is the mistake this exists to avoid.** Half of a
    /// linear spectrum is above 12kHz, where music has almost no energy, so
    /// linear bars leave the bottom two lit and the other twelve dead. Pitch
    /// is logarithmic and so is hearing.
    ///
    /// Ranges are contiguous and never empty: a band whose edges round to the
    /// same bin still gets that one bin, which is what the lowest bars need at
    /// this FFT size.
    public static func binRanges(count: Int = count,
                                 sampleRate: Double = sampleRate,
                                 fftSize: Int = fftSize,
                                 low: Double = lowHz,
                                 high: Double = highHz) -> [Range<Int>] {
        let bins = fftSize / 2
        guard count > 0, bins > 1, low > 0, high > low else { return [] }
        let perHz = Double(fftSize) / sampleRate
        // Bin 0 is DC -- a constant offset, not a frequency -- and drawing it
        // pins the first bar to whatever the signal's average happens to be.
        var start = max(1, Int((low * perHz).rounded()))
        var ranges: [Range<Int>] = []
        for i in 1...count {
            let edge = low * pow(high / low, Double(i) / Double(count))
            let end = min(bins, max(start + 1, Int((edge * perHz).rounded())))
            guard start < bins else { break }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// Bar heights in 0...1 from FFT magnitudes.
    ///
    /// **The peak of each band, not the mean.** A band that spans 40 bins
    /// averages one loud partial against 39 quiet ones and reads as
    /// permanently half-lit; the peak is what the ear picks out of that band
    /// anyway.
    ///
    /// Decibels, not raw magnitude. Loudness is logarithmic, so a linear bar
    /// spends its whole height on the top 10% of the dynamic range and sits
    /// flat for everything else -- which is the single biggest reason a
    /// homemade visualiser looks wrong.
    public static func levels(magnitudes: [Float], ranges: [Range<Int>],
                              floorDB: Float = floorDB) -> [Float] {
        ranges.map { range in
            let clamped = range.clamped(to: 0..<magnitudes.count)
            guard !clamped.isEmpty else { return 0 }
            let peak = magnitudes[clamped].max() ?? 0
            guard peak > 0 else { return 0 }
            let db = 20 * log10f(peak)
            return max(0, min(1, (db - floorDB) / -floorDB))
        }
    }
}

/// A windowed real FFT, sized once and reused.
///
/// Held for the lifetime of the tap rather than built per frame: the setup
/// allocates twiddle tables, and doing that 30 times a second in something
/// that runs all day is exactly the shape of waste `docs/TRAPS.md` warns
/// about.
public final class Spectrum {
    public let size: Int
    private let window: [Float]
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let outRealp: UnsafeMutablePointer<Float>
    private let outImagp: UnsafeMutablePointer<Float>

    /// Fails rather than trapping on a size vDSP cannot transform, so a wrong
    /// constant is a silent fallback to synthetic bars and not a crash in a
    /// resident agent.
    public init?(size: Int = Bands.fftSize) {
        guard size >= 8, size.nonzeroBitCount == 1,
              let fft = vDSP.FFT(log2n: vDSP_Length(size.trailingZeroBitCount),
                                 radix: .radix2, ofType: DSPSplitComplex.self)
        else { return nil }
        self.size = size
        self.fft = fft
        // Hann: a rectangular window makes every partial leak across the whole
        // spectrum, which looks like all fourteen bars breathing together.
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                  count: size, isHalfWindow: false)
        let half = size / 2
        realp = .allocate(capacity: half); imagp = .allocate(capacity: half)
        outRealp = .allocate(capacity: half); outImagp = .allocate(capacity: half)
        realp.initialize(repeating: 0, count: half)
        imagp.initialize(repeating: 0, count: half)
        outRealp.initialize(repeating: 0, count: half)
        outImagp.initialize(repeating: 0, count: half)
    }

    deinit {
        realp.deallocate(); imagp.deallocate()
        outRealp.deallocate(); outImagp.deallocate()
    }

    /// Magnitude per bin, `size / 2` of them, scaled so a full-scale sine
    /// reads about 1.0 in its own bin.
    ///
    /// Short input is zero-padded rather than refused -- the first buffer
    /// after the tap starts is often partial, and a bar row that appears one
    /// frame late is better than one that throws.
    public func magnitudes(_ samples: [Float]) -> [Float] {
        let half = size / 2
        var input = [Float](repeating: 0, count: size)
        for i in 0..<min(samples.count, size) { input[i] = samples[i] * window[i] }

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: DSPComplex.self).baseAddress else { return }
            vDSP_ctoz(base, 2, &split, 1, vDSP_Length(half))
        }
        var out = DSPSplitComplex(realp: outRealp, imagp: outImagp)
        fft.forward(input: split, output: &out)

        var mags = [Float](repeating: 0, count: half)
        vDSP_zvabs(&out, 1, &mags, 1, vDSP_Length(half))
        // 2/size for the transform, times 2 again for a Hann window's 0.5
        // coherent gain, times 0.5 because vDSP's packed real FFT already
        // carries a factor of two. Net 2/size -- asserted by
        // `testFullScaleSineReadsFullScale` rather than trusted.
        return vDSP.multiply(2 / Float(size), mags)
    }
}

/// Samples in, bar heights out. The whole chain in one object so the tap has
/// one call to make and the test has one thing to drive.
public final class Analyzer {
    private let spectrum: Spectrum
    private let ranges: [Range<Int>]
    private var previous: [Float]

    public init?(count: Int = Bands.count, sampleRate: Double = Bands.sampleRate,
                 fftSize: Int = Bands.fftSize) {
        guard let spectrum = Spectrum(size: fftSize) else { return nil }
        self.spectrum = spectrum
        self.ranges = Bands.binRanges(count: count, sampleRate: sampleRate, fftSize: fftSize)
        self.previous = [Float](repeating: 0, count: count)
        guard ranges.count == count else { return nil }
    }

    public func push(_ samples: [Float]) -> [Float] {
        let target = Bands.levels(magnitudes: spectrum.magnitudes(samples), ranges: ranges)
        previous = Bands.envelope(previous, toward: target)
        return previous
    }

    /// One frame of decay with no new audio, so a paused stream falls to the
    /// floor instead of freezing mid-song.
    public func idle() -> [Float] {
        previous = Bands.envelope(previous, toward: [Float](repeating: 0, count: previous.count))
        return previous
    }
}

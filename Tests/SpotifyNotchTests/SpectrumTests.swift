import XCTest
@testable import SpotifyNotchCore

/// The real-audio half of `Bands`, driven by signals whose answer is known
/// before the code runs. A visualiser is the easiest thing in the world to
/// write wrong and call finished -- it moves, so it looks alive whatever the
/// numbers mean. These assert what the numbers mean.
final class SpectrumTests: XCTestCase {

    /// The exact centre of a bin. A tone between two bins splits its energy
    /// across both -- real scalloping loss, up to 1.4dB with a Hann window --
    /// so a test that asserts "this bar and not its neighbour" has to pick a
    /// frequency the FFT can represent, or it is asserting a coin toss.
    private func binCentre(_ bin: Int, rate: Double = Bands.sampleRate,
                           size: Int = Bands.fftSize) -> Double {
        Double(bin) * rate / Double(size)
    }

    private func sine(_ hz: Double, amplitude: Float = 1,
                      count: Int = Bands.fftSize,
                      rate: Double = Bands.sampleRate) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    // MARK: - Bin ranges

    func testBandsTileTheSpectrumWithoutGapsOrOverlap() {
        let ranges = Bands.binRanges()
        XCTAssertEqual(ranges.count, Bands.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(a.upperBound, b.lowerBound, "gap or overlap between bands")
        }
        for r in ranges { XCTAssertFalse(r.isEmpty, "a band with no bins draws a dead bar") }
        XCTAssertGreaterThanOrEqual(ranges[0].lowerBound, 1, "bin 0 is DC, not a frequency")
        XCTAssertLessThanOrEqual(ranges.last!.upperBound, Bands.fftSize / 2)
    }

    /// The whole point of log spacing: the top band covers far more of the
    /// spectrum than the bottom one. Linear edges make this ratio 1.
    func testSpacingIsLogarithmicNotLinear() {
        let ranges = Bands.binRanges()
        let first = ranges[0].count
        let last = ranges[ranges.count - 1].count
        XCTAssertGreaterThan(last, first * 10,
                             "top band \(last) bins vs bottom \(first) -- that is linear spacing")
    }

    func testRangesStayInsideTheSpectrumAtAnyFFTSize() {
        for size in [64, 256, 1024, 4096] {
            let ranges = Bands.binRanges(fftSize: size)
            for r in ranges { XCTAssertLessThanOrEqual(r.upperBound, size / 2, "size \(size)") }
        }
    }

    // MARK: - The transform

    /// A full-scale sine must read as full scale, or every level above is
    /// measured against a scale nobody checked.
    func testFullScaleSineReadsFullScale() throws {
        let spectrum = try XCTUnwrap(Spectrum())
        let mags = spectrum.magnitudes(sine(binCentre(21)))
        let peak = try XCTUnwrap(mags.max())
        XCTAssertEqual(peak, 1.0, accuracy: 0.02, "FFT scaling is off")
        // Half amplitude is half the magnitude: the transform is linear and
        // the decibel curve is applied later, in `levels`.
        let quiet = try XCTUnwrap(spectrum.magnitudes(sine(binCentre(21), amplitude: 0.5)).max())
        XCTAssertEqual(quiet, 0.5, accuracy: 0.02)
    }

    func testEnergyLandsInTheRightBin() throws {
        let spectrum = try XCTUnwrap(Spectrum())
        for bin in [3, 21, 128] {
            let mags = spectrum.magnitudes(sine(binCentre(bin)))
            let loudest = try XCTUnwrap(mags.indices.max(by: { mags[$0] < mags[$1] }))
            XCTAssertEqual(loudest, bin)
        }
    }

    func testSilenceProducesNoMagnitude() throws {
        let spectrum = try XCTUnwrap(Spectrum())
        for m in spectrum.magnitudes([Float](repeating: 0, count: Bands.fftSize)) {
            XCTAssertEqual(m, 0, accuracy: 1e-6)
        }
    }

    func testShortBufferIsPaddedRatherThanRefused() throws {
        let spectrum = try XCTUnwrap(Spectrum())
        XCTAssertEqual(spectrum.magnitudes(Array(sine(1000).prefix(300))).count,
                       Bands.fftSize / 2)
    }

    func testSpectrumRejectsASizeItCannotTransform() {
        XCTAssertNil(Spectrum(size: 1000), "1000 is not a power of two")
        XCTAssertNil(Spectrum(size: 0))
    }

    // MARK: - Levels

    func testLevelsAreDecibelsNotRawMagnitude() {
        let one = Bands.levels(magnitudes: [1], ranges: [0..<1])[0]
        let half = Bands.levels(magnitudes: [0.5], ranges: [0..<1])[0]
        let floor = Bands.levels(magnitudes: [0.001], ranges: [0..<1])[0]   // -60dB
        XCTAssertEqual(one, 1, accuracy: 0.001)
        XCTAssertEqual(floor, 0, accuracy: 0.001)
        // Half amplitude is -6dB, a tenth of the range -- not half a bar.
        XCTAssertEqual(half, 0.9, accuracy: 0.01)
    }

    func testAQuietBandIsZeroRatherThanNegative() {
        for v in Bands.levels(magnitudes: [1e-9, 0], ranges: [0..<2]) {
            XCTAssertGreaterThanOrEqual(v, 0)
        }
    }

    func testABandTakesItsPeakNotItsAverage() {
        let mags: [Float] = [0.0001, 0.0001, 1, 0.0001]
        XCTAssertEqual(Bands.levels(magnitudes: mags, ranges: [0..<4])[0], 1, accuracy: 0.001)
    }

    func testRangesPastTheEndOfTheSpectrumDoNotCrash() {
        XCTAssertEqual(Bands.levels(magnitudes: [1, 1], ranges: [0..<2, 2..<8]), [1, 0])
    }

    // MARK: - End to end

    /// The assertion that actually says "this is a spectrum analyser": a tone
    /// lights the bar that owns its frequency and leaves the others alone.
    func testAToneLightsItsOwnBar() throws {
        let analyzer = try XCTUnwrap(Analyzer())
        let ranges = Bands.binRanges()
        for bin in [3, 21, 128] {
            let hz = binCentre(bin)
            let analyzer = try XCTUnwrap(Analyzer())
            var bars = Bands.silent
            // Several frames, because the envelope's attack is deliberately
            // not instant.
            for _ in 0..<20 { bars = analyzer.push(sine(hz)) }
            let expected = try XCTUnwrap(ranges.firstIndex { $0.contains(bin) })
            let loudest = try XCTUnwrap(bars.indices.max(by: { bars[$0] < bars[$1] }))
            XCTAssertEqual(loudest, expected, "\(Int(hz))Hz lit bar \(loudest), not \(expected)")
            XCTAssertGreaterThan(bars[expected], 0.8)
        }
        _ = analyzer
    }

    func testSilenceSettlesEveryBarToZero() throws {
        let analyzer = try XCTUnwrap(Analyzer())
        for _ in 0..<20 { _ = analyzer.push(sine(1000)) }
        var bars: [Float] = []
        for _ in 0..<200 { bars = analyzer.push([Float](repeating: 0, count: Bands.fftSize)) }
        for v in bars { XCTAssertEqual(v, 0, accuracy: 0.01) }
    }

    /// No audio at all is not the same as silent audio: the tap stops
    /// delivering when the stream stops, and the bars must still fall.
    func testIdleDecaysTowardTheFloor() throws {
        let analyzer = try XCTUnwrap(Analyzer())
        for _ in 0..<20 { _ = analyzer.push(sine(1000)) }
        let before = try XCTUnwrap(analyzer.idle().max())
        var last: [Float] = []
        for _ in 0..<200 { last = analyzer.idle() }
        XCTAssertGreaterThan(before, 0.5)
        for v in last { XCTAssertEqual(v, 0, accuracy: 0.01) }
    }

    /// The analyzer smooths; it does not pass magnitudes straight through.
    /// Raw frame-to-frame values read as flicker rather than as music, and the
    /// only way to tell the two apart from outside is that the first loud
    /// frame must not arrive at full height.
    func testTheFirstLoudFrameDoesNotSnapToFullHeight() throws {
        let analyzer = try XCTUnwrap(Analyzer())
        let first = try XCTUnwrap(analyzer.push(sine(binCentre(21))).max())
        let settled = try XCTUnwrap((0..<20).map { _ in analyzer.push(sine(binCentre(21))) }
                                             .last?.max())
        XCTAssertGreaterThan(settled, 0.9)
        XCTAssertLessThan(first, settled * 0.8, "no attack smoothing -- the bars will flicker")
    }

    func testAnalyzerAlwaysReturnsOneValuePerBar() throws {
        let analyzer = try XCTUnwrap(Analyzer())
        XCTAssertEqual(analyzer.push(sine(440)).count, Bands.count)
        XCTAssertEqual(analyzer.push([]).count, Bands.count)
        XCTAssertEqual(analyzer.idle().count, Bands.count)
    }

    // MARK: - The buffer between the audio thread and the main one

    private func ringWrite(_ ring: AudioRing, _ samples: [Float], channels: Int = 1) {
        samples.withUnsafeBufferPointer {
            ring.write(interleaved: $0.baseAddress!,
                       frames: samples.count / channels, channels: channels)
        }
    }

    func testTheRingMixesChannelsDownAsItCopies() {
        let ring = AudioRing(capacity: 16)
        ringWrite(ring, [1, 0, 0.5, 0.5, -1, 1], channels: 2)
        XCTAssertEqual(try XCTUnwrap(ring.take(3)), [0.5, 0.5, 0])
    }

    func testTheRingReturnsTheNewestSamplesLast() {
        let ring = AudioRing(capacity: 16)
        ringWrite(ring, [1, 2, 3, 4, 5])
        XCTAssertEqual(try XCTUnwrap(ring.take(3)), [3, 4, 5])
    }

    /// The case a ring buffer exists to get right, and the one that is wrong
    /// in most hand-written ones: more audio has arrived than the buffer
    /// holds, so the window straddles the wrap point.
    func testTheRingReadsCorrectlyAcrossTheWrap() {
        let ring = AudioRing(capacity: 8)
        ringWrite(ring, (1...13).map(Float.init))
        XCTAssertEqual(try XCTUnwrap(ring.take(4)), [10, 11, 12, 13])

        // The window itself spanning the wrap -- head is at 2 and the four
        // newest samples start at 6. This is the case that reads backwards off
        // the front of the buffer when the modulo is written the obvious way,
        // and it reads *garbage* rather than crashing, because the storage is
        // a raw pointer.
        let straddling = AudioRing(capacity: 8)
        ringWrite(straddling, (1...10).map(Float.init))
        XCTAssertEqual(try XCTUnwrap(straddling.take(4)), [7, 8, 9, 10])
    }

    /// A partial first window is padded at the front, so the newest sample is
    /// still the last one. Padding at the back would hand the analyzer a
    /// window whose audio is in the wrong place in time.
    func testAShortHistoryIsPaddedAtTheFront() {
        let ring = AudioRing(capacity: 16)
        ringWrite(ring, [7, 8])
        XCTAssertEqual(try XCTUnwrap(ring.take(4)), [0, 0, 7, 8])
    }

    /// Nil, not a repeat: the difference between a stream with a gap in it and
    /// a stream that has stopped. A repeated window holds the bars up forever
    /// on a paused track.
    func testTheRingSaysNothingWhenNothingIsNew() {
        let ring = AudioRing(capacity: 16)
        XCTAssertNil(ring.take(4))
        ringWrite(ring, [1, 2])
        XCTAssertNotNil(ring.take(4))
        XCTAssertNil(ring.take(4))
        ringWrite(ring, [3])
        XCTAssertNotNil(ring.take(4))
    }

    func testTheRingIgnoresAnEmptyBuffer() {
        let ring = AudioRing(capacity: 16)
        ringWrite(ring, [1])
        _ = ring.take(4)
        [Float]().withUnsafeBufferPointer { _ in }
        var nothing: Float = 0
        ring.write(interleaved: &nothing, frames: 0, channels: 2)
        ring.write(interleaved: &nothing, frames: 4, channels: 0)
        XCTAssertNil(ring.take(4))
    }

    // MARK: - When to stop believing the tap

    /// The rule that decides between a real waveform and the synthetic one.
    /// Everything else about the tap needs a real system; this does not.
    func testSilenceForLongerThanTheDeadlineFallsBack() {
        let start = Date()
        let deadline = AudioTap.deadline
        // Audio has been arriving: not silent, however long ago the tap began.
        XCTAssertFalse(AudioTap.hasGoneSilent(lastSignal: start.addingTimeInterval(9),
                                              startedAt: start,
                                              now: start.addingTimeInterval(9.5)))
        // A short gap between notes is not silence.
        XCTAssertFalse(AudioTap.hasGoneSilent(lastSignal: start,
                                              startedAt: start,
                                              now: start.addingTimeInterval(deadline - 0.1)))
        // A long one is.
        XCTAssertTrue(AudioTap.hasGoneSilent(lastSignal: start,
                                             startedAt: start,
                                             now: start.addingTimeInterval(deadline + 0.1)))
    }

    /// The permission case: buffers arrive from the moment the tap starts and
    /// every sample in them is zero, so there is no `lastSignal` at all.
    func testATapThatNeverCarriesSignalFallsBack() {
        let start = Date()
        XCTAssertFalse(AudioTap.hasGoneSilent(lastSignal: nil, startedAt: start,
                                              now: start.addingTimeInterval(0.5)))
        XCTAssertTrue(AudioTap.hasGoneSilent(lastSignal: nil, startedAt: start,
                                             now: start.addingTimeInterval(AudioTap.deadline + 1)))
    }
}

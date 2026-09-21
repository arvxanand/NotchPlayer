import AppKit
import AudioToolbox
import CoreAudio
import os

/// A Core Audio process tap on Spotify, turned into fourteen bar heights.
///
/// **This is the one part of the app that cannot be tested.** Everything it
/// computes lives in `Bands` behind a pure interface; what is left here is
/// Core Audio object plumbing, which needs a real system, a real Spotify and
/// a real user who has granted audio recording. So it is written to fail
/// quietly: any step that does not work leaves `bands` nil, the waveform falls
/// back to the synthetic generator, and the app looks exactly as it did before
/// this file existed.
///
/// **There is no public API to ask whether audio recording is permitted, or
/// to request it.** `AudioHardwareCreateProcessTap` returns `noErr` either
/// way; what happens without permission is that no buffer ever arrives. So
/// "nothing arrived" is a normal outcome and not an error -- see
/// `Self.deadline`.
/// **Pulled, not published.** `@Published` bar values put SwiftUI in the path
/// of every frame: thirty view-tree updates a second, which measured 8.8% of a
/// core while the arithmetic behind them measured 0.8%. The waveform now asks
/// this object for a frame when it is about to draw one, and nothing observes
/// it -- see `BarsLayer`.
@MainActor
public final class AudioTap {
    /// The last frame handed out. Not a publisher: reading it changes nothing
    /// and invalidates nothing.
    public private(set) var bands: [Float]?
    public private(set) var status: Status = .stopped

    public enum Status: Equatable, Sendable {
        case stopped
        case listening
        /// Buffers are arriving and every sample in them is zero.
        ///
        /// **This is what no permission looks like from inside the process.**
        /// The tap is created, the IOProc fires 40 times a second, and every
        /// frame is digital silence -- there is no error and no callback to
        /// say so. It is indistinguishable from a genuinely silent passage,
        /// which is why the rule is a timeout and not a flag.
        case silent
        /// The tap could not be built, or was built and never delivered.
        /// Carries the reason for `--bands`, not for the UI: the user is not
        /// told their waveform is synthetic, because a waveform is decoration
        /// and a sentence about Core Audio is not.
        case unavailable(String)
    }

    /// How long to wait for the first buffer before deciding this is not going
    /// to work. Two seconds is long enough for a stream that was mid-gap and
    /// short enough that nobody watches flat bars wondering.
    public nonisolated static let deadline: TimeInterval = 2
    /// How long a stream that *was* delivering may go quiet before the chain
    /// is rebuilt.
    ///
    /// **This is the headphones case.** A tap is created against one output
    /// format and the user plugs in AirPods, which is the single most likely
    /// thing to happen to a laptop during a song. The stream stops arriving,
    /// nothing errors, and the bars decay to flat and stay there -- a
    /// waveform that says "paused" over music that is playing. Rebuilding is
    /// cheap and the alternative is silently wrong forever.
    public nonisolated static let staleTimeout: TimeInterval = 3
    /// A rebuild that does not bring audio back means something structural is
    /// wrong, and a tap rebuilt every three seconds forever is a background
    /// app thrashing system audio objects.
    public nonisolated static let rebuildLimit = 3
    /// The bars are redrawn at 30Hz. 60 would double the wakeups of a process
    /// that runs all day to add motion nobody can see in a 22pt bar.
    public nonisolated static let frameRate: Double = 30

    private var chain: Chain?
    private var ring: AudioRing?
    private var analyzer: Analyzer?
    private var followed: AudioSource?
    private var startedAt: Date?
    private var rate: Double = Bands.sampleRate
    private var lastBuffer: Date?
    /// When a sample last had a value other than zero.
    private var lastSignal: Date?
    private var rebuilds = 0
    /// One log line per tap, either way.
    ///
    /// A resident agent has no console and no window to report from, so
    /// whether the waveform is real or synthetic is otherwise unknowable from
    /// outside the process -- the fallback is deliberately convincing.
    private var reported = false

    /// Called once when a source turns out to deliver nothing but digital
    /// silence, so whoever chose it can choose something else. An app can
    /// hold an audio stream open without playing anything, and Core Audio
    /// reports that as producing output.
    public var onSilence: ((AudioSource) -> Void)?

    public init() {}

    deinit { chain?.tearDown() }

    /// Follow one source, or nothing.
    ///
    /// Idempotent for the same source, because the caller is a state observer
    /// and will republish the same answer several times a minute. Rebuilding
    /// the chain each time would glitch the user's audio.
    public func follow(_ source: AudioSource?) {
        guard source != followed else { return }
        stop()
        rebuilds = 0
        guard let source else { return }
        followed = source
        start(source)
    }

    public func stop() {
        chain?.tearDown(); chain = nil
        ring = nil; analyzer = nil
        followed = nil
        startedAt = nil
        lastBuffer = nil
        lastSignal = nil
        if bands != nil { bands = nil }
        if status != .stopped { status = .stopped }
    }

    // MARK: - Building the chain

    private func start(_ source: AudioSource) {
        do {
            let chain = try Chain(object: source.object)
            // **The rate the tap actually reports, not the one the probe saw
            // once.** It follows the current output device: measured 48000 on
            // this machine in September and 44100 an hour later with a
            // different device selected. Sizing the log band edges for the
            // wrong rate puts every bar 9% off its frequency, which nothing
            // on screen would ever reveal.
            guard let analyzer = Analyzer(sampleRate: chain.format.mSampleRate) else {
                chain.tearDown()
                return fail("FFT setup failed")
            }
            let ring = AudioRing()
            try chain.startDelivering(into: ring)
            self.chain = chain
            self.ring = ring
            self.analyzer = analyzer
            self.rate = chain.format.mSampleRate
            self.startedAt = Date()
            self.status = .listening
            self.reported = false
        } catch {
            fail("\(error)")
        }
    }

    private func fail(_ reason: String) {
        chain?.tearDown(); chain = nil
        ring = nil; analyzer = nil
        bands = nil
        status = .unavailable(reason)
        NSLog("SpotifyNotch: no live waveform (%@)", reason)
    }

    /// One frame of bar heights, or nil when there is no live audio and the
    /// caller should draw synthetic bars instead.
    ///
    /// Called by whatever is about to draw, at its own rate. Everything the
    /// tap has to notice over time -- a stream that never delivered, one that
    /// stopped, digital silence -- is noticed here, because a tap nobody is
    /// drawing from has nothing to notice.
    @discardableResult
    public func frame() -> [Float]? {
        tick()
        return bands
    }

    private func tick() {
        guard let ring, let analyzer else { return }
        let now = Date()
        if let samples = ring.take(Bands.fftSize) {
            lastBuffer = now
            rebuilds = 0
            let values = analyzer.push(samples)
            if samples.contains(where: { $0 != 0 }) { lastSignal = now }
            // Digital silence for long enough is treated as no live audio at
            // all: a flat row of dots over music that is audibly playing is
            // worse than the synthetic bars, and the most likely cause is a
            // permission nobody can ask about.
            let quiet = Self.hasGoneSilent(lastSignal: lastSignal,
                                           startedAt: startedAt ?? now, now: now)
            bands = quiet ? nil : values
            status = quiet ? .silent : .listening
            if quiet, lastSignal == nil, let followed { onSilence?(followed) }
            if !reported, quiet || lastSignal != nil {
                reported = true
                NSLog("SpotifyNotch: waveform %@ (%.0fHz)",
                      quiet ? "synthetic -- tap is silent, audio recording permission"
                            : "live", rate)
            }
            return
        }
        // Nothing new: the stream has a gap, the output device changed under
        // it, or no buffer has ever arrived and none is going to.
        if bands != nil { bands = analyzer.idle() }
        if let lastBuffer {
            if now.timeIntervalSince(lastBuffer) > Self.staleTimeout { rebuild() }
        } else if let startedAt, now.timeIntervalSince(startedAt) > Self.deadline {
            let source = followed
            fail("no audio in \(Int(Self.deadline))s -- audio recording permission, most likely")
            // Keep the source so the observer's next publish is a no-op rather
            // than a rebuild of the same doomed chain every few seconds.
            followed = source
        }
    }

    /// Whether to stop believing the tap and fall back to synthetic bars.
    ///
    /// Pure, and lifted out of `tick` so it can be *called* by a test rather
    /// than restated in one -- the same reason `Expansion.shouldExpand` is its
    /// own function. Coming back is automatic: one non-zero sample sets
    /// `lastSignal` and the next frame is live again.
    public nonisolated static func hasGoneSilent(lastSignal: Date?, startedAt: Date,
                                                 now: Date) -> Bool {
        now.timeIntervalSince(lastSignal ?? startedAt) > deadline
    }

    private func rebuild() {
        guard rebuilds < Self.rebuildLimit, let source = followed else {
            let source = followed
            fail("stream stopped delivering")
            followed = source
            return
        }
        rebuilds += 1
        stop()
        followed = source
        start(source)
    }
}

// MARK: - The Core Audio objects

extension AudioTap {
    /// The three objects the tap needs, and the one job of tearing all three
    /// down in the right order. They are plain integers, so this can be
    /// touched from `deinit` without actor ceremony.
    ///
    /// **An aggregate device that outlives the process is visible in Audio
    /// MIDI Setup and in every app's device list.** Private ones are meant not
    /// to be, but a leaked tap is still a leaked system object, which is the
    /// audio equivalent of the leaked preview window in `docs/BUGS.md` #10.
    final class Chain {
        private let tapID: AudioObjectID
        private let aggregateID: AudioDeviceID
        private var ioProcID: AudioDeviceIOProcID?
        let format: AudioStreamBasicDescription

        init(object processObject: AudioObjectID) throws {
            let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
            description.uuid = UUID()
            description.name = "SpotifyNotch"
            description.isPrivate = true
            // **Unmuted, and this is not a detail.** The other behaviours let
            // a tap silence what it is listening to; muting the user's music
            // to draw a picture of it would be the single worst bug this app
            // could ship.
            description.muteBehavior = .unmuted

            var tap = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")
            tapID = tap

            format = try Chain.format(of: tap)

            // The tap is not a device and cannot be read from directly; an
            // aggregate that contains it is. No sub-devices: this aggregate
            // exists to carry the tap and nothing else.
            let uid = UUID().uuidString
            let settings: [String: Any] = [
                kAudioAggregateDeviceNameKey: "SpotifyNotch Tap",
                kAudioAggregateDeviceUIDKey: uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [] as [Any],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: description.uuid.uuidString,
                     kAudioSubTapDriftCompensationKey: true]
                ],
            ]
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            let created = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate)
            guard created == noErr else {
                AudioHardwareDestroyProcessTap(tap)
                throw Failure("create aggregate", created)
            }
            aggregateID = aggregate
        }

        /// The IOProc block runs on a real-time audio thread. It may not
        /// allocate, lock for long, log, or touch the main actor -- so all it
        /// does is mix the frames down and copy them into a fixed buffer.
        func startDelivering(into ring: AudioRing) throws {
            var procID: AudioDeviceIOProcID?
            let created = AudioDeviceCreateIOProcIDWithBlock(
                &procID, aggregateID, nil
            ) { _, input, _, _, _ in
                let list = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: input))
                guard let first = list.first, let data = first.mData else { return }
                // One buffer holding every channel is the interleaved case,
                // which is what the tap reported on this machine. Several
                // buffers means one per channel; take the first rather than
                // mixing across buffers, which would need a second loop for a
                // case that has not been seen.
                let lanes = list.count == 1 ? max(1, Int(first.mNumberChannels)) : 1
                let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * lanes)
                ring.write(interleaved: data.assumingMemoryBound(to: Float.self),
                           frames: frames, channels: lanes)
            }
            try check(created, "create IOProc")
            ioProcID = procID
            try check(AudioDeviceStart(aggregateID, procID), "start device")
        }

        /// Stop, unhook, and destroy -- in that order. Destroying an aggregate
        /// that still has a running IOProc leaves the tap alive with nothing
        /// attached to it.
        func tearDown() {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
        }

        /// Asked rather than assumed. The probe saw 48kHz stereo float, and
        /// the band edges are sized for 48kHz -- but a user on a 44.1kHz
        /// output would otherwise have every bar pointing at the wrong
        /// frequency with nothing to show for it.
        private static func format(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd),
                      "tap format")
            return asbd
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let code: OSStatus
        init(_ step: String, _ code: OSStatus) { self.step = step; self.code = code }
        var description: String { "\(step) failed (\(code))" }
    }
}

private func check(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw AudioTap.Failure(step, status) }
}

// MARK: - The buffer between the two threads

/// A fixed circular buffer of mono samples, written by the audio thread and
/// read by the main one.
///
/// The lock is held for a memcpy-sized span on both sides. An `os_unfair_lock`
/// in an IOProc is a priority-inversion risk in principle; the alternative is
/// a lock-free ring with acquire/release atomics, which is more code to get
/// subtly wrong for a waveform that can drop a frame with no consequence.
final class AudioRing: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private var head = 0
    private var written: UInt64 = 0
    private var taken: UInt64 = 0
    private var lock = os_unfair_lock_s()

    /// Four FFT windows, so a late reader still finds the recent past rather
    /// than a buffer that has already wrapped past it.
    init(capacity: Int = Bands.fftSize * 4) {
        self.capacity = max(1, capacity)
        storage = .allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit { storage.deallocate() }

    /// Audio thread. Mixes the channels down as it copies -- no allocation, no
    /// intermediate array.
    func write(interleaved: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0 else { return }
        os_unfair_lock_lock(&lock)
        let scale = 1 / Float(channels)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += interleaved[f * channels + c] }
            storage[head] = sum * scale
            head = (head + 1) % capacity
        }
        written &+= UInt64(frames)
        os_unfair_lock_unlock(&lock)
    }

    /// The most recent `n` samples, oldest first, or **nil when nothing new
    /// has arrived** since the last call.
    ///
    /// Nil rather than a repeat of the last window: a stopped stream and a
    /// silent one are different, and analysing the same window twice makes a
    /// paused track hold its bars up forever.
    func take(_ n: Int) -> [Float]? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard written > taken else { return nil }
        taken = written
        var out = [Float](repeating: 0, count: n)
        let available = Int(min(written, UInt64(min(n, capacity))))
        for i in 0..<available {
            let index = (head - available + i + capacity) % capacity
            // Short history is padded at the front, so the newest sample is
            // always the last one and a partial first window is not silently
            // time-shifted.
            out[n - available + i] = storage[index]
        }
        return out
    }
}

// MARK: - Finding Spotify



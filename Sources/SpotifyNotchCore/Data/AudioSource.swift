import AppKit
import CoreAudio

/// Who is making sound.
///
/// Spotify is one answer among several now. The waveform follows whatever is
/// playing -- a video, a stream, a game -- and this is the part that says
/// which process that is, and which *app* the process belongs to.
public struct AudioSource: Equatable, Sendable {
    /// Core Audio's handle for the process, which is what a tap is scoped to.
    public let object: AudioObjectID
    /// The process actually producing audio. Often a helper.
    public let pid: pid_t
    /// The app it belongs to, after walking up from the helper.
    public let appPID: pid_t
    public let name: String
    public let bundleID: String

    public init(object: AudioObjectID, pid: pid_t, appPID: pid_t,
                name: String, bundleID: String) {
        self.object = object; self.pid = pid; self.appPID = appPID
        self.name = name; self.bundleID = bundleID
    }

    public var isSpotify: Bool { bundleID == SpotifyBridge.bundleID }

    /// The app's own icon, which stands in for the album cover. Not part of
    /// `Equatable`: `NSImage` is not `Sendable` and an icon does not change
    /// under an app that is still running.
    @MainActor public var icon: NSImage? {
        NSRunningApplication(processIdentifier: appPID)?.icon
    }
}

/// Watches Core Audio for processes that are producing output.
///
/// **Listeners, not a poll.** Audio starting and stopping is an event the
/// system already publishes; a timer asking "is anything playing yet" every
/// second, forever, in a process that runs for weeks, is the shape of waste
/// `docs/TRAPS.md` warns about. Core Audio calls us when the process list
/// changes and when any process starts or stops producing output.
@MainActor
public final class AudioSources: ObservableObject {
    /// The one the notch should follow, or nil for silence.
    @Published public private(set) var current: AudioSource?
    /// Everything producing audio right now, whether adopted or not. The
    /// diagnostic (`--sources`) prints this; the UI only ever sees `current`.
    @Published public private(set) var all: [AudioSource] = []

    private var watched: Set<AudioObjectID> = []
    private var listener: AudioObjectPropertyListenerBlock?
    /// When each process started producing output, for the dwell and for
    /// "most recent wins". Keyed by object, because a pid can be reused.
    private var startedAt: [AudioObjectID: Date] = [:]
    /// Re-decides once, when a source that is waiting out its dwell becomes
    /// eligible. Not a repeating timer: there is nothing to check afterwards.
    private var dwellTimer: Timer?
    /// Sources that were tapped and turned out to be silent, and when to
    /// reconsider them. See `skip`.
    private var quiet: [AudioObjectID: Date] = [:]
    /// What Spotify says about itself. Set by the owner; `true` until told
    /// otherwise, so nothing depends on the service having answered yet.
    public var spotifyPlaying = true { didSet { if spotifyPlaying != oldValue { refresh() } } }

    public init() {}

    // MARK: - The rules
    //
    // Pure, and lifted out so they can be *called* by a test rather than
    // restated in one -- the same reason `Expansion.shouldExpand` is its own
    // function.

    /// How long a new source must keep making sound before the notch adopts
    /// it. Three seconds is longer than a notification ding, a UI click or a
    /// hover-preview, and short enough that starting a video does not feel
    /// broken.
    public nonisolated static let dwell: TimeInterval = 3

    /// Apps whose audio the notch never touches.
    ///
    /// **Not a display filter -- an exclusion.** These are never chosen, so no
    /// tap is ever created for them and their audio never enters this
    /// process. A call is the one thing a visualiser has no business
    /// listening to, and "nothing is stored" is a weaker promise than "it was
    /// never read".
    ///
    /// A meeting *in a browser tab* cannot be told apart from a video in one,
    /// so browsers stay tappable. That limit is real and is written down
    /// rather than papered over.
    public nonisolated static let excluded: Set<String> = [
        "us.zoom.xos",
        "com.apple.FaceTime",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.skype.skype",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",   // Meet PWA
        "com.apple.iChat",                                           // Messages
    ]

    public nonisolated static func isExcluded(_ bundleID: String) -> Bool {
        excluded.contains(bundleID)
    }

    /// How long the chosen source may be silent before the notch gives
    /// someone else a turn.
    ///
    /// **`kAudioProcessPropertyIsRunningOutput` means "has an audio stream
    /// open", not "is making sound".** Measured: Spotify reported output
    /// continuously *through* a four-second pause, and a browser keeps its
    /// stream open for about a minute after a video is paused. So a source
    /// that has gone quiet has to be stood down by listening to it, which is
    /// the one thing that can tell the difference.
    ///
    /// Five seconds, not the two the waveform uses to fall back to synthetic
    /// bars: a quiet passage in a song should change the bars, not the app
    /// the notch is following.
    public nonisolated static let followSilence: TimeInterval = 5

    /// How long a source that turned out to be silent is passed over.
    ///
    /// **An app can hold an audio stream open without making a sound**, and
    /// Core Audio reports it as producing output either way. Claude Desktop
    /// does exactly this, which the first live run of `--sources` caught: it
    /// would have taken the notch after three seconds and sat there with a
    /// row of flat bars. So a source that delivers nothing but digital
    /// silence is put aside -- and reconsidered later, because a video that
    /// happens to open on a quiet passage is not an idle stream.
    public nonisolated static let quietRetry: TimeInterval = 20

    /// Whether a source has been playing long enough to be worth showing.
    ///
    /// Spotify is exempt: it announces itself over its own notification, it
    /// is never a stray ding, and making it wait three seconds would be a
    /// regression in the case the app was built for.
    public nonisolated static func adopted(started: Date, now: Date,
                                           isSpotify: Bool) -> Bool {
        isSpotify || now.timeIntervalSince(started) >= dwell
    }

    /// Which source the notch follows: the most recently started one that is
    /// adopted and not excluded.
    ///
    /// Most recent rather than loudest or first, because what you just
    /// started is what you just chose to watch -- and if you pause it while
    /// music is still going, the older source is still in the list and takes
    /// the notch straight back.
    /// `spotifyPlaying` is what Spotify itself says, over Apple Events.
    ///
    /// **Spotify is the one source whose state we know without listening**,
    /// so a paused Spotify is not a candidate at all -- it keeps its audio
    /// stream open while paused, and without this it outranks a video that
    /// started afterwards purely because its stream is older. That is the bug
    /// the user saw: a video kept the notch for a minute after they started
    /// their music.
    public nonisolated static func chosen(from candidates: [(AudioSource, Date)],
                                          now: Date,
                                          quiet: [AudioObjectID: Date] = [:],
                                          spotifyPlaying: Bool = true) -> AudioSource? {
        candidates
            .filter { source, started in
                !isExcluded(source.bundleID)
                    && adopted(started: started, now: now, isSpotify: source.isSpotify)
                    && !isQuiet(source, now: now, quiet: quiet)
                    && (spotifyPlaying || !source.isSpotify)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// Spotify is never passed over for being quiet *by the tap*: we know
    /// what it is playing without listening to it, so a silent tap costs it
    /// nothing. It also keeps the app working when audio recording is
    /// refused, where every source looks silent. A *paused* Spotify is
    /// excluded by `spotifyPlaying` above instead, which is a fact rather
    /// than an inference.
    nonisolated static func isQuiet(_ source: AudioSource, now: Date,
                                    quiet: [AudioObjectID: Date]) -> Bool {
        guard !source.isSpotify, let until = quiet[source.object] else { return false }
        return now < until
    }

    public func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        listener = block
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &address, DispatchQueue.main, block)
        refresh()
    }

    public func stop() {
        guard let listener else { return }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, listener)
        for object in watched { unwatch(object) }
        watched.removeAll()
        dwellTimer?.invalidate(); dwellTimer = nil
        startedAt.removeAll()
        self.listener = nil
        all = []
        current = nil
    }

    // MARK: - Reading the list

    private func refresh() {
        let objects = Self.processObjects()
        // Follow every process's running state, so starting a video is an
        // event rather than something noticed on the next tick.
        for object in objects where !watched.contains(object) { watch(object) }
        for object in watched.subtracting(objects) { unwatch(object) }
        watched = Set(objects)

        let found = objects.compactMap(Self.source)
        if found != all { all = found }

        // Remember when each one started, and forget the ones that stopped.
        let now = Date()
        let live = Set(found.map(\.object))
        startedAt = startedAt.filter { live.contains($0.key) }
        for source in found where startedAt[source.object] == nil {
            startedAt[source.object] = now
        }

        quiet = quiet.filter { live.contains($0.key) && $0.value > now }
        let candidates = found.map { ($0, startedAt[$0.object] ?? now) }
        let chosen = Self.chosen(from: candidates, now: now, quiet: quiet,
                                 spotifyPlaying: spotifyPlaying)
        if chosen != current { current = chosen }

        // If something is still waiting out its dwell, come back exactly when
        // it is eligible -- once.
        dwellTimer?.invalidate(); dwellTimer = nil
        let waiting = candidates
            .filter { source, started in
                !Self.isExcluded(source.bundleID)
                    && !Self.adopted(started: started, now: now, isSpotify: source.isSpotify)
            }
            .map { _, started in started.addingTimeInterval(Self.dwell) }
            .min()
        if let waiting {
            let timer = Timer(fire: waiting, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            dwellTimer = timer
        }
    }

    /// Told by the tap that this source delivered nothing but silence. Pass
    /// it over and pick something else.
    public func skip(_ source: AudioSource) {
        guard !source.isSpotify else { return }
        // `refresh` below re-chooses; without clearing this the same source
        // would be picked again on the strength of its old start time.
        quiet[source.object] = Date().addingTimeInterval(Self.quietRetry)
        refresh()
        // Come back when the skip expires, in case it is the only source.
        let timer = Timer(fire: Date().addingTimeInterval(Self.quietRetry + 0.1),
                          interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func watch(_ object: AudioObjectID) {
        guard let listener else { return }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, listener)
    }

    private func unwatch(_ object: AudioObjectID) {
        guard let listener else { return }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, listener)
    }

    // MARK: - Core Audio

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func processObjects() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var objects = [AudioObjectID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    /// nil unless the process is producing output *and* belongs to an app we
    /// can name. A process with no owning app -- `say`, a background daemon,
    /// an installer chiming -- has nothing to draw, so it is not a source.
    @MainActor
    static func source(_ object: AudioObjectID) -> AudioSource? {
        guard value(object, kAudioProcessPropertyIsRunningOutput) == 1 else { return nil }
        // The pid comes back in a UInt32-shaped property and has to be read
        // as signed: `pid_t(raw)` on a value that is really -1 traps.
        guard let raw = value(object, kAudioProcessPropertyPID) else { return nil }
        let pid = pid_t(bitPattern: raw)
        guard pid > 0, let owner = owningApp(pid) else { return nil }
        return AudioSource(object: object, pid: pid, appPID: owner.pid,
                           name: owner.name, bundleID: owner.bundle)
    }

    private static func value(_ object: AudioObjectID,
                              _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var out: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &out) == noErr
        else { return nil }
        return out
    }

    /// The app a process belongs to.
    ///
    /// **Browsers do not play their own audio.** Chrome and every app built on
    /// it render sound in a helper process, which is not an `NSRunningApplication`
    /// and has no name or icon of its own -- so the pid Core Audio reports
    /// would draw as a blank. Walking up the parent chain finds the app that
    /// owns it. Six hops is well past the deepest real chain and stops a
    /// pathological parent loop from hanging the main thread.
    @MainActor
    static func owningApp(_ pid: pid_t) -> (name: String, bundle: String, pid: pid_t)? {
        var current: pid_t? = pid
        for _ in 0..<6 {
            guard let p = current else { return nil }
            if let app = NSRunningApplication(processIdentifier: p),
               let bundle = app.bundleIdentifier {
                return (app.localizedName ?? bundle, bundle, p)
            }
            current = parentPID(of: p)
        }
        return nil
    }

    nonisolated static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        // launchd is everybody's ancestor and owns nothing.
        return parent > 1 ? parent : nil
    }
}

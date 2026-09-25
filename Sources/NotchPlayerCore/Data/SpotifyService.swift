import AppKit
import Combine

/// The single publisher of what Spotify is playing.
///
/// **Event-driven, not polled.** `com.spotify.client.PlaybackStateChanged`
/// arrives with the whole track payload in its `userInfo` -- name, artist,
/// album, duration, position and state -- so the ordinary case costs no Apple
/// Event at all. Verified on the target Mac on 14 Sep 2026: play and pause
/// each fired once, ~4s of uninterrupted playing fired nothing, which is why
/// the reconcile tick below exists rather than being optional.
///
/// Apple Events are needed for exactly four things: the read at launch before
/// any notification has fired, the artwork URL (the one field the
/// notification omits), the reconcile tick, and sending a command.
@MainActor
public final class SpotifyService: ObservableObject {
    @Published public private(set) var now: Now = .unknown("not read yet")
    @Published public private(set) var permission: Permission = .unknown
    /// Shuffle and repeat. Read with every full read -- launch, wake, the
    /// panel opening, and after a command -- because Spotify publishes no
    /// notification when either changes. Nil until the first read.
    @Published public private(set) var modes: Modes?

    /// The position and the instant it was true. Published so the panel can
    /// advance it locally between reads instead of asking.
    @Published public private(set) var progress: Interpolator? {
        didSet { armLoop() }
    }
    private var loop: Timer?

    private let bridge: SpotifyBridge
    private var reconcile: Timer?
    private var retry: Timer?
    private var observers: [Any] = []

    /// How often to re-read the position while playing. The notification does
    /// not fire while a track merely plays on, and may not fire on a seek.
    public static let reconcileInterval: TimeInterval = 5
    /// How long to wait after a read that failed for an unknown reason.
    public static let retryInterval: TimeInterval = 2

    /// The bridge is optional rather than defaulted to `SpotifyBridge()`
    /// because a default argument expression is evaluated nonisolated, and the
    /// bridge is main-actor bound.
    public init(bridge: SpotifyBridge? = nil) {
        self.bridge = bridge ?? SpotifyBridge()
    }

    // MARK: - Lifecycle

    public func start() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.received(note.userInfo) }
            })

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == SpotifyBridge.bundleID else { return }
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        // **Refresh, not "check whether anything changed".** Timers run on a
        // clock that stops while the machine sleeps, so a wait booked before
        // the lid closed still has its whole remaining duration to serve after
        // it opens -- the reconcile tick is late by exactly the sleep. An
        // existing observer on the right notification is not coverage for
        // this; it has to actually re-read (matchnotch TRAPS #91).
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    NSLog("NotchPlayer: woke, re-reading now")
                    self?.refresh()
                }
            })

        refresh()
    }

    public func stop() {
        reconcile?.invalidate(); reconcile = nil
        retry?.invalidate(); retry = nil
        for o in observers {
            DistributedNotificationCenter.default().removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers.removeAll()
    }

    // MARK: - Reading

    /// A full Apple Event read. Launch, wake, and whenever Spotify starts or
    /// stops.
    public func refresh() {
        guard bridge.isRunning else { return settle(.notRunning) }
        switch bridge.read() {
        case .success(let reading):
            permission = .granted
            apply(reading)
            if case .success(var read) = bridge.modes() {
                // Repeat-one is ours; it survives only while Spotify still
                // repeats underneath it.
                read.one = read.repeating && (modes?.one ?? false)
                if read != modes { modes = read }
            }
        case .failure(let failure):
            handle(failure)
        }
    }

    /// The notification path. No Apple Event unless the artwork is missing.
    private func received(_ info: [AnyHashable: Any]?) {
        guard let info else { return unresolved("notification with no userInfo") }
        switch Reading.from(notification: info) {
        case .ok(var track, let state, let position):
            // Carry a URL already fetched for this same track, so a
            // play/pause does not re-ask Spotify for something it just said.
            if let previous = now.track, previous.id == track.id {
                track.artworkURL = previous.artworkURL
            }
            if track.artworkURL == nil, track.hasArtwork { track.artworkURL = fetchArtwork() }
            settle(.track(track, state: state, position: position))
        case .malformed(let what):
            // Fall back to a full read rather than discarding the event: the
            // notification told us *something* changed, and that is still true
            // even if we could not parse it.
            NSLog("NotchPlayer: unparsable notification (%@), falling back to a read", what)
            refresh()
        }
    }

    private func apply(_ reading: Reading) {
        switch reading {
        case .ok(let track, let state, let position):
            settle(.track(track, state: state, position: position))
        case .malformed(let what):
            unresolved("malformed read: \(what)")
        }
    }

    /// One Apple Event, only when the notification left the URL out.
    private func fetchArtwork() -> URL? {
        switch bridge.artworkURL() {
        case .success(let url):
            permission = .granted
            return url
        case .failure(.denied):
            // The interesting case: the panel still has the whole track from
            // the notification, so this is a missing cover rather than a
            // broken app. The transport buttons are what actually stop
            // working, and the panel says so.
            permission = .denied
            return nil
        case .failure(let other):
            NSLog("NotchPlayer: artwork url failed: %@", String(describing: other))
            return nil
        }
    }

    private func handle(_ failure: SpotifyBridge.Failure) {
        switch failure {
        case .notRunning: settle(.notRunning)
        case .noTrack:    settle(.stopped)
        case .denied:
            permission = .denied
            // Nothing else is known yet. If a notification has already told
            // us the track, that stands -- `unresolved` leaves it alone.
            unresolved("Automation permission refused (-1743)")
        case .other(let code, let message):
            unresolved("read failed (\(code)): \(message)")
        }
    }

    // MARK: - Publishing

    private func settle(_ value: Now) {
        var value = value
        // A local file's cover lives in the file (`LocalCover`): its address
        // is the file itself, so every view that shows covers shows it.
        if case .track(var track, let state, let position) = value, track.artworkURL == nil,
           LocalCover.isLocal(track.id) {
            track.artworkURL = LocalCover.file(for: track)
            value = .track(track, state: state, position: position)
        }
        retry?.invalidate(); retry = nil
        if case let .track(_, state, position) = value {
            progress = Interpolator(position: position, stamped: .now,
                                    advancing: state == .playing)
        } else {
            progress = nil
        }
        if now != value { now = value }
        scheduleReconcile(value.isPlaying)
    }

    /// A failure that is **not** an answer.
    ///
    /// "Nothing came back" and "nothing is there" are different, and only one
    /// of them should blank the notch (TRAPS #92). So this publishes only
    /// before the first successful read; afterwards it leaves the last good
    /// value on screen and books a retry.
    private func unresolved(_ reason: String) {
        NSLog("NotchPlayer: %@", reason)
        if case .unknown = now { now = .unknown(reason) }
        // The retry clock starts now, when the answer arrived -- not when the
        // question was asked. A TTL stamped before the request turns one
        // failed read at login, before the network or Spotify is up, into a
        // long silence (TRAPS #63).
        retry?.invalidate()
        let t = Timer(timeInterval: Self.retryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        retry = t
    }

    /// A timer is only cheap if the pixels change (TRAPS #66), so this runs
    /// only while a track is actually advancing.
    ///
    /// ponytail: no reconcile while paused, so a seek made in Spotify's own
    /// window while paused leaves our position stale until playback resumes.
    /// Measured, not assumed -- a `set player position` while paused
    /// published nothing. Nobody can see it yet (the collapsed peek has no
    /// progress bar), so the upgrade path is one `refresh()` when the panel
    /// expands, which is the only moment it becomes visible.
    private func scheduleReconcile(_ playing: Bool) {
        guard playing else { reconcile?.invalidate(); reconcile = nil; return }
        guard reconcile == nil else { return }
        let t = Timer(timeInterval: Self.reconcileInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        reconcile = t
    }

    /// The cheap read: correct the drift, keep the track we already have.
    private func tick() {
        guard case let .track(track, _, _) = now else { return scheduleReconcile(false) }
        switch bridge.position() {
        case .success(let (state, position)):
            settle(.track(track, state: state, position: position))
        case .failure(let failure):
            handle(failure)
        }
    }

    // MARK: - Progress

    /// The interpolated position, or nil when nothing is playing.
    ///
    /// Read by the view; advances between reads at no cost. The duration clamp
    /// lives in `Interpolator` so a stale stamp cannot draw a bar past its end.
    public func position(at instant: SuspendingClock.Instant = .now) -> TimeInterval? {
        guard let progress, let track = now.track else { return nil }
        return progress.position(at: instant, duration: track.duration)
    }

    /// Off, all, one: Spotify's repeat, plus this app's loop for "one".
    public func setRepeat(_ mode: Modes.Repeat) {
        let wantsSpotify = mode != .off
        if modes?.repeating != wantsSpotify { send(.repeating(wantsSpotify)) }
        modes?.one = mode == .one
        armLoop()
    }

    /// How long before the end to jump back. Early enough that Spotify has not
    /// started the next song -- a Timer and an Apple Event both take some
    /// milliseconds -- late enough that almost none of the song is lost.
    nonisolated static let loopLead: TimeInterval = 0.35

    /// When to jump back, from now. Nil when there is nothing to loop.
    public nonisolated static func loopDelay(duration: TimeInterval,
                                             position: TimeInterval) -> TimeInterval? {
        guard duration > loopLead * 2 else { return nil }
        return max(0, duration - loopLead - position)
    }

    /// **Repeat one, done here.** While it is on and a song plays, one timer
    /// is armed for just before the end; when it fires, the real position is
    /// read and, if the same song really is about to end, it goes back to 0.
    /// Re-armed whenever the position changes (a seek, a pause, a new song),
    /// so it never runs on a stale guess.
    private func armLoop() {
        loop?.invalidate()
        loop = nil
        guard modes?.one == true, now.isPlaying, let track = now.track,
              let position = position(),
              let delay = Self.loopDelay(duration: track.duration, position: position)
        else { return }
        let id = track.id
        loop = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.modes?.one == true, self.now.track?.id == id else { return }
                if case .success(let read) = self.bridge.position(),
                   track.duration - read.position <= Self.loopLead * 3 {
                    self.send(.seek(0))
                } else {
                    // The guess was early (a stall, a drifted clock): try again.
                    self.armLoop()
                }
            }
        }
    }

    public func send(_ command: SpotifyBridge.Command) {
        switch bridge.send(command) {
        case .success:
            permission = .granted
            // **A seek publishes nothing.** Spotify sends `PlaybackStateChanged`
            // when the state changes, and moving the playhead is not a state
            // change -- so without this the bar springs back to where it was
            // and only corrects on the next reconcile, seconds later. Taking
            // the position we just wrote as true is not optimism: we are the
            // ones who set it, and the reconcile below still checks.
            if case .seek(let seconds) = command {
                progress = Interpolator(position: seconds, stamped: .now,
                                        advancing: now.isPlaying)
            }
            // Same reasoning: no notification comes back, and we just set it.
            if case .shuffle(let on) = command { modes?.shuffle = on }
            if case .repeating(let on) = command { modes?.repeating = on }
            // Spotify answers with a notification of its own, so there is
            // nothing to read here -- but a command that produced no
            // notification within a moment means the optimistic state and the
            // real one have diverged, so reconcile once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        case .failure(.denied):
            permission = .denied
        case .failure(let other):
            NSLog("NotchPlayer: %@ failed: %@", command.name, String(describing: other))
        }
    }
}

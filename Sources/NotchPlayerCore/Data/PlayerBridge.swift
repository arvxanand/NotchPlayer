import AppKit

/// Everything that talks to a music app (`Source`) over Apple Events.
///
/// **Scripts are compiled once and held for the life of the process.** The
/// measurement that decides this, taken on the target Mac on 14 Sep 2026:
/// shelling out to `osascript` costs **220-270ms** per read; a compiled
/// `NSAppleScript` held in-process costs **3.34ms** median over 20 runs.
/// Seventy times. Never spawn `osascript`, and never put either on a frame
/// path.
///
/// `@MainActor` on purpose. 3.34ms is only ever paid on a notification, at
/// launch, on the reconcile tick, on wake, and on a button press -- none of
/// them a frame path -- and a single actor removes any question about which
/// thread `NSAppleScript` is being driven from.
@MainActor
public final class PlayerBridge {
    /// Why a read did not produce a track. Each one means something different
    /// on screen, which is the whole point of not returning an optional.
    public enum Failure: Error, Equatable, Sendable {
        /// Spotify is not launched.
        case notRunning
        /// `errAEEventNotPermitted` (-1743). Automation refused or not yet
        /// granted. **Not** the same as "no music".
        case denied
        /// Spotify is open but has no current track.
        case noTrack
        case other(Int, String)
    }

    private var compiled: [String: NSAppleScript] = [:]

    public let source: Source

    public init(source: Source = .spotify) { self.source = source }

    public var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    /// A full read. Used at launch, on wake, and whenever the notification
    /// path has not produced anything yet.
    public func read() -> Result<Reading, Failure> {
        items(source.readScript).map { Reading.from(appleScript: $0) }
    }

    /// Position and state only.
    public func position() -> Result<(state: PlayerState, position: TimeInterval), Failure> {
        items(source.positionScript).flatMap { fields in
            guard fields.count == 2, let p = Double(fields[0]),
                  let s = PlayerState(loose: fields[1]) else {
                return .failure(.other(0, "unexpected position reply: \(fields)"))
            }
            return .success((s, p))
        }
    }

    public func modes() -> Result<Modes, Failure> {
        items(source.modesScript).flatMap { fields in
            Modes.from(fields).map { .success($0) }
                ?? .failure(.other(0, "unexpected modes reply: \(fields)"))
        }
    }

    /// The one field the playback notification does not carry.
    public func artworkURL() -> Result<URL?, Failure> {
        run(Source.artworkScript).map { descriptor in
            guard let s = descriptor.stringValue, !s.isEmpty else { return nil }
            return URL(string: s)
        }
    }

    /// Music's cover, as bytes. Nil when the song has none (the script then
    /// fails, which is an answer here and not an error).
    public func coverData() -> Data? {
        guard case .success(let descriptor) = run(Source.coverScript), !descriptor.data.isEmpty
        else { return nil }
        return descriptor.data
    }

    @discardableResult
    public func send(_ command: Command) -> Result<Void, Failure> {
        run(command.script(for: source), cache: command.cacheable).map { _ in () }
    }

    // MARK: - Plumbing

    /// Every item's `stringValue`, whatever its descriptor type.
    ///
    /// Uniform on purpose: AppleScript hands back `utxt` for text, `long` for
    /// `duration` and `doub` for `player position`, and `stringValue` is
    /// correct for all three. `int32Value` is not -- it rounds `23.69` to
    /// `24`, which would silently quantise the progress bar to whole seconds.
    private func items(_ source: String) -> Result<[String], Failure> {
        run(source).map { descriptor in
            guard descriptor.numberOfItems > 0 else {
                return [descriptor.stringValue ?? ""]
            }
            return (1...descriptor.numberOfItems).map { descriptor.atIndex($0)?.stringValue ?? "" }
        }
    }

    private func run(_ source: String, cache: Bool = true) -> Result<NSAppleEventDescriptor, Failure> {
        // Asked before the event is sent, because "Spotify is closed" is a
        // fact we can establish without an Apple Event, and the error code for
        // it (-600) is easy to confuse with a permissions problem.
        guard isRunning else { return .failure(.notRunning) }

        let script: NSAppleScript
        if cache, let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(.other(0, "could not create script"))
            }
            var compileError: NSDictionary?
            fresh.compileAndReturnError(&compileError)
            if let compileError {
                return .failure(.other(0, "compile: \(compileError)"))
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(Self.failure(from: error)) }
        return .success(result)
    }

    /// Pure, so every error code can be asserted without provoking one --
    /// which is the whole reason it is lifted out of `run` rather than being a
    /// switch inline. `nonisolated` for the same reason: a test should not
    /// have to hop actors to ask what -1743 means.
    nonisolated static func failure(from error: NSDictionary) -> Failure {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
        switch code {
        // Automation refused, or not granted yet. The user has to allow it in
        // System Settings > Privacy & Security > Automation; there is no API
        // to ask again from here.
        case -1743: return .denied
        // procNotFound / appIsDying: Spotify went away between `isRunning`
        // and the event.
        case -600, -609: return .notRunning
        // No such object: Spotify is open with nothing loaded, so
        // `current track` does not resolve.
        case -1728: return .noTrack
        default: return .other(code, message)
        }
    }
}

public enum Command: Equatable, Sendable {
    case playpause, previous, next
    /// Seconds from the start of the track. `player position` has no
    /// `access="r"` in Spotify's dictionary -- it is writable, checked
    /// before anything was built on it.
    case seek(TimeInterval)
    /// `shuffling` and `repeating` are writable booleans. **Repeat is on or
    /// off only**: the dictionary has no repeat-one, so the app can neither
    /// set it nor tell it apart from repeat-all.
    case shuffle(Bool)
    case repeating(Bool)

    /// The three that take no argument. Not `CaseIterable`, which an enum
    /// with an associated value cannot be, so the tests that sweep every
    /// command sweep this and `seek` explicitly.
    public static let simple: [Command] = [.playpause, .previous, .next]

    public var name: String {
        switch self {
        case .playpause: return "playpause"
        case .previous: return "previous"
        case .next: return "next"
        case .seek: return "seek"
        case .shuffle: return "shuffle"
        case .repeating: return "repeat"
        }
    }

    func script(for source: Source) -> String {
        let app = #"tell application ""# + source.appName + #"" to "#
        switch self {
        // Never `activate`. Bringing the app forward to talk to it clobbers
        // whatever the user was doing, and it is never necessary for a
        // command or a read.
        case .playpause: return app + "playpause"
        case .previous:  return app + "previous track"
        case .next:      return app + "next track"
        case .seek(let seconds):
            // **Three decimals and `String(format:)`, not interpolation.**
            // `"\(seconds)"` on a Double can produce `4.2e+01`, which
            // AppleScript does not parse, and a locale-aware formatter can
            // produce `42,5`, which it parses as a list. This is a
            // program's source code, so it gets C formatting.
            return app + "set player position to " + String(format: "%.3f", max(0, seconds))
        case .shuffle(let on):
            return app + (source == .spotify ? "set shuffling to " : "set shuffle enabled to ")
                + (on ? "true" : "false")
        case .repeating(let on):
            return app + (source == .spotify ? "set repeating to " + (on ? "true" : "false")
                                             : "set song repeat to " + (on ? "all" : "off"))
        }
    }

    /// Whether the compiled script is worth keeping.
    ///
    /// Every other script in this file is one fixed string compiled once
    /// and held for the life of the process. A seek's source carries its
    /// argument, so caching it would add an entry per distinct position --
    /// an unbounded dictionary of near-identical scripts in a process that
    /// runs for weeks.
    var cacheable: Bool {
        if case .seek = self { return false }
        return true
    }
}

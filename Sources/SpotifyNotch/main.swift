import AppKit
import Combine
import SpotifyNotchCore

let args = CommandLine.arguments

/// The camera-housing rect in `screencapture -R` coordinates, so
/// `tools/check_notch.sh` can ask rather than hard-code this display's
/// numbers. Prints nothing and exits 1 when there is no notched display.
if args.contains("--notchrect") {
    guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
        FileHandle.standardError.write(Data("no notched display\n".utf8))
        exit(1)
    }
    let r = NotchGeometry(screen: screen).captureRect
    print("\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))")
    exit(0)
}

/// One full Apple Event read, printed. The quickest way to see what Spotify is
/// actually saying, and the first thing to run when the panel looks wrong.
if args.contains("--read") {
    MainActor.assumeIsolated {
        let bridge = SpotifyBridge()
        print("spotify running: \(bridge.isRunning)")
        switch bridge.read() {
        case .success(.ok(let track, let state, let position)):
            print("state:    \(state.rawValue)")
            print("track:    \(track.name)")
            print("artist:   \(track.artist)")
            print("album:    \(track.album)")
            print(String(format: "duration: %.3fs", track.duration))
            print(String(format: "position: %.3fs", position))
            print("artwork:  \(track.artworkURL?.absoluteString ?? "none")")
            print("id:       \(track.id)")
        case .success(.malformed(let what)):
            print("malformed: \(what)")
        case .failure(let failure):
            print("failed: \(failure)")
        }
    }
    exit(0)
}

/// Watch the event path without any UI: every state change the service
/// publishes, stamped, for `--watch [seconds]`. This is how "does the
/// notification actually fire" gets answered, and how a track change or a seek
/// can be checked by hand.
if args.contains("--watch") {
    let seconds = args.firstIndex(of: "--watch").flatMap { i -> Double? in
        i + 1 < args.count ? Double(args[i + 1]) : nil
    } ?? 30
    setvbuf(stdout, nil, _IONBF, 0)
    MainActor.assumeIsolated {
        let service = SpotifyService()
        let start = Date()
        var bag: Any?
        bag = service.$now.sink { value in
            let t = String(format: "%6.2fs", Date().timeIntervalSince(start))
            switch value {
            case .track(let track, let state, let position):
                print(String(format: "%@  %-7@ %.1f/%.1fs  %@ - %@  art=%@",
                             t, state.rawValue as NSString, position, track.duration,
                             track.artist, track.name,
                             track.artworkURL == nil ? "none" : "yes"))
            default:
                print("\(t)  \(value)")
            }
        }
        service.start()
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                _ = bag
                print("permission: \(service.permission)")
                exit(0)
            }
        }
    }
    RunLoop.main.run()
}

/// What the app thinks is making sound: `--sources [seconds]`, printed as it
/// changes. The `--read` of the any-audio half.
if args.contains("--sources") {
    let seconds = args.firstIndex(of: "--sources").flatMap { i -> Double? in
        i + 1 < args.count ? Double(args[i + 1]) : nil
    } ?? 20
    setvbuf(stdout, nil, _IONBF, 0)
    nonisolated(unsafe) var keepAlive: [Any] = []
    MainActor.assumeIsolated {
        let sources = AudioSources()
        let start = Date()
        var bag: Any?
        bag = sources.$all.sink { list in
            let t = String(format: "%6.2fs", Date().timeIntervalSince(start))
            if list.isEmpty { print("\(t)  (silence)"); return }
            for s in list {
                let why = AudioSources.isExcluded(s.bundleID) ? "  EXCLUDED, never tapped" : ""
                print("\(t)  \(s.name)  [\(s.bundleID)]  audio pid \(s.pid)"
                      + (s.pid == s.appPID ? "" : " via helper, app pid \(s.appPID)")
                      + (s.isSpotify ? "  <- Spotify" : "") + why)
            }
        }
        // **Both cancellables have to outlive this block.** `_ = chosenBag`
        // at the end of a scope does not extend a lifetime, so the subscription
        // was torn down the moment setup finished and the tool printed one
        // line and went quiet -- which read as "the dwell never fired".
        let chosenBag = sources.$current.sink { chosen in
            let t = String(format: "%6.2fs", Date().timeIntervalSince(start))
            print("\(t)  chosen: \(chosen?.name ?? "nothing")")
        }
        keepAlive.append(chosenBag)
        if let bag { keepAlive.append(bag) }
        sources.start()
        // Poll-print as well as subscribe, so "the rule never fired" and "the
        // subscription died" cannot be confused for each other.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = String(format: "%6.2fs", Date().timeIntervalSince(start))
                print("\(t)  [poll] current = \(sources.current?.name ?? "nothing")")
            }
        }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { _ = keepAlive; exit(0) }
        }
    }
    RunLoop.main.run()
}

/// Watch the real waveform without any UI: `--bands [seconds]`.
///
/// **This is the only way to tell the tap is working.** The fallback to
/// synthetic bars is deliberately silent and deliberately convincing, so the
/// peek looks alive whether or not a single sample ever arrived. Here the two
/// are labelled.
if args.contains("--bands") {
    let seconds = args.firstIndex(of: "--bands").flatMap { i -> Double? in
        i + 1 < args.count ? Double(args[i + 1]) : nil
    } ?? 15
    setvbuf(stdout, nil, _IONBF, 0)
    nonisolated(unsafe) var held: [Any] = []
    MainActor.assumeIsolated {
        let tap = AudioTap()
        let sources = AudioSources()
        // Held in a box that outlives this scope. `_ = bag` at the end of a
        // block does not extend a lifetime -- the subscription died at setup,
        // the tool followed nothing, and it reported "no live audio" about a
        // tap it had never started.
        let following = sources.$current.sink { source in
            print("following: \(source?.name ?? "nothing")")
            tap.follow(source)
        }
        held.append(following)
        sources.start()
        let meter = Array(" ▁▂▃▄▅▆▇█")
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = String(format: "%5.1fs", Date().timeIntervalSince(start))
                guard let bands = tap.frame() else {
                    print("\(t)  no live audio  \(tap.status)")
                    return
                }
                let row = bands.map { v -> Character in
                    meter[max(0, min(meter.count - 1, Int(v * Float(meter.count - 1))))]
                }
                print("\(t)  |\(String(row))|  peak \(String(format: "%.2f", bands.max() ?? 0))")
            }
        }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                _ = held
                print("final: \(tap.status)")
                tap.stop()
                exit(0)
            }
        }
    }
    RunLoop.main.run()
}

/// Poke the running agent's frame probe: `--probe-signal start|report`.
///
/// Posting the notification from here rather than from the shell means the
/// name lives in one place (`FrameProbe`) and a typo in a script cannot
/// silently measure nothing.
if let i = args.firstIndex(of: "--probe-signal") {
    let which = i + 1 < args.count ? args[i + 1] : ""
    let name: String
    switch which {
    case "start": name = FrameProbe.startNotification
    case "report": name = FrameProbe.reportNotification
    default:
        FileHandle.standardError.write(Data("usage: --probe-signal start|report\n".utf8))
        exit(1)
    }
    DistributedNotificationCenter.default().postNotificationName(
        .init(name), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

/// `--render <subject> <path> [--side N]` -- see `Render`.
if let i = args.firstIndex(of: "--render") {
    guard i + 2 < args.count, let subject = Render.Subject(rawValue: args[i + 1]) else {
        let names = Render.Subject.allCases.map(\.rawValue).joined(separator: "|")
        FileHandle.standardError.write(Data("usage: --render <\(names)> <path> [--side N]\n".utf8))
        exit(1)
    }
    var side: CGFloat = 240
    if let j = args.firstIndex(of: "--side"), j + 1 < args.count, let v = Double(args[j + 1]) {
        side = CGFloat(v)
    }
    let path = args[i + 2]
    MainActor.assumeIsolated {
        exit(Render.png(subject, side: side, to: path) ? 0 : 1)
    }
}

/// The transport targets in screen coordinates, for `tools/hit_probe.sh`.
if args.contains("--hit-rects") {
    guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
        FileHandle.standardError.write(Data("no notched display\n".utf8))
        exit(1)
    }
    let geometry = NotchGeometry(screen: screen)
    for (name, r) in PanelView.transportRects(geometry) {
        print("\(name) \(Int(r.midX)) \(Int(r.midY)) \(Int(r.width)) \(Int(r.height))")
    }
    let p = PanelView.progressRect(geometry)
    print("progress \(Int(p.midX)) \(Int(p.midY)) \(Int(p.width)) \(Int(p.height))")
    exit(0)
}

if args.contains("--audit") {
    print(AuditReport.json())
    exit(0)
}

/// The states `tools/check_notch.sh` should capture: the ones that draw.
///
/// Emitted by the binary so the shell script cannot drift from the state list.
/// matchnotch keeps its equivalent as a hand-maintained bash array of 37
/// entries with no test behind it, which its own notes call the one real gap
/// in the scheme.
if args.contains("--check-states") {
    // Complete flag strings, not bare names: whether a state is worth
    // checking expanded as well is a decision about the UI, so it belongs
    // here rather than in a bash loop.
    for spec in PreviewData.checkSpecs { print(spec) }
    exit(0)
}

if args.contains("--list-previews") {
    for state in PreviewData.all {
        print(state.name.padding(toLength: 14, withPad: " ", startingAt: 0) + state.caption)
    }
    exit(0)
}

/// `--preview [state]`, defaulting to the first one. An unknown name exits
/// rather than rendering something plausible.
var preview: PreviewData.State?
if let i = args.firstIndex(of: "--preview") {
    let name = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1]
                                                                    : PreviewData.names[0]
    guard let state = PreviewData.named(name) else {
        FileHandle.standardError.write(Data("""
        unknown preview state \(name.debugDescription)
        known: \(PreviewData.names.joined(separator: " "))
        """.utf8))
        exit(1)
    }
    preview = state
}
/// Fills the shell white so its geometry can actually be captured. See
/// `RootView.probe`.
let probe = args.contains("--probe")

// A second instance stacks a second panel on the same notch. Bundled runs
// only, so `swift run` during development is exempt -- a CLI binary has no
// bundle identifier.
//
// **Count other processes, not all of them.** This was `count > 1` for five
// milestones, on the assumption that the asking process is in the list. It is
// not, or not yet: registration happens when `NSApplication` starts, and this
// runs before that. So a real second launch saw exactly one instance, decided
// that was fine, and put a second panel on the notch -- which is the bug the
// guard exists to prevent, surviving because nobody had launched a second one
// until milestone 7 asked. `docs/BUGS.md` #15.
if let id = Bundle.main.bundleIdentifier {
    let mine = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        .filter { $0.processIdentifier != mine }
    if !others.isEmpty {
        FileHandle.standardError.write(Data("SpotifyNotch is already running\n".utf8))
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    let controller = AppController(preview: preview, previewExpanded: args.contains("--expanded"),
                                   probe: probe, offscreen: args.contains("--offscreen"),
                                   captureServer: args.contains("--capture-server"))
    app.delegate = controller
    // NSApplication holds its delegate weakly.
    objc_setAssociatedObject(app, "spotifynotch.controller", controller, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}

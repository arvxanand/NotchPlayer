import AppKit
import Combine
import SwiftUI

/// Owns the panel and the one thing that can invalidate it wholesale: which
/// screen exists.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private let preview: PreviewData.State?
    private let previewExpanded: Bool
    private let probe: Bool
    /// Park the window off every screen. Captures still work; nothing appears
    /// in front of whoever is using the machine.
    private let offscreen: Bool
    /// Stay alive and take state names on stdin, instead of rendering one
    /// state and exiting.
    private let captureServer: Bool
    private var stage: CaptureStage?
    private let service = SpotifyService()
    private let expansion = Expansion()
    /// The live waveform. Owned here rather than by the view, because it holds
    /// system audio objects that have to be torn down when the panel goes away
    /// -- a leaked aggregate device outlives the window that wanted it.
    private let tap = AudioTap()
    private var tapFollow: AnyCancellable?
    private var menuBar: MenuBarItem?
    /// Stood down: no panel, no hover polling, no tap. Survives a relaunch,
    /// because a user who hid this to get matchnotch's notch back does not
    /// want it returning at login.
    private var hidden = UserDefaults.standard.bool(forKey: AppController.hiddenKey) {
        didSet { UserDefaults.standard.set(hidden, forKey: Self.hiddenKey) }
    }
    static let hiddenKey = "hiddenFromTheNotch"

    /// `--cycle N`: a preview that changes track every N seconds.
    private let previewCycle: Double?

    public init(preview: PreviewData.State? = nil, previewExpanded: Bool = false,
                previewCycle: Double? = nil,
                probe: Bool = false, offscreen: Bool = false,
                captureServer: Bool = false) {
        self.preview = preview
        self.previewCycle = previewCycle
        self.previewExpanded = previewExpanded
        self.probe = probe
        self.offscreen = offscreen
        self.captureServer = captureServer
        super.init()
    }

    /// The notched built-in display, or nil.
    ///
    /// **`safeAreaInsets.top > 0` is the test, not `NSScreen.main`.** `main`
    /// means "the screen with the key window", and this app deliberately never
    /// has one -- so on a two-display setup it answers with whichever screen
    /// the pointer happens to be on. An external monitor has no cutout to
    /// straddle, and with the lid shut the built-in screen is not in
    /// `NSScreen.screens` at all, which is exactly the clamshell case: no
    /// notch, draw nothing.
    static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// ponytail: appends forever, like the LaunchAgent's log did. Rotate it
    /// if it ever gets big.
    public static let logPath = NSHomeDirectory() + "/Library/Logs/SpotifyNotch.log"

    private static var stdoutIsDevNull: Bool {
        var out = stat(), null = stat()
        return fstat(STDOUT_FILENO, &out) == 0 && stat("/dev/null", &null) == 0
            && out.st_rdev == null.st_rdev && (out.st_mode & S_IFMT) == S_IFCHR
    }

    public func applicationDidFinishLaunching(_ note: Notification) {
        // **Launched by LaunchServices -- at login, by `open`, from Finder --
        // stdout is /dev/null**, and every log line with it. Only then: a
        // terminal, or `open --stdout FILE` (TRAPS #30), keeps its own.
        if preview == nil, !probe, !captureServer, Self.stdoutIsDevNull {
            freopen(Self.logPath, "a", stdout)
            freopen(Self.logPath, "a", stderr)
        }
        // Swift's print to a file is block-buffered -- so without this every
        // log line is held until the process exits, which for a resident app
        // is never.
        setvbuf(stdout, nil, _IONBF, 0)

        build()
        if preview == nil, !probe { service.start() }
        // Live runs only. A capture or a preview is driven by a script and
        // must not put anything in the user's menu bar.
        if preview == nil, !probe, !captureServer {
            menuBar = MenuBarItem(
                state: { [weak self] in
                    guard let self else { return (.unknown("no controller"), .unknown) }
                    return (service.now, service.permission)
                },
                hidden: { [weak self] in self?.hidden ?? false },
                setHidden: { [weak self] in self?.setHidden($0) })
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // The frame probe, driven from outside. A notification rather than a
        // flag, because the measurement has to be taken from the **installed
        // agent** -- a terminal build is a different scheduling class -- and
        // the agent is already running by the time anyone wants a number.
        if preview == nil, !probe, !captureServer {
            let centre = DistributedNotificationCenter.default()
            centre.addObserver(forName: .init(FrameProbe.startNotification),
                               object: nil, queue: .main) { _ in
                FrameProbe.shared.begin()
                print("probe: recording")
            }
            centre.addObserver(forName: .init(FrameProbe.reportNotification),
                               object: nil, queue: .main) { _ in
                print(FrameProbe.shared.report())
            }
        }
    }

    /// Stand down, or come back. The menu-bar item stays either way -- it is
    /// the only way back, so it is the one thing that must not be hidden.
    private func setHidden(_ value: Bool) {
        guard value != hidden else { return }
        hidden = value
        if value { standDown() } else { build() }
    }

    /// Everything `build` turns on, turned off. Not just `orderOut`: a hidden
    /// panel that is still polling the pointer and still holding an audio tap
    /// open is hidden from the user and from nobody else.
    private func standDown() {
        expansion.stop()
        tapFollow = nil
        tap.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func build() {
        guard !hidden else { return standDown() }
        guard let screen = Self.notchedScreen else {
            NSLog("SpotifyNotch: no notched display, drawing nothing")
            // Nothing is drawn in clamshell, so nothing needs listening to.
            // Holding a process tap open to feed a waveform on no screen is
            // the definition of a background app being a bad citizen.
            tap.stop()
            return
        }
        let geometry = NotchGeometry(screen: screen)
        let probing = probe
        let panel: NotchPanel
        if captureServer {
            let stage = CaptureStage(state: preview ?? PreviewData.all[0],
                                     expanded: previewExpanded)
            self.stage = stage
            panel = NotchPanel(screen: screen) {
                CaptureStageView(geometry: geometry, stage: stage)
            }
        } else if let preview {
            // The preview renders through the production view hierarchy with
            // fixed data, rather than through a parallel "preview view" that
            // could drift from the real one.
            let open = previewExpanded
            let cycle = previewCycle
            panel = NotchPanel(screen: screen) {
                CyclingPreview(every: cycle) { flipped in
                    RootView(geometry: geometry, now: flipped ? PreviewData.nextTrack : preview.now,
                             permission: preview.permission, expanded: open,
                             progress: preview.progress, holdBands: preview.bands,
                             probe: probing)
                }
            }
        } else if probing {
            panel = NotchPanel(screen: screen) {
                RootView(geometry: geometry, now: .stopped, probe: true)
            }
        } else {
            panel = NotchPanel(screen: screen) { [service, expansion, tap] in
                Live(geometry: geometry, service: service, expansion: expansion)
                    .environment(\.liveBands, tap)
            }
        }
        self.panel = panel

        // A preview is pinned open by its flag and must not be closable by
        // waving the pointer at it, or a capture races the person taking it.
        if preview == nil, !probe {
            expansion.setInteractive = { [weak panel] on in panel?.setInteractive(on) }
            expansion.hasContent = { [weak self] in
                guard let self else { return false }
                return Presentation.of(now: service.now, permission: service.permission).draws
            }
            // See `Expansion.onOpen`: the position can be stale after a seek
            // made while paused, and opening the panel is when that shows.
            expansion.onOpen = { [weak self] in self?.service.refresh() }
            expansion.start(geometry: geometry)

            // The tap follows playback rather than running all day: a stopped
            // stream delivers nothing, so an idle tap is a wakeup every 33ms
            // to analyse silence. `follow` is idempotent per pid, so the
            // several publishes a minute the service makes while playing cost
            // one comparison each.
            tapFollow = service.$now.sink { [weak self] now in
                MainActor.assumeIsolated {
                    self?.tap.follow(pid: now.isPlaying ? AudioTap.spotifyPID : nil)
                }
            }
        }

        // **Emitted so `tools/check_notch.sh` can capture *this window* rather
        // than a screen rect.** Capturing the screen at the housing's
        // coordinates measures whatever is topmost there, which over a dark
        // menu bar is all-black whether or not the panel exists -- so a screen
        // capture reports CLEAN for a panel that never launched. Asking for
        // the window by id is the difference between checking our own pixels
        // and checking a coincidence.
        if offscreen { panel.park() }

        if captureServer { listenForStates(geometry: geometry) }

        if preview != nil || probing || captureServer {
            print("window \(panel.windowNumber)")
            // In points, so `tools/pixel_check.py` can work out the backing
            // scale from the captured image rather than assuming 2x.
            let f = geometry.panelFrame()
            print("size \(Int(f.width)),\(Int(f.height))")
            let band = geometry.housingInWindow
            print("housing \(Int(band.minX)),0,\(Int(band.width)),\(Int(band.height))")
            // The drawn shape, which is taller when a preview is pinned open.
            //
            // Asks `Presentation`, not `Now`: `nopermission` has no track and
            // still draws, so keying off `now.draws` reported a 37pt shell for
            // a 185pt panel and the bounds check failed for the wrong reason.
            let draws = preview.map {
                Presentation.of(now: $0.now, permission: $0.permission).draws
            } ?? false
            let drawnHeight = previewExpanded && draws
                ? NotchGeometry.panelHeight : geometry.collapsedHeight
            print("shell \(Int(geometry.collapsedWidth)),\(Int(drawnHeight))")
        }
    }

    /// Read `<state> [expanded]` lines from stdin, redraw, answer `ready`.
    ///
    /// The reader sits on a background queue because `readLine` blocks, and
    /// the main runloop has a window to draw. Each line hops back to the main
    /// actor to touch the stage.
    private func listenForStates(geometry: NotchGeometry) {
        let stage = self.stage
        // **A watchdog, because the alternative already happened.** A capture
        // run that dies badly can leave this process holding a window the user
        // cannot close -- no dock icon, no menu bar item, no Quit. One such
        // orphan sat on the notch for an hour. The driving script's traps are
        // the first defence and they are not enough: if nothing has asked for
        // a state in this long, nobody is driving, so leave.
        armWatchdog()
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let stage, let parsed = CaptureStage.parse(trimmed) else {
                            print("unknown \(trimmed)")
                            return
                        }
                        stage.show(parsed.state, expanded: parsed.expanded,
                                   probe: parsed.probe)
                        let drawn = Presentation.of(now: parsed.state.now,
                                                    permission: parsed.state.permission).draws
                        let height = parsed.expanded && drawn && !parsed.probe
                            ? NotchGeometry.panelHeight : geometry.collapsedHeight
                        // One runloop turn for SwiftUI to lay out and draw,
                        // then say so. Animation is off, so there is nothing
                        // else to wait for.
                        self.armWatchdog()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            print("ready \(Int(geometry.collapsedWidth)),\(Int(height))")
                        }
                    }
                }
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// How long the capture server waits for a state before deciding nobody
    /// is driving it.
    public static let captureIdleTimeout: TimeInterval = 30

    private var watchdog: Timer?

    private func armWatchdog() {
        watchdog?.invalidate()
        let t = Timer(timeInterval: Self.captureIdleTimeout, repeats: false) { _ in
            DispatchQueue.main.async {
                FileHandle.standardError.write(
                    Data("capture server idle, exiting\n".utf8))
                NSApp.terminate(nil)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    /// A status item outlives the app that made it and leaves a dead icon in
    /// the menu bar until the next login.
    public func applicationWillTerminate(_ note: Notification) {
        menuBar?.remove()
        tap.stop()
    }

    /// Tear the panel down and build it again.
    ///
    /// A rebuild rather than a reposition: notch metrics differ per screen and
    /// the SwiftUI tree captured the old geometry. Display changes are rare
    /// enough that a hammer is the right tool.
    @objc private func screensChanged() {
        standDown()
        build()
    }
}


/// Binds the production view to the live service. Exists so `RootView` stays a
/// function of plain values -- which is what lets every preview state render
/// through the real hierarchy.
private struct Live: View {
    let geometry: NotchGeometry
    @ObservedObject var service: SpotifyService
    @ObservedObject var expansion: Expansion

    var body: some View {
        RootView(geometry: geometry, now: service.now, permission: service.permission,
                 expanded: expansion.expanded, progress: service.progress,
                 onScrubbing: { expansion.hold($0) },
                 send: { service.send($0) },
                 openLink: { SpotifyLinks.open($0, for: $1) })
    }
}

/// Flips between two tracks on a timer, for `--cycle`. Without one it never
/// flips, so every other preview is untouched.
struct CyclingPreview<Content: View>: View {
    let every: Double?
    @ViewBuilder let content: (Bool) -> Content
    @State private var flipped = false

    var body: some View {
        content(flipped).task {
            guard let every else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(every))
                flipped.toggle()
            }
        }
    }
}

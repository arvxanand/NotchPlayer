import AppKit
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

    public init(preview: PreviewData.State? = nil, previewExpanded: Bool = false,
                probe: Bool = false, offscreen: Bool = false,
                captureServer: Bool = false) {
        self.preview = preview
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

    public func applicationDidFinishLaunching(_ note: Notification) {
        // A LaunchAgent's StandardErrorPath is a file, and Swift's print to a
        // pipe is block-buffered -- so without this every log line is held
        // until the process exits, which for a resident agent is never.
        setvbuf(stdout, nil, _IONBF, 0)

        build()
        if preview == nil, !probe { service.start() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func build() {
        guard let screen = Self.notchedScreen else {
            NSLog("SpotifyNotch: no notched display, drawing nothing")
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
            panel = NotchPanel(screen: screen) {
                RootView(geometry: geometry, now: preview.now,
                         permission: preview.permission, expanded: open,
                         progress: preview.progress, holdBands: preview.bands,
                         probe: probing)
            }
        } else if probing {
            panel = NotchPanel(screen: screen) {
                RootView(geometry: geometry, now: .stopped, probe: true)
            }
        } else {
            panel = NotchPanel(screen: screen) { [service, expansion] in
                Live(geometry: geometry, service: service, expansion: expansion)
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

    /// Tear the panel down and build it again.
    ///
    /// A rebuild rather than a reposition: notch metrics differ per screen and
    /// the SwiftUI tree captured the old geometry. Display changes are rare
    /// enough that a hammer is the right tool.
    @objc private func screensChanged() {
        expansion.stop()
        panel?.orderOut(nil)
        panel = nil
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
                 send: { service.send($0) })
    }
}

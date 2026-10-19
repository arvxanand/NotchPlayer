import AppKit
import CoreImage
import SwiftUI

/// The playing song's cover filling the screen, tilting in 3D, for fun --
/// what Spotify's phone app does when its cover is tapped.
///
/// Opened by clicking the cover in the open notch (the title still opens the
/// album in Spotify). Closed by a click anywhere, Esc, or clicking another
/// app. The desktop shows through, dimmed.
public enum BigCover {
    /// Degrees about the x axis (top edge away or toward you) and the y axis
    /// (side edges), for a time in seconds and a pointer from -1...1 on each
    /// axis, centre 0, y down. A slow drift, plus a lean toward the pointer.
    /// Still with Reduce motion on.
    static func tilt(time: Double, pointer: CGPoint, reduced: Bool) -> (x: Double, y: Double) {
        guard !reduced else { return (0, 0) }
        let t = time / Motion.slow
        let px = Double(max(-1, min(1, pointer.x))), py = Double(max(-1, min(1, pointer.y)))
        return (sin(t * 0.45) * 7 - py * 12, cos(t * 0.35) * 9 + px * 14)
    }

    /// The colour glow behind the cover: the small cover blurred and made a
    /// little more vivid, **once per cover**. Stretched over the screen and
    /// only turned after that -- a full-screen `.blur()` redrawn every frame
    /// would keep the GPU busy for a toy.
    static func glow(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12])
            // A little darker: a pale cover would otherwise wash the whole
            // screen out and lose the white title under it.
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4,
                                                            kCIInputBrightnessKey: -0.12])
            .cropped(to: input.extent)
        guard let blurred = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: blurred, size: image.size)
    }

    /// The record's turn, in degrees, from a start that is re-based whenever
    /// play or pause flips, so the angle never jumps. Its speed eases toward
    /// `speed` while playing, in about 0.6s, and toward a stop while paused,
    /// in about a second: `v(t) = target + (v₀ - target)·e^(-kt)`.
    struct Spin: Equatable {
        /// Half a real record's 33⅓ rpm: the owner found that too busy.
        static let speed: Double = 100
        var angle0: Double = 0, time0: Double = 0, velocity0: Double = 0, playing = false

        private var target: Double { playing ? Self.speed : 0 }
        private var k: Double { playing ? 5 : 3 }

        func angle(at time: Double) -> Double {
            let dt = max(0, time - time0)
            return angle0 + target * dt + (velocity0 - target) * (1 - exp(-k * dt)) / k
        }

        func velocity(at time: Double) -> Double {
            target + (velocity0 - target) * exp(-k * max(0, time - time0))
        }

        mutating func set(playing: Bool, at time: Double) {
            guard playing != self.playing else { return }
            self = Spin(angle0: angle(at: time).truncatingRemainder(dividingBy: 360),
                        time0: time, velocity0: velocity(at: time), playing: playing)
        }
    }

    /// **30 redraws a second for the cover, not the screen's 120.** It moves
    /// slowly, so 30 looks the same and costs a quarter of the work.
    static let schedule = AnimationTimelineSchedule(minimumInterval: 1.0 / 30)
    /// The glow turns 3° a second and is blurred, so 10 steps a second are
    /// invisible -- and it is the one layer the size of the screen.
    static let glowSchedule = AnimationTimelineSchedule(minimumInterval: 1.0 / 10)

    /// The cover's side on `screen`.
    static func side(on screen: CGRect) -> CGFloat { min(screen.height * 0.6, 640) }

    /// The small window the moving part lives in: the cover, the record slid
    /// out beside it, the title, and room for the tilt -- or, with the lyrics
    /// on, the cover and the lyrics beside it. Sized for the lyrics either
    /// way, so turning them on moves nothing but the drawing.
    static func stageSize(on screen: CGRect) -> CGSize {
        let side = side(on: screen)
        return CGSize(width: min(screen.width * 0.92, side * 2.3), height: min(screen.height, side * 1.5))
    }

    /// The Lyrics button's height: the minimum target.
    static let pillHeight = NotchGeometry.minimumHitHeight

    /// Remembered between opens; both windows read it.
    static let lyricsKey = "bigCoverLyrics"
    /// Between the cover and the lyrics.
    static func lyricsGap(on screen: CGRect) -> CGFloat { side(on: screen) * 0.1 }
    /// What the lyrics get beside the cover, inside the stage, with the
    /// tilt's room (`margin`) kept clear at the edge.
    static func lyricsWidth(on screen: CGRect) -> CGFloat {
        stageSize(on: screen).width - side(on: screen) - lyricsGap(on: screen) - 2 * margin(on: screen)
    }
    static func margin(on screen: CGRect) -> CGFloat { side(on: screen) * 0.05 }

    /// About seven lines on the cover's height, the lit one a little above
    /// the middle so more of what's coming shows than what's gone.
    static func lyricsStyle(on screen: CGRect) -> LyricsLines.Style {
        let side = side(on: screen)
        return LyricsLines.Style(font: Type.label((side * 0.05).rounded(), weight: .bold),
                                 spacing: (side * 0.03).rounded(), anchor: 0.38,
                                 note: Type.label((side * 0.035).rounded(), weight: .semibold))
    }

    /// Where the pointer is on `screen`, as `tilt` wants it.
    static func pointer(_ location: CGPoint, on screen: CGRect) -> CGPoint {
        CGPoint(x: (location.x - screen.midX) / (screen.width / 2),
                y: (screen.midY - location.y) / (screen.height / 2))
    }
}

/// The big cover's two windows.
///
/// **Two, because one screen-sized window that moves is costly.** Anything
/// that changes in a window has the window server repaint that window, and a
/// single full-screen one made every frame of the turning cover a full-screen
/// repaint (measured: ~13% more window-server CPU, against ~4% for the same
/// window standing still). So the full-screen backdrop -- the glow and the dim,
/// which barely change -- is this window, and the cover, the record and the
/// title live in a small child window over the middle, the only one redrawn
/// every frame.
///
/// The backdrop becomes key, unlike the notch, so Esc reaches it; a
/// non-activating panel can, without bringing this app forward. A click on it,
/// Esc, or another app taking the keyboard closes both. The stage takes no
/// clicks, so a click on the cover lands on the backdrop and closes it too.
final class CoverWindow: NSPanel {
    var onDismiss: (() -> Void)?
    private let stage: NSPanel

    init<Backdrop: View, Stage: View>(screen: NSScreen, @ViewBuilder backdrop: () -> Backdrop,
                                      @ViewBuilder stage content: () -> Stage) {
        let size = BigCover.stageSize(on: screen.frame)
        let stageFrame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                width: size.width, height: size.height)
        stage = NSPanel(contentRect: stageFrame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // One above the notch panel's, so the notch sits under the dimming.
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        for window in [self, stage] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovable = false
            window.hidesOnDeactivate = false
            window.level = level
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        }
        stage.ignoresMouseEvents = true
        let host = FirstMouseHostingView(rootView: backdrop())
        host.autoresizingMask = [.width, .height]
        contentView = host
        stage.contentView = NSHostingView(rootView: content())
        setFrame(screen.frame, display: false)
        stage.setFrame(stageFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        alphaValue = 0
        stage.alphaValue = 0
        orderFrontRegardless()
        addChildWindow(stage, ordered: .above)
        makeKey()
        fade(to: 1)
    }

    func dismiss() {
        guard let onDismiss else { return }
        self.onDismiss = nil
        // Held until the fade ends: the owner drops it straight away.
        fade(to: 0) { [self] in
            removeChildWindow(stage)
            stage.orderOut(nil)
            orderOut(nil)
        }
        onDismiss()
    }

    private func fade(to alpha: CGFloat, then done: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2 * Motion.slow
            animator().alphaValue = alpha
            stage.animator().alphaValue = alpha
        }, completionHandler: { MainActor.assumeIsolated { done?() } })
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss() } else { super.keyDown(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}

/// The full-screen layer: the glow and the dim. Takes the closing click.
struct BigCoverBackdrop: View {
    @ObservedObject var players: Players
    let screen: CGRect
    let close: () -> Void

    @ObservedObject private var memory = ArtMemory.shared
    @State private var glow: NSImage?
    @State private var glowFor: URL?
    @AppStorage(BigCover.lyricsKey) private var lyrics = false

    var body: some View {
        let url = players.current.now.track?.artworkURL
        let glowing = glowFor == url && glow != nil
        ZStack {
            if let glow, glowing { swirl(glow).id(url).transition(.opacity) }
            // A little lighter over the glow, so its colour comes through;
            // darker under the lyrics, so the desktop does not read through
            // the dimmed lines.
            Color.black.opacity(lyrics ? 0.72 : glowing ? 0.45 : 0.55)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        // After the tap, so a click on it is not also a click on the dim.
        .overlay(alignment: .bottomTrailing) { lyricsButton }
        .animation(.easeInOut(duration: 0.35 * Motion.slow), value: url)
        .animation(.easeInOut(duration: 0.35 * Motion.slow), value: lyrics)
        // The small cover, usually already loaded for the notch: blurred once
        // when it is here, whichever comes first.
        .onChange(of: memory.image(for: url) != nil, initial: true) { _, loaded in
            guard loaded, let url, glowFor != url, let small = memory.image(for: url),
                  let image = BigCover.glow(small) else { return }
            glow = image; glowFor = url
        }
        .onAppear { url.map(memory.load) }
    }

    /// Here rather than on the stage, which takes no clicks; in the corner,
    /// clear of the stage. A plain `Button`: it acts on mouse-up (TRAPS #37).
    private var lyricsButton: some View {
        Button { lyrics.toggle() } label: {
            Label("Lyrics", systemImage: "music.mic")
                .font(Type.label(14, weight: .semibold))
                .foregroundStyle(lyrics ? Palette.background : Palette.primary)
                .padding(.horizontal, 18)
                .frame(height: BigCover.pillHeight)
                .background(Capsule().fill(lyrics ? Palette.primary : Palette.pill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(28)
        .accessibilityLabel(lyrics ? "Hide the lyrics" : "Show the lyrics")
    }

    /// The glow stretched over the screen, turning slowly. One layer: a
    /// second, counter-turning copy doubled the full-screen fill for little.
    /// Still with Reduce motion.
    private func swirl(_ image: NSImage) -> some View {
        let size = max(screen.width, screen.height) * 1.6
        return TimelineView(BigCover.glowSchedule) { context in
            let t = Motion.reduced ? 0 : context.date.timeIntervalSinceReferenceDate / Motion.slow
            Image(nsImage: image).resizable().interpolation(.medium)
                .frame(width: size, height: size)
                .rotationEffect(.degrees((t * 3).truncatingRemainder(dividingBy: 360)))
                .opacity(0.85)
        }
        .frame(width: screen.width, height: screen.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// The small, moving layer: the cover, the record, the song under them.
struct BigCoverStage: View {
    @ObservedObject var players: Players
    let screen: CGRect

    @ObservedObject private var memory = ArtMemory.shared
    @State private var big: NSImage?
    @State private var bigFor: URL?
    @State private var spin = BigCover.Spin()
    /// The record slides out from behind the cover just after opening.
    @State private var out = Motion.reduced
    @AppStorage(BigCover.lyricsKey) private var lyrics = false
    @ObservedObject private var store = LyricsStore.shared

    var body: some View {
        let track = players.current.now.track
        let url = track?.artworkURL
        let showing = lyrics && track != nil
        HStack(alignment: .top, spacing: BigCover.lyricsGap(on: screen)) {
            VStack(spacing: 18) {
                stage(url, source: track?.source ?? .spotify, tucked: showing)
                if let track {
                    VStack(spacing: 3) {
                        Text(track.name).font(Type.label(15, weight: .semibold)).foregroundStyle(Palette.primary)
                        Text(track.artist).font(Type.label(13)).foregroundStyle(Palette.secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: side)
                }
            }
            if showing, let track {
                // Not clickable: the stage takes no clicks, so a click here
                // closes the cover like anywhere else.
                LyricsWords(content: store.content(for: track), progress: players.current.progress,
                            duration: track.duration, live: playing,
                            style: BigCover.lyricsStyle(on: screen), seek: nil)
                    .frame(width: BigCover.lyricsWidth(on: screen), height: side)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35 * Motion.slow), value: url)
        .animation(Motion.reduced ? .easeInOut(duration: 0.2) : Motion.spring, value: showing)
        .task(id: showing ? track?.id : nil) {
            if showing, let track { store.load(track) }
        }
        .onAppear {
            spin.set(playing: playing, at: Date.timeIntervalSinceReferenceDate)
            guard !out else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Motion.slow) {
                withAnimation(Motion.spring) { out = true }
            }
        }
        .onChange(of: playing) { _, now in spin.set(playing: now, at: Date.timeIntervalSinceReferenceDate) }
        .task(id: url) {
            // The small cover shows at once; the sharp one replaces it.
            guard let url, let bytes = await ArtworkCache.shared.data(for: url, original: true),
                  let image = NSImage(data: bytes) else { return }
            big = image; bigFor = url
        }
    }

    private var side: CGFloat { BigCover.side(on: screen) }

    private var playing: Bool {
        if case .track(_, .playing, _) = players.current.now { return true }
        return false
    }

    /// The sharp cover once it is here, the small one until then.
    private func image(_ url: URL?) -> NSImage? {
        (bigFor == url ? big : nil) ?? memory.image(for: url)
    }

    private func cover(_ url: URL?, source: Source) -> some View {
        ZStack {
            Palette.wash
            if let image = image(url) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                SourceMark(source).frame(width: side * 0.4, height: side * 0.4)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .id(url)
        .transition(.opacity)
    }

    /// The cover and the record behind it, tilting together. Redrawn every
    /// frame: the time and the pointer are read directly, since hover events
    /// are unreliable in this app's windows (TRAPS #40). The pair shifts left
    /// as the record slides out, so the two stay centred.
    /// `tucked`: the record stays behind the cover, the lyrics need the room.
    private func stage(_ url: URL?, source: Source, tucked: Bool) -> some View {
        let slide = out && !tucked ? side * 0.45 : 0
        return TimelineView(BigCover.schedule) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let angle = BigCover.tilt(time: now, pointer: BigCover.pointer(NSEvent.mouseLocation, on: screen),
                                      reduced: Motion.reduced)
            let shine = min(0.2, (abs(angle.x) + abs(angle.y)) / 60)
            ZStack {
                Vinyl(diameter: side * 0.94, label: image(url),
                      turn: Motion.reduced ? 0 : spin.angle(at: now))
                    .offset(x: slide)
                cover(url, source: source)
                    .overlay {
                        LinearGradient(colors: [.white.opacity(shine), .white.opacity(0)],
                                       startPoint: UnitPoint(x: 0.5 - angle.y / 30, y: 0.5 + angle.x / 30 - 0.5),
                                       endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .allowsHitTesting(false)
                    }
            }
            .offset(x: -slide / 2)
            .rotation3DEffect(.degrees(angle.x), axis: (1, 0, 0), perspective: 0.5)
            .rotation3DEffect(.degrees(angle.y), axis: (0, 1, 0), perspective: 0.5)
        }
    }
}

/// A black record with the cover as its label. Only the record turns; the
/// light on it stays where it is, as it does on a real one.
struct Vinyl: View {
    let diameter: CGFloat
    let label: NSImage?
    /// Degrees.
    let turn: Double

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.04))
            Grooves().drawingGroup()
            Group {
                if let label { Image(nsImage: label).resizable().interpolation(.high).scaledToFill() }
                else { Color(white: 0.2) }
            }
            .frame(width: diameter * 0.36, height: diameter * 0.36)
            .clipShape(Circle())
            Circle().fill(Color(white: 0.7)).frame(width: diameter * 0.025, height: diameter * 0.025)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(turn))
        .overlay {
            AngularGradient(colors: [.white.opacity(0), .white.opacity(0.12), .white.opacity(0),
                                     .white.opacity(0.07), .white.opacity(0)],
                            center: .center)
                .clipShape(Circle())
                .allowsHitTesting(false)
        }
    }
}

/// The grooves: rings in two near-blacks. No inputs, so SwiftUI draws them
/// once and only the turn changes per frame.
private struct Grooves: View {
    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 * 0.97
            var radius = outer * 0.4, odd = false
            while radius < outer {
                let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                  width: radius * 2, height: radius * 2))
                context.stroke(ring, with: .color(Color(white: odd ? 0.09 : 0.06)), lineWidth: 1)
                radius += 2; odd.toggle()
            }
        }
    }
}

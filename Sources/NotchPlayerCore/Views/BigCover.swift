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
        return (sin(t * 0.9) * 7 - py * 12, cos(t * 0.7) * 9 + px * 14)
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

    /// Where the pointer is on `screen`, as `tilt` wants it.
    static func pointer(_ location: CGPoint, on screen: CGRect) -> CGPoint {
        CGPoint(x: (location.x - screen.midX) / (screen.width / 2),
                y: (screen.midY - location.y) / (screen.height / 2))
    }
}

/// A borderless window over the whole screen, above the notch panel.
///
/// Becomes key, unlike the notch, so Esc reaches it; a non-activating panel
/// can, without bringing this app forward. Losing key (another app clicked)
/// closes it too.
final class CoverWindow: NSPanel {
    var onDismiss: (() -> Void)?

    init<Content: View>(screen: NSScreen, @ViewBuilder content: () -> Content) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // One above the notch panel's, so the notch sits under the dimming.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = FirstMouseHostingView(rootView: content())
        host.autoresizingMask = [.width, .height]
        contentView = host
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2 * Motion.slow; animator().alphaValue = 1 }
    }

    func dismiss() {
        guard let onDismiss else { return }
        self.onDismiss = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2 * Motion.slow; animator().alphaValue = 0 },
                                             completionHandler: { [self] in
            // Held until the fade ends: the owner drops it straight away.
            MainActor.assumeIsolated { orderOut(nil) }
        })
        onDismiss()
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

/// What the window draws: the dim, the cover, the song under it.
struct BigCoverView: View {
    @ObservedObject var players: Players
    let screen: CGRect
    let close: () -> Void

    @ObservedObject private var memory = ArtMemory.shared
    @State private var big: NSImage?
    @State private var bigFor: URL?
    @State private var glow: NSImage?
    @State private var glowFor: URL?

    var body: some View {
        let track = players.current.now.track
        let url = track?.artworkURL
        let glowing = glowFor == url && glow != nil
        ZStack {
            if let glow, glowing { swirl(glow).id(url).transition(.opacity) }
            // A little lighter over the glow, so its colour comes through.
            Color.black.opacity(glowing ? 0.45 : 0.55)
            VStack(spacing: 18) {
                tilting(cover(url, source: track?.source ?? .spotify))
                if let track {
                    VStack(spacing: 3) {
                        Text(track.name).font(Type.label(15, weight: .semibold)).foregroundStyle(Palette.primary)
                        Text(track.artist).font(Type.label(13)).foregroundStyle(Palette.secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: side)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .animation(.easeInOut(duration: 0.35 * Motion.slow), value: url)
        .task(id: url) {
            guard let url else { return }
            // The glow from the small cover, usually already loaded for the
            // notch; the sharp cover then replaces the small one.
            if let small = memory.image(for: url) { setGlow(BigCover.glow(small), for: url) }
            guard let bytes = await ArtworkCache.shared.data(for: url, original: true),
                  let image = NSImage(data: bytes) else { return }
            big = image; bigFor = url
            if glowFor != url { setGlow(BigCover.glow(image), for: url) }
        }
    }

    private func setGlow(_ image: NSImage?, for url: URL) {
        guard let image else { return }
        glow = image; glowFor = url
    }

    /// Two stretched copies of the glow turning opposite ways, so its colours
    /// drift through each other. Still with Reduce motion.
    private func swirl(_ image: NSImage) -> some View {
        let size = max(screen.width, screen.height) * 1.6
        return TimelineView(.animation) { context in
            let t = Motion.reduced ? 0 : context.date.timeIntervalSinceReferenceDate / Motion.slow
            ZStack {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees((t * 8).truncatingRemainder(dividingBy: 360)))
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .scaleEffect(1.3)
                    .rotationEffect(.degrees((-t * 5).truncatingRemainder(dividingBy: 360)))
                    .opacity(0.5)
            }
            .opacity(0.85)
        }
        .frame(width: screen.width, height: screen.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private var side: CGFloat { min(screen.height * 0.6, 640) }

    private func cover(_ url: URL?, source: Source) -> some View {
        let image = bigFor == url ? big : nil
        return ZStack {
            Palette.wash
            if let image = image ?? memory.image(for: url) {
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

    /// Redrawn every frame: the time and the pointer, read directly, since
    /// hover events are unreliable in this app's windows (TRAPS #40).
    private func tilting(_ content: some View) -> some View {
        TimelineView(.animation) { context in
            let angle = BigCover.tilt(time: context.date.timeIntervalSinceReferenceDate,
                                      pointer: BigCover.pointer(NSEvent.mouseLocation, on: screen),
                                      reduced: Motion.reduced)
            let shine = min(0.2, (abs(angle.x) + abs(angle.y)) / 60)
            content
                .overlay {
                    LinearGradient(colors: [.white.opacity(shine), .white.opacity(0)],
                                   startPoint: UnitPoint(x: 0.5 - angle.y / 30, y: 0.5 + angle.x / 30 - 0.5),
                                   endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.45), radius: 30, y: 24)
                .rotation3DEffect(.degrees(angle.x), axis: (1, 0, 0), perspective: 0.5)
                .rotation3DEffect(.degrees(angle.y), axis: (0, 1, 0), perspective: 0.5)
        }
    }
}

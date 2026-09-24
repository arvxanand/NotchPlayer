import SwiftUI

/// What the menu-bar item opens.
///
/// **A panel, not a menu.** The first version of this was an `NSMenu` with
/// three lines of text, which is the right answer for a utility that has
/// nothing to show -- and the wrong one here, because this app's whole subject
/// is an album cover. A menu of words about a picture is a worse menu.
///
/// Black, like the notch panel and like matchnotch's popover: the surface is
/// the app's identity, and a vibrancy-backed sheet with system text would look
/// like a different program's settings window.
public struct MenuPanel: View {
    let track: Track?
    let playing: Bool
    let subtitle: String
    let hidden: Bool
    let toggleHidden: () -> Void
    /// State, so the box flips in place. Rebuilding the popover's content
    /// instead moved the whole popover 26pt sideways under the pointer.
    @State private var login: Grant
    /// Does the change and answers what the state is now.
    let toggleLogin: () -> Grant
    /// The panel's + pressing Spotify's own, the same way.
    @State private var plus: Grant
    let togglePlus: () -> Grant
    /// A newer version, when there is one (`Updater`).
    let update: String?
    let installUpdate: () -> Void
    /// Nil hides the switch: a Homebrew install or a local build doesn't check.
    @State private var checkUpdates: Bool?
    let toggleUpdates: () -> Bool
    let version: String
    let quit: () -> Void
    /// Read by `PanelView` too, which redraws the line when it changes.
    @AppStorage(Accent.enabledKey) private var coverAccent = true

    /// A switch macOS has a say in: launch at login (`SMAppService`), and the
    /// + pressing Spotify's button (Accessibility).
    public enum Grant: Sendable { case off, on, needsApproval }

    /// Behind the gear. `rawValue` is the side a page sits on: settings is to
    /// the right of the glance, so it arrives from the right.
    public enum Page: Int, Sendable { case main, settings }
    /// A fresh panel is built on every open (`MenuBarItem.rebuild`), so the
    /// popover always opens on `.main`.
    @State private var page: Page
    /// The popover animates itself in -- see `MenuBarItem`, which turns
    /// AppKit's own animation off.
    @State private var shown = false

    public init(track: Track?, playing: Bool, subtitle: String, hidden: Bool,
                toggleHidden: @escaping () -> Void, login: Grant,
                toggleLogin: @escaping () -> Grant,
                plus: Grant = .off, togglePlus: @escaping () -> Grant = { .off },
                update: String? = nil, installUpdate: @escaping () -> Void = {},
                checkUpdates: Bool? = nil, toggleUpdates: @escaping () -> Bool = { false },
                version: String = "",
                quit: @escaping () -> Void,
                page: Page = .main, animateIn: Bool = true) {
        self.track = track; self.playing = playing; self.subtitle = subtitle
        self.hidden = hidden; self.toggleHidden = toggleHidden
        _login = State(initialValue: login); self.toggleLogin = toggleLogin; self.quit = quit
        _plus = State(initialValue: plus); self.togglePlus = togglePlus
        self.update = update; self.installUpdate = installUpdate
        _checkUpdates = State(initialValue: checkUpdates); self.toggleUpdates = toggleUpdates
        self.version = version
        _page = State(initialValue: page)
        // An offscreen render never appears, so it would stay invisible.
        _shown = State(initialValue: !animateIn)
    }

    public static let width: CGFloat = 268
    /// Fixed, so the window cannot resize under the pointer when a track
    /// changes while the panel is open. matchnotch's popover states its height
    /// for the same reason.
    ///
    /// **Both pages are this tall**, which is what keeps the page change
    /// smooth: matchnotch let its pages have their own heights and `NSPopover`
    /// resized its window on every frame of the slide, which wobbled.
    /// `MenuPanelTests` fails if either page outgrows it -- the pages are
    /// `.clipped()`, so an extra row would not scroll, it would vanish.
    /// 200 since the updater: settings has four rows, and the main page's
    /// spare space holds the version footer, or the update row instead.
    public static let height: CGFloat = 200
    static let margin: CGFloat = 14
    static let coverSide: CGFloat = 56

    /// How far a page travels when it changes. **14pt, not the panel's width**
    /// -- matchnotch's hardest-won number. A full-width push is ~16pt a frame
    /// at 60Hz and reads as stepping however it is built; 14pt over 0.22s is
    /// about 1pt a frame, which cannot judder. System Settings and Control
    /// Center move a few points and cross-fade for the same reason.
    static let travel: CGFloat = 14
    /// An ease, not a spring: over 14pt a spring's fast opening frames are all
    /// it adds, and that is where matchnotch's judder was.
    static var pageMotion: Animation {
        Motion.reduced ? .easeInOut(duration: 0.16) : .easeOut(duration: 0.22)
    }

    /// **Both pages always exist, stacked; only opacity and a 14pt offset
    /// animate.** matchnotch's third attempt, after `.transition(.move)` read
    /// as janky: a transition inserts and removes views, so every frame of the
    /// slide re-ran layout, and a second tap mid-flight drew two copies of the
    /// incoming page. An offset is a transform -- nothing is laid out again,
    /// and a new tap just retargets it.
    public var body: some View {
        ZStack(alignment: .topLeading) {
            pageView(main, .main)
            pageView(settings, .settings)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .clipped()
        .background(Palette.background)
        .scaleEffect(shown ? 1 : 0.97, anchor: .top)
        .opacity(shown ? 1 : 0)
        // Scoped to `shown`, not `withAnimation`: as a root transaction it
        // would start the page offset springing too (matchnotch TRAPS #52).
        .animation(Motion.standard, value: shown)
        .onAppear { shown = true }
    }

    /// Faded, nudged, and inert when it is not the page showing. Without
    /// `allowsHitTesting`, the invisible page -- laid out on top -- would
    /// swallow the clicks meant for the visible one.
    private func pageView(_ content: some View, _ which: Page) -> some View {
        let on = page == which
        return content
            .frame(width: Self.width, height: Self.height, alignment: .topLeading)
            .opacity(on ? 1 : 0)
            .modifier(PageOffset(x: CGFloat(which.rawValue - page.rawValue) * Self.travel,
                                 page: which))
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
    }

    private func go(_ to: Page) {
        withAnimation(Self.pageMotion) { page = to }
    }

    var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            if let update {
                divider
                Row(title: "Update to v\(update)", symbol: "arrow.down.circle", action: installUpdate)
            }
            divider
            Row(title: hidden ? "Show in the Notch" : "Hide from the Notch",
                symbol: hidden ? "eye" : "eye.slash", action: toggleHidden)
            divider
            Row(title: "Quit NotchPlayer", symbol: "power", action: quit)
            // The update row takes its room.
            if update == nil { footer }
        }
        .overlay(alignment: .topTrailing) {
            Glyph(symbol: "gearshape", label: "Settings") { go(.settings) }
                .padding(.top, 4).padding(.trailing, 4)
        }
    }

    /// Switches, not checkboxes: each is a setting that stays, and a switch
    /// says which way it is at a glance.
    var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Glyph(symbol: "chevron.left", label: "Back") { go(.main) }
                Text("Settings")
                    .font(Type.label(13, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .frame(height: 44)
            divider
            loginRow
            divider
            SwitchRow(title: "Cover colour on the progress bar", isOn: coverAccent) {
                coverAccent.toggle()
            }
            divider
            plusRow
            if let on = checkUpdates {
                divider
                SwitchRow(title: "Check for updates", isOn: on) { checkUpdates = toggleUpdates() }
            }
            Spacer(minLength: 0)
        }
    }

    static let privacy = URL(string: "https://github.com/arvxanand/NotchPlayer#what-audio-recording-actually-records")!

    /// Small and grey: which version this is, and what the app does with
    /// what it hears. The whole row is the link, so the target is full height.
    private var footer: some View {
        Footer(version: version)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // A 56pt black square would read as a hole in the panel while the
            // cover is still downloading, so the slot is washed rather than
            // black here. In the peek it stays black -- see `ArtworkView.fill`.
            ArtworkView(url: track?.artworkURL, side: Self.coverSide, corner: 8,
                        fill: Palette.wash)
            VStack(alignment: .leading, spacing: 3) {
                Text(track?.name ?? "Nothing playing")
                    .font(Type.label(13, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1).truncationMode(.tail)
                if let artist = track?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(Type.label(11))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                state
            }
            // Clear of the gear in the corner, so a long title stops short of it.
            .padding(.trailing, 18)
            Spacer(minLength: 0)
        }
        .padding(Self.margin)
    }

    /// The one coloured thing in the panel, and only while the music is
    /// actually running -- the same rule the waveform follows. A dot that is
    /// green whatever is happening stops meaning anything.
    private var state: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(playing ? Palette.spotify : Palette.track)
                .frame(width: 6, height: 6)
            Text(subtitle)
                .font(Type.label(11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    /// **Needs approval** is its own state, not a quiet "off". The user can
    /// switch the item off in System Settings, and after that `register()`
    /// cannot turn it back on -- only System Settings can. A switch that stays
    /// off when clicked would look broken, so the row says where to go.
    @ViewBuilder
    private var loginRow: some View {
        let flip = { login = toggleLogin() }
        if login == .needsApproval {
            Row(title: "Allow in Login Items\u{2026}", symbol: "exclamationmark.triangle",
                action: flip)
        } else {
            SwitchRow(title: "Launch at login", isOn: login == .on, action: flip)
        }
    }

    /// Off, the panel's + opens the song; on, it presses Spotify's own +.
    /// Flipping it on asks macOS for Accessibility, and until that is given
    /// the row says where to go -- the + meanwhile still opens the song.
    @ViewBuilder
    private var plusRow: some View {
        let flip = { plus = togglePlus() }
        if plus == .needsApproval {
            Row(title: "Allow in Accessibility\u{2026}", symbol: "exclamationmark.triangle",
                action: flip)
        } else {
            SwitchRow(title: "Save with Spotify's +", isOn: plus == .on, action: flip)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 0.5)
    }

    /// Dim until pointed at, like every row in matchnotch's popover. Quit is
    /// the one destructive thing here and a red row would be the loudest pixel
    /// in a window whose job is to be glanced at.
    private struct Row: View {
        let title: String
        let symbol: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(title).font(Type.label(11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
            .padding(.horizontal, MenuPanel.margin)
            .frame(height: 38)
            .background(hovering ? Palette.wash : .clear)
            // Last, after every sizing modifier, or the live area is whatever
            // the content happens to cover -- TRAPS #21, which every hit
            // target in matchnotch had backwards.
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
        }
    }

    /// A drawn switch, as matchnotch's `NotchSwitch` is: an AppKit `Toggle`
    /// draws itself inactive-grey whenever its window is not key, on or off.
    /// **Spotify green when on**, the user's call (22 Sep 2026), like
    /// matchnotch's; off is the grey track with a white knob.
    struct SwitchRow: View {
        let title: String
        let isOn: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 9) {
                Text(title).font(Type.label(11))
                    .foregroundStyle(hovering || isOn ? Palette.primary : Palette.secondary)
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Palette.spotify : Palette.track)
                    Circle().fill(Palette.primary)
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 2)
                }
                .frame(width: 26, height: 14)
                // Scoped to the switch's own value (matchnotch TRAPS #52).
                .animation(Motion.standard, value: isOn)
            }
            .padding(.horizontal, MenuPanel.margin)
            .frame(height: 38)
            .background(hovering ? Palette.wash : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "on" : "off")
            .accessibilityAddTraits(.isButton)
        }
    }

    private struct Footer: View {
        let version: String
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 4) {
                Text("NotchPlayer \(version)")
                Text("\u{00B7}")
                Text("Privacy").underline(hovering)
            }
            .font(Type.label(10))
            .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { NSWorkspace.shared.open(MenuPanel.privacy) }
            .accessibilityElement()
            .accessibilityLabel("NotchPlayer \(version), privacy")
            .accessibilityAddTraits(.isLink)
        }
    }

    /// A glyph with a 30pt target: the gear, and the way back.
    struct Glyph: View {
        let symbol: String
        let label: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Palette.primary : Palette.secondary)
                .frame(width: 30, height: 30)
                // After the frame, or only the glyph's own 12pt is live --
                // matchnotch's "the gear doesn't work" bug (TRAPS #21 here).
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// The page offset, as a `GeometryEffect` so the slide can be measured.
///
/// Ported from matchnotch, where three attempts at a smooth slide were made
/// from theory and one made it worse; this ended it. `animatableData` is set
/// once per frame the animation computes, so it reports how far the page
/// jumped between drawn frames. Off unless `NOTCHPLAYER_PAGE_PROBE` is set.
struct PageOffset: GeometryEffect {
    var x: CGFloat
    /// Only one page is recorded: both animate together, and two into one
    /// series would print the gaps between different pages as "steps".
    var page: MenuPanel.Page

    var animatableData: CGFloat {
        get { x }
        set {
            x = newValue
            MainActor.assumeIsolated {
                if PageProbe.enabled, page == .settings { PageProbe.tick(newValue) }
            }
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

@MainActor
enum PageProbe {
    static let enabled = ProcessInfo.processInfo.environment["NOTCHPLAYER_PAGE_PROBE"] != nil
    private static var times: [CFTimeInterval] = []
    private static var values: [CGFloat] = []
    private static var flush: Task<Void, Never>?

    static func tick(_ value: CGFloat) {
        // Only when it moved: the setter also runs on plain re-renders.
        if let last = values.last, last == value { return }
        times.append(CACurrentMediaTime())
        values.append(value)
        flush?.cancel()
        flush = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            report()
        }
    }

    private static func report() {
        defer { times.removeAll(); values.removeAll() }
        guard times.count > 2 else { return }
        let gaps = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }
        let steps = zip(values.dropFirst(), values).map { abs($0 - $1) }
        print(String(format: "page probe: %d frames, %.0fms, moved %.0fpt, biggest step %.1fpt, worst gap %.0fms",
                     values.count, (times.last! - times.first!) * 1000,
                     abs(values.last! - values.first!), steps.max() ?? 0, gaps.max() ?? 0))
    }
}

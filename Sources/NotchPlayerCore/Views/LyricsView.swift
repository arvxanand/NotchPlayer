import SwiftUI

/// The open panel's second page: the song's words, the line being sung lit
/// and the rest dimmed, scrolling along on their own, like Spotify's lyrics.
///
/// **The cover, title and progress make way; the controls stay.** The words
/// take exactly the room the cover row had, and `ControlRow` sits where it
/// sits on the player, so nothing under the pointer moves -- and the lyrics
/// button, lit here, is the way back. The panel stays open while this shows
/// (`Expansion`), so the words can be read with the pointer elsewhere.
///
/// The words are asked of LRCLIB (`Lyrics`) only while this page shows.
public struct LyricsPage: View {
    public enum Content: Equatable, Sendable {
        case loading
        /// LRCLIB was busy or out of reach. Showing the page again asks again.
        case failed
        case lyrics(Lyrics)
    }

    let geometry: NotchGeometry
    let track: Track
    let progress: Interpolator?
    let playing: Bool
    let controllable: Bool
    let modes: Modes?
    let showing: Bool
    let send: (Command) -> Void
    let setRepeat: (Modes.Repeat) -> Void
    let showPage: ((Expansion.Page) -> Void)?
    /// Previews: shown as is, nothing asked.
    let fixed: Content?

    @ObservedObject private var store = LyricsStore.shared

    public init(geometry: NotchGeometry, track: Track, progress: Interpolator?, playing: Bool,
                controllable: Bool, modes: Modes?, showing: Bool,
                send: @escaping (Command) -> Void, setRepeat: @escaping (Modes.Repeat) -> Void,
                showPage: ((Expansion.Page) -> Void)?, fixed: Content? = nil) {
        self.geometry = geometry; self.track = track; self.progress = progress; self.playing = playing
        self.controllable = controllable; self.modes = modes; self.showing = showing
        self.send = send; self.setRepeat = setRepeat; self.showPage = showPage; self.fixed = fixed
    }

    public var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            LyricsWords(content: fixed ?? store.content(for: track), progress: progress,
                        duration: track.duration, live: showing && fixed == nil, style: Self.notch,
                        seek: controllable && track.duration > 0 ? { send(.seek($0)) } : nil)
                .padding(.horizontal, PanelView.inset)
                .frame(height: Self.wordsHeight)
            ControlRow(source: track.source, playing: playing, controllable: controllable, modes: modes,
                       send: send, setRepeat: setRepeat, lyricsShowing: true,
                       lyrics: showPage.map { show in { show(.player) } },
                       showStats: showPage.map { show in { show(.stats) } })
                .padding(.top, PanelView.transportGap)
            Spacer(minLength: 0)
        }
        .frame(width: geometry.openWidth, height: geometry.openHeight)
        .task(id: fixed == nil && showing ? track.id : nil) {
            guard fixed == nil, showing else { return }
            store.load(track)
        }
    }

    /// The room the cover row has on the player: the words end where the
    /// transport line starts, on both pages.
    static let wordsHeight = PanelView.topGap + PanelView.artSide

    /// About four lines: one sung, the one being sung, two to come.
    static let notch = LyricsLines.Style(font: Type.label(14, weight: .semibold), spacing: 6, anchor: 0.3,
                                         note: Type.label(12))
}

/// What the lyrics area shows, in either place: the timed lines, the words
/// alone, or a word on why there are none.
struct LyricsWords: View {
    let content: LyricsPage.Content
    let progress: Interpolator?
    let duration: TimeInterval
    let live: Bool
    let style: LyricsLines.Style
    let seek: ((TimeInterval) -> Void)?

    var body: some View {
        switch content {
        case .loading: note("Finding the lyrics…")
        case .failed: note("Can't reach the lyrics right now")
        case .lyrics(.none): note("No lyrics for this song")
        case .lyrics(.instrumental): note("Instrumental")
        case .lyrics(.plain(let lines)):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: style.spacing) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line.isEmpty ? " " : line)
                            .font(style.font)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, style.spacing)
            }
            .mask(LyricsLines.fade)
        case .lyrics(.synced(let lines)):
            LyricsLines(lines: lines, progress: progress, duration: duration, live: live, style: style, seek: seek)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(style.note)
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Timed lines, the one being sung lit, scrolled so it sits at `style.anchor`.
/// Shared by the notch's page and the big cover.
///
/// **Redrawn when a line starts, not on a clock.** A task sleeps until the
/// next line's start, worked out from the player's position, then redraws; a
/// seek, a pause or the service's re-read of the position brings a new
/// `progress` and restarts it. Paused, or hidden, it does not run at all.
///
/// **Not `TimelineView(.explicit(...))`**, which this was first: in this
/// panel it never woke on its dates, so the lines only moved when the
/// position was re-read, every 5 seconds -- up to a line late (TRAPS #80).
struct LyricsLines: View {
    struct Style {
        let font: Font
        let spacing: CGFloat
        /// Where the lit line sits, from the top (0) to the bottom (1).
        let anchor: CGFloat
        /// "No lyrics for this song" and the like.
        let note: Font
    }

    let lines: [Lyrics.Line]
    let progress: Interpolator?
    let duration: TimeInterval
    /// False keeps it still: a page out of sight, or a preview.
    let live: Bool
    let style: Style
    /// A click on a line goes there. Nil: the lines are only words.
    let seek: ((TimeInterval) -> Void)?

    /// Bumped when a line starts; read by `body` only so that it redraws.
    @State private var wakes = 0

    private struct Clock: Equatable {
        let lines: [Lyrics.Line]
        let progress: Interpolator?
        let live: Bool
    }

    var body: some View {
        let _ = wakes
        Lines(lines: lines, current: Lyrics.index(of: lines, at: position), style: style, seek: seek)
            .task(id: Clock(lines: lines, progress: progress, live: live)) {
                guard live else { return }
                while let next = Self.changes(lines, progress: progress, duration: duration).first {
                    // A hair past the start, so the redraw lands on the new line.
                    try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 0.02))
                    guard !Task.isCancelled else { return }
                    wakes &+= 1
                }
            }
    }

    private var position: TimeInterval { progress?.position(at: .now, duration: duration) ?? 0 }

    /// When each line still to come starts, as dates. None while paused.
    static func changes(_ lines: [Lyrics.Line], progress: Interpolator?, duration: TimeInterval,
                        now: Date = Date(), clock: SuspendingClock.Instant = .now) -> [Date] {
        guard let progress, progress.advancing else { return [] }
        let position = progress.position(at: clock, duration: duration)
        return lines.compactMap { line in
            let wait = line.time - Lyrics.lead - position
            return wait > 0 ? now.addingTimeInterval(wait) : nil
        }
    }

    /// Faded at the top and bottom edges, so lines scroll in and out rather
    /// than being cut. A fixed mask: drawn once, not per line.
    static let fade = LinearGradient(stops: [
        .init(color: .clear, location: 0), .init(color: .black, location: 0.18),
        .init(color: .black, location: 0.82), .init(color: .clear, location: 1),
    ], startPoint: .top, endPoint: .bottom)

    private struct Lines: View {
        let lines: [Lyrics.Line]
        let current: Int?
        let style: Style
        let seek: ((TimeInterval) -> Void)?

        var body: some View {
            GeometryReader { frame in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: style.spacing) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                row(line, lit: index == current).id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Room for the first line to sit at the anchor, and the last.
                        .padding(.top, frame.size.height * style.anchor)
                        .padding(.bottom, frame.size.height * (1 - style.anchor))
                    }
                    .mask(LyricsLines.fade)
                    .onAppear { proxy.scrollTo(current ?? 0, anchor: UnitPoint(x: 0, y: style.anchor)) }
                    .onChange(of: current) { _, now in
                        withAnimation(Motion.reduced ? nil : .easeInOut(duration: 0.35 * Motion.slow)) {
                            proxy.scrollTo(now ?? 0, anchor: UnitPoint(x: 0, y: style.anchor))
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func row(_ line: Lyrics.Line, lit: Bool) -> some View {
            // `verbatim`: the words are someone else's text, never markup.
            let text = Text(verbatim: line.text.isEmpty ? "♪" : line.text)
                .font(style.font)
                .foregroundStyle(lit ? Palette.primary : Palette.secondary)
                .animation(.easeOut(duration: 0.2 * Motion.slow), value: lit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(lit ? .isSelected : [])
            if let seek {
                // A plain button, acting on mouse-up like every other here (TRAPS #37).
                Button { seek(line.time) } label: { text.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays from this line")
            } else {
                text
            }
        }
    }
}

import SwiftUI

/// One transport control.
///
/// **A plain-styled `Button` with an explicit colour, not a stock control.**
/// The panel never becomes key, and AppKit draws its own controls in the
/// inactive grey style in a window like that -- so a stock button would look
/// disabled, which for a play button is the worst possible lie. matchnotch
/// carries three separate trap entries about this (#5, #31, #49) and ends up
/// drawing its own switch. A `.plain` button with `.foregroundStyle` has no
/// inactive state to draw, so the problem never arises.
public struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let colour: Color
    let action: () -> Void

    public init(symbol: String, size: CGFloat, label: String, colour: Color = Palette.primary,
                action: @escaping () -> Void) {
        self.symbol = symbol; self.size = size; self.label = label
        self.colour = colour; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(colour)
                .frame(width: NotchGeometry.minimumHitHeight,
                       height: NotchGeometry.minimumHitHeight)
                // **Last, after every sizing modifier.** `.contentShape` uses
                // the bounds of the view it is applied to; a `.frame()` placed
                // after it enlarges the layout and leaves the live area where
                // it was. matchnotch had this backwards at six call sites,
                // each with a comment claiming a 44pt target -- the worst case
                // was a 12pt glyph where about a seventh of the intended
                // target worked, and four clicks in five did nothing. It was
                // found from a phone video, not from the code.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Shuffle, previous, play/pause, next, repeat -- drawn to match the user's
/// screenshot of Spotify's own row, then made white wherever it is usable
/// (the user's call: Spotify's greys read as disabled). A white disc behind
/// play/pause with the glyph cut out in black.
public struct TransportRow: View {
    let playing: Bool
    /// Nil until Spotify has been read; drawn as off.
    let modes: Modes?
    let send: (SpotifyBridge.Command) -> Void
    let setRepeat: (Modes.Repeat) -> Void

    public init(playing: Bool, modes: Modes? = nil,
                send: @escaping (SpotifyBridge.Command) -> Void,
                setRepeat: @escaping (Modes.Repeat) -> Void = { _ in }) {
        self.playing = playing; self.modes = modes; self.send = send; self.setRepeat = setRepeat
    }

    /// Sized from the screenshot, which is 2x: previous/next 27px tall,
    /// shuffle/repeat 29px wide, the disc 58px across. The hit targets are
    /// all 44pt regardless -- the drawn size and the tappable size are
    /// different questions.
    public static let sideGlyph: CGFloat = 16.5
    public static let centreGlyph: CGFloat = 14
    public static let disc: CGFloat = 29
    /// Shuffle's symbol is wider than its neighbours at the same size.
    public static let shuffleGlyph: CGFloat = 12.5
    /// **Spaced exactly as the screenshot**, at the user's request: centres
    /// 44pt apart across the middle three (87.5px at 2x) and 37pt out to
    /// shuffle and repeat (73px). So the targets touch -- this was 56pt with a
    /// 12pt gap, so a trackpad miss landed on nothing -- and the two outer
    /// ones are 30pt wide, under the 44pt used everywhere else. See
    /// `docs/DECISIONS.md`.
    public static let gap: CGFloat = 0
    public static var centreToCentre: CGFloat { NotchGeometry.minimumHitHeight + gap }
    public static let modeWidth: CGFloat = 30
    public static var outerCentreToCentre: CGFloat {
        NotchGeometry.minimumHitHeight / 2 + modeWidth / 2
    }
    public static var width: CGFloat {
        NotchGeometry.minimumHitHeight * 3 + modeWidth * 2 + gap * 2
    }

    /// **The glyph is what playback *is*, not what the button does.** A
    /// playing track shows the pause bars, because that is the state you are
    /// in and the thing you would change. Getting this backwards is a
    /// one-character mistake that reads as correct in the code and as broken
    /// on screen, so it is a function with a test rather than a ternary in a
    /// view body.
    public static func playPauseSymbol(playing: Bool) -> String {
        playing ? "pause.fill" : "play.fill"
    }

    /// What VoiceOver reads. Names the action, not the state -- a button is
    /// announced by what pressing it does.
    public static func playPauseLabel(playing: Bool) -> String {
        playing ? "Pause" : "Play"
    }

    static func repeatValue(_ mode: Modes.Repeat) -> String {
        switch mode {
        case .off: "off"
        case .all: "all songs"
        case .one: "this song"
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            ModeButton(symbol: "shuffle", on: modes?.shuffle ?? false, one: false,
                       allowed: modes?.allowed ?? true, label: "Shuffle") {
                send(.shuffle(!(modes?.shuffle ?? false)))
            }
            TransportButton(symbol: "backward.end.fill", size: Self.sideGlyph,
                            label: "Previous track") { send(.previous) }
            Spacer().frame(width: Self.gap)
            Button { send(.playpause) } label: {
                ZStack {
                    Circle().fill(Palette.primary).frame(width: Self.disc, height: Self.disc)
                    Image(systemName: Self.playPauseSymbol(playing: playing))
                        .font(.system(size: Self.centreGlyph, weight: .bold))
                        .foregroundStyle(Palette.background)
                }
                .frame(width: NotchGeometry.minimumHitHeight, height: NotchGeometry.minimumHitHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.playPauseLabel(playing: playing))
            Spacer().frame(width: Self.gap)
            TransportButton(symbol: "forward.end.fill", size: Self.sideGlyph,
                            label: "Next track") { send(.next) }
            let mode = modes?.repeatMode ?? .off
            ModeButton(symbol: "repeat", on: mode != .off, one: mode == .one,
                       allowed: modes?.allowed ?? true,
                       label: "Repeat", value: Self.repeatValue(mode)) {
                setRepeat(Modes.next(after: mode))
            }
        }
        .frame(width: Self.width, height: NotchGeometry.minimumHitHeight)
    }
}

/// Shuffle or repeat: white when off, so it reads as usable (the user's call
/// -- the screenshot's `#363636` read as disabled); Spotify green with a dot
/// under it when on, the way Spotify marks it, so the state is not carried by
/// colour alone.
struct ModeButton: View {
    let symbol: String
    let on: Bool
    /// Repeat one: a "1" inside the loop, as Spotify draws it.
    let one: Bool
    /// False on Spotify's DJ: fainter, and a click does nothing rather than
    /// send a write Spotify would silently drop.
    let allowed: Bool
    let label: String
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(on ? Palette.spotify : Palette.primary)
                .overlay(alignment: .bottom) {
                    Circle().fill(Palette.spotify)
                        .frame(width: 4, height: 4)
                        .offset(y: 9)
                        .opacity(on ? 1 : 0)
                }
                .frame(width: TransportRow.modeWidth,
                       height: NotchGeometry.minimumHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(allowed ? 1 : 0.4)
        .disabled(!allowed)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? (on ? "on" : "off"))
    }

    /// Spotify's repeat is a rounded loop with one arrowhead, which SF
    /// Symbols' `repeat` (two arrows) is not -- so it is drawn.
    @ViewBuilder private var glyph: some View {
        if symbol == "repeat" {
            // Repeat one, as Spotify draws it: the loop opens at the top and a
            // "1" stands in the gap, taller than the loop's edge.
            RepeatGlyph(gapAtTop: one)
                .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 14)
                .overlay(alignment: .top) {
                    if one {
                        Text("1").font(.system(size: 9.5, weight: .bold))
                            .offset(y: -3.5)
                    }
                }
        } else {
            Image(systemName: symbol)
                .font(.system(size: TransportRow.shuffleGlyph, weight: .semibold))
        }
    }
}

/// Traced from the screenshot: a rounded square open at the bottom, the
/// stroke coming round clockwise into an arrowhead that points left into
/// the gap.
struct RepeatGlyph: Shape {
    /// Leave the middle of the top edge open, for repeat-one's "1".
    var gapAtTop = false

    func path(in rect: CGRect) -> Path {
        let lw: CGFloat = 1.7
        let box = CGRect(x: rect.minX + lw / 2, y: rect.minY + lw / 2,
                         width: rect.width - lw, height: rect.height * 0.8 - lw)
        let r = box.height * 0.3, w = box.width
        var p = Path()
        p.move(to: CGPoint(x: box.minX + w * 0.38, y: box.maxY))
        p.addLine(to: CGPoint(x: box.minX + r, y: box.maxY))
        p.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - r),
                       control: CGPoint(x: box.minX, y: box.maxY))
        p.addLine(to: CGPoint(x: box.minX, y: box.minY + r))
        p.addQuadCurve(to: CGPoint(x: box.minX + r, y: box.minY),
                       control: CGPoint(x: box.minX, y: box.minY))
        if gapAtTop {
            p.addLine(to: CGPoint(x: box.midX - w * 0.2, y: box.minY))
            p.move(to: CGPoint(x: box.midX + w * 0.2, y: box.minY))
        }
        p.addLine(to: CGPoint(x: box.maxX - r, y: box.minY))
        p.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + r),
                       control: CGPoint(x: box.maxX, y: box.minY))
        p.addLine(to: CGPoint(x: box.maxX, y: box.maxY - r))
        p.addQuadCurve(to: CGPoint(x: box.maxX - r, y: box.maxY),
                       control: CGPoint(x: box.maxX, y: box.maxY))
        let tip = CGPoint(x: box.minX + w * 0.5, y: box.maxY)
        p.addLine(to: tip)
        let wing = box.height * 0.26
        p.move(to: CGPoint(x: tip.x + wing, y: tip.y - wing))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + wing, y: tip.y + wing))
        return p
    }
}

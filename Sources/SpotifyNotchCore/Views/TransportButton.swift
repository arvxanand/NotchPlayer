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
    let action: () -> Void

    public init(symbol: String, size: CGFloat, label: String,
                action: @escaping () -> Void) {
        self.symbol = symbol; self.size = size; self.label = label; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Palette.primary)
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

/// What a transport button means, separate from who carries it out.
///
/// The row draws three buttons; Spotify's panel turns these into Apple Events
/// addressed to Spotify by name, and the panel for any other app turns them
/// into system media keys. The row knows neither -- which is what lets one
/// row serve both without a flag saying which kind of app it is in.
public enum Transport: Equatable, Sendable {
    case previous, playpause, next
}

/// Previous, play/pause, next.
public struct TransportRow: View {
    let playing: Bool
    let send: (Transport) -> Void

    public init(playing: Bool, send: @escaping (Transport) -> Void) {
        self.playing = playing; self.send = send
    }

    /// The middle glyph is bigger because it is the one people aim at without
    /// looking. The hit targets are all 44pt regardless -- the drawn size and
    /// the tappable size are different questions.
    public static let sideGlyph: CGFloat = 18
    public static let centreGlyph: CGFloat = 22
    /// Gap between the 44pt targets, chosen so their centres are 56pt apart:
    /// close enough to read as one control, far enough that a trackpad miss
    /// does not skip a track when it meant to pause.
    public static let gap: CGFloat = 12
    public static var centreToCentre: CGFloat { NotchGeometry.minimumHitHeight + gap }
    public static var width: CGFloat {
        NotchGeometry.minimumHitHeight * 3 + gap * 2
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

    public var body: some View {
        HStack(spacing: Self.gap) {
            TransportButton(symbol: "backward.fill", size: Self.sideGlyph,
                            label: "Previous track") { send(.previous) }
            TransportButton(symbol: Self.playPauseSymbol(playing: playing),
                            size: Self.centreGlyph,
                            label: Self.playPauseLabel(playing: playing)) { send(.playpause) }
            TransportButton(symbol: "forward.fill", size: Self.sideGlyph,
                            label: "Next track") { send(.next) }
        }
        .frame(width: Self.width, height: NotchGeometry.minimumHitHeight)
    }
}

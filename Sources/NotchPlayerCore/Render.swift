import AppKit
import SwiftUI

/// Render one view offscreen to a PNG, large, so a detail can be judged.
///
/// **A different job from `tools/check_notch.sh`, deliberately.** That
/// captures the real window and answers "what is on screen"; this answers
/// "what does this view look like" without a window, at whatever size makes
/// the thing legible. Neither substitutes for the other: an offscreen render
/// cannot prove the panel draws, and an 11pt mark in a window capture cannot
/// be judged at all.
public enum Render {
    /// Named so `--render` has a fixed vocabulary and a typo cannot silently
    /// produce something plausible.
    public enum Subject: String, CaseIterable, Sendable {
        case mark, peek, artwork, waveform, menu, update, settings, progress
    }

    @MainActor
    public static func png(_ subject: Subject, side: CGFloat, to path: String) -> Bool {
        let size = canvas(subject, side: side)
        let host = NSHostingView(rootView: content(subject, side: side))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func canvas(_ subject: Subject, side: CGFloat) -> CGSize {
        switch subject {
        case .mark, .artwork: return CGSize(width: side, height: side)
        case .waveform:       return CGSize(width: side * 3, height: side)
        case .peek:           return CGSize(width: side * 10, height: side)
        // Its own fixed size: the popover is not scalable art, it is a window
        // whose proportions are the thing being judged.
        case .menu, .update, .settings: return CGSize(width: MenuPanel.width, height: MenuPanel.height)
        // The real width it is drawn at, so the knob is judged at its real
        // proportion to the line rather than at a flattering one.
        case .progress:       return CGSize(width: 234, height: 40)
        }
    }

    @MainActor @ViewBuilder
    private static func content(_ subject: Subject, side: CGFloat) -> some View {
        ZStack {
            Palette.background
            switch subject {
            case .mark:
                SpotifyMark().frame(width: side * 0.8, height: side * 0.8)
            case .menu, .update:
                MenuPanel(track: PreviewData.named("playing")?.now.track,
                          playing: true, subtitle: "Playing", hidden: false,
                          toggleHidden: {}, login: .on, toggleLogin: { .on },
                          update: subject == .update ? "0.4" : nil, version: "0.3", quit: {},
                          animateIn: false)
            case .settings:
                MenuPanel(track: nil, playing: false, subtitle: "", hidden: false,
                          toggleHidden: {}, login: .on, toggleLogin: { .on },
                          checkUpdates: true, quit: {},
                          page: .settings, animateIn: false)
            case .progress:
                // Handlers passed, because the knob only exists when the line
                // is actually draggable.
                ProgressLine(fraction: 0.62, onScrub: { _ in }, onCommit: { _ in })
                    .frame(width: 234)
            case .artwork, .peek, .waveform:
                // Filled in as each view lands; a subject with no content is
                // a black square, which is visibly nothing rather than
                // plausibly something.
                EmptyView()
            }
        }
    }
}

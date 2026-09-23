import AppKit
import SwiftUI

/// What the panel shows instead of transport controls when Apple Events are
/// refused.
///
/// It takes the transport row's place and its exact height, so the panel does
/// not change size between states -- one `panelHeight`, one set of expected
/// bounds in the footprint check, and no second animation to tune.
public struct PermissionNote: View {
    /// Nil where the panel has already explained itself. `PermissionPanel`
    /// leads with "Can't reach Spotify" and a sentence; repeating a second,
    /// differently-worded explanation under it read as two problems rather
    /// than one.
    let explanation: String?

    public init(explanation: String? = PermissionNote.defaultExplanation) {
        self.explanation = explanation
    }

    /// Verified on macOS 15.7.7 on 14 Sep 2026: this opens System Settings
    /// directly on the Automation pane, not merely on Privacy & Security.
    /// A deep link that silently lands on the wrong pane is worse than a
    /// sentence, because the user follows it and finds nothing.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    public static let defaultExplanation = "Automation access is needed to control Spotify."
    public static let action = "Open Settings"

    public var body: some View {
        Button {
            NSWorkspace.shared.open(Self.settingsURL)
        } label: {
            VStack(spacing: 3) {
                if let explanation {
                    Text(explanation)
                        .font(Type.label(11))
                        .foregroundStyle(Palette.secondary)
                }
                HStack(spacing: 3) {
                    Text(Self.action)
                        .font(Type.label(12, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Palette.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: NotchGeometry.minimumHitHeight)
            // Last, after every sizing modifier. The whole block is the
            // target, not just the words -- see docs/TRAPS.md #21.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([explanation, Self.action].compactMap { $0 }.joined(separator: " "))
    }
}

/// The panel when nothing is known and Automation is refused.
///
/// Spotify is running -- a denial cannot be reported for an app that is not
/// open -- so there is something to say and no way to say it in the peek.
public struct PermissionPanel: View {
    let geometry: NotchGeometry

    public init(geometry: NotchGeometry) { self.geometry = geometry }

    public var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            HStack(alignment: .top, spacing: PanelView.gap) {
                SpotifyMark()
                    .frame(width: PanelView.artSide * 0.62, height: PanelView.artSide * 0.62)
                    .frame(width: PanelView.artSide, height: PanelView.artSide)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can't reach Spotify")
                        .font(Type.title())
                        .foregroundStyle(Palette.primary)
                        .lineLimit(1)
                    Text("NotchPlayer needs permission to read what's playing.")
                        .font(Type.label())
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(height: PanelView.artSide, alignment: .top)
            }
            .padding(.horizontal, PanelView.inset)
            .padding(.top, PanelView.topGap)

            // Action only: the text above has already said what is wrong.
            PermissionNote(explanation: nil)
                .padding(.horizontal, PanelView.inset)
                .padding(.top, PanelView.transportGap)

            Spacer(minLength: 0)
        }
        .frame(width: geometry.collapsedWidth, height: NotchGeometry.panelHeight)
    }
}

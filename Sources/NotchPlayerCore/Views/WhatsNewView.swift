import SwiftUI

/// "New in v0.6", once, the first time the notch opens after an update.
///
/// Same frame and the same empty camera band as `PanelView`. "Got it" puts
/// the player back; so does closing the notch, so it never shows twice.
public struct WhatsNewView: View {
    let geometry: NotchGeometry
    let note: WhatsNew.Note
    let dismiss: () -> Void

    public init(geometry: NotchGeometry, note: WhatsNew.Note, dismiss: @escaping () -> Void = {}) {
        self.geometry = geometry; self.note = note; self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            Text("New in v\(note.version)")
                .font(Type.title(15))
                .foregroundStyle(Palette.primary)
                .padding(.top, Self.topGap)
            VStack(alignment: .leading, spacing: Self.lineGap) {
                ForEach(note.lines, id: \.self) { line in
                    HStack(alignment: .center, spacing: 7) {
                        Circle().fill(Palette.spotify).frame(width: 5, height: 5)
                        Text(line)
                            .font(Self.lineFont)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                // A plain button acts on mouse-up (`docs/TRAPS.md` #37).
                Button(action: dismiss) {
                    Text("Got it")
                        .font(Type.label(12, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 14)
                        .frame(height: Self.buttonHeight)
                        .background(Palette.primary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PanelView.inset)
        .padding(.bottom, PanelView.bottomGap + 2)
        .frame(width: geometry.openWidth, height: geometry.openHeight)
    }

    static let topGap: CGFloat = 8
    static let lineGap: CGFloat = 5
    static let buttonHeight: CGFloat = 26
    static let lineFont = Type.label(12)
    /// What a line has to fit in: the panel less its insets, the dot and its gap.
    public static func lineWidth(_ geometry: NotchGeometry) -> CGFloat {
        geometry.openWidth - PanelView.inset * 2 - 12
    }
}

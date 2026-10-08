import SwiftUI

/// The open panel's second page: how much was listened to, and to what.
///
/// Same frame and the same empty camera band as `PanelView`, so the shell is
/// one size on both pages and nothing legible sits behind the housing.
///
/// Left, the total time and the song count; right, the top three, artists or
/// songs. Four ranges along the top. Everything comes from `Listening`, kept
/// on this Mac (`Stats.summary`).
public struct StatsView: View {
    let geometry: NotchGeometry
    let plays: [Play]
    /// Fixed in previews, so a capture is the same whenever it is taken.
    let now: Date

    @State private var range = Stats.Range.today
    @State private var songs = false

    public init(geometry: NotchGeometry, plays: [Play], now: Date = Date()) {
        self.geometry = geometry; self.plays = plays; self.now = now
    }

    public var body: some View {
        let summary = Stats.summary(plays, range, now: now)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            HStack(spacing: 2) {
                ForEach(Stats.Range.allCases, id: \.self) { which in
                    choice(which.title, on: range == which) { range = which }
                }
            }
            .padding(.top, Self.topGap)
            HStack(alignment: .top, spacing: Self.columnGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Stats.duration(summary.seconds))
                        .font(Type.title(24))
                        .foregroundStyle(Palette.primary)
                    Text("listened")
                        .font(Type.label(11))
                        .foregroundStyle(Palette.secondary)
                    Text(summary.songs == 1 ? "1 song" : "\(summary.songs) songs")
                        .font(Type.label(12))
                        .foregroundStyle(Palette.primary)
                        .padding(.top, 8)
                }
                .frame(width: Self.totalsWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        choice("Artists", on: !songs) { songs = false }
                        choice("Songs", on: songs) { songs = true }
                    }
                    top(songs ? summary.tracks : summary.artists)
                }
            }
            .padding(.top, Self.rowGap)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelView.inset)
        .padding(.bottom, PanelView.bottomGap)
        .frame(width: geometry.openWidth, height: geometry.openHeight)
    }

    @ViewBuilder
    private func top(_ entries: [Stats.Entry]) -> some View {
        if entries.isEmpty {
            Text("Nothing yet")
                .font(Type.label(12))
                .foregroundStyle(Palette.secondary)
                .frame(height: Self.lineHeight)
        } else {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(Type.clock())
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 10, alignment: .leading)
                    Text(entry.name)
                        .font(Type.label(12))
                        .foregroundStyle(Palette.primary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(songs ? (entry.plays == 1 ? "1 play" : "\(entry.plays) plays")
                               : Stats.duration(entry.seconds))
                        .font(Type.clock())
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                }
                .frame(height: Self.lineHeight)
            }
        }
    }

    /// A tab: a plain button, which acts on mouse-up (`docs/TRAPS.md` #37).
    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Type.label(11, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Palette.primary : Palette.secondary)
                .padding(.horizontal, 8)
                .frame(height: Self.tabHeight)
                .background(on ? Palette.wash : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Metrics

    static let topGap: CGFloat = 6
    static let rowGap: CGFloat = 8
    static let columnGap: CGFloat = 16
    static let tabHeight: CGFloat = 24
    static let lineHeight: CGFloat = 20
    static let totalsWidth: CGFloat = 96

    /// Everything below the camera band, top to bottom, at its tallest.
    public static func contentHeight() -> CGFloat {
        topGap + tabHeight + rowGap + tabHeight + lineHeight * 3
    }
}

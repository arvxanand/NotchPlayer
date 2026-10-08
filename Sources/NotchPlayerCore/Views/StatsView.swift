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
    /// The playing song's cover, whose colour tints the page like the
    /// progress line (`Accent`).
    let artwork: URL?
    /// Fixed in previews, so a capture is the same whenever it is taken.
    let now: Date

    @State private var range = Stats.Range.today
    @State private var songs = false
    @ObservedObject private var memory = ArtMemory.shared
    @AppStorage(Accent.enabledKey) private var coverAccent = true

    public init(geometry: NotchGeometry, plays: [Play], artwork: URL? = nil, now: Date = Date()) {
        self.geometry = geometry; self.plays = plays; self.artwork = artwork; self.now = now
    }

    /// The cover's colour, already legible on black; white for a grey cover,
    /// or when the switch for the progress line's colour is off.
    private var accent: Color {
        memory.accent(for: coverAccent ? artwork : nil).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
            ?? Palette.primary
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
                        .foregroundStyle(accent)
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
            let most = entries.map { songs ? Double($0.plays) : $0.seconds }.max() ?? 1
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let share = (songs ? Double(entry.plays) : entry.seconds) / max(most, 1)
                VStack(alignment: .leading, spacing: Self.barGap) {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(Type.clock())
                            .foregroundStyle(Palette.secondary)
                            .frame(width: Self.rankWidth - 6, alignment: .leading)
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
                    // How it compares with the first: full width for #1, then
                    // shorter and fainter, so the three read as a ranking.
                    GeometryReader { box in
                        Capsule()
                            .fill(accent.opacity(1 - Double(index) * 0.25))
                            .frame(width: max(Self.barHeight, box.size.width * share))
                    }
                    .frame(height: Self.barHeight)
                    .padding(.leading, Self.rankWidth)
                }
                .frame(height: Self.lineHeight, alignment: .top)
            }
        }
    }

    /// A tab: a plain button, which acts on mouse-up (`docs/TRAPS.md` #37).
    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Type.label(11, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? accent : Palette.secondary)
                .padding(.horizontal, 8)
                .frame(height: Self.tabHeight)
                .background(on ? accent.opacity(0.18) : .clear, in: Capsule())
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
    static let lineHeight: CGFloat = 22
    static let barHeight: CGFloat = 2.5
    static let barGap: CGFloat = 2
    static let rankWidth: CGFloat = 16
    static let totalsWidth: CGFloat = 96

    /// Everything below the camera band, top to bottom, at its tallest.
    public static func contentHeight() -> CGFloat {
        topGap + tabHeight + rowGap + tabHeight + lineHeight * 3
    }
}

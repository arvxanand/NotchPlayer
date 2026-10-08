import SwiftUI

/// The open panel's second page: the user's playlists, albums, DJ and Liked
/// Songs as covers. Tapping one plays it; the + adds whatever link is on the
/// clipboard (`Picks`).
///
/// Same frame and the same empty camera band as `PanelView`, so the shell is
/// one size on both pages and nothing legible sits behind the housing.
///
/// **One row of four, scrolling a whole row at a time.** The covers are the
/// player's size where the panel is wide enough. The window onto them is
/// exactly one row tall, so nothing shows cut off; the owner chose that over
/// letting the next row peek out (9 Oct 2026).
public struct PicksView: View {
    let geometry: NotchGeometry
    let picks: [Pick]
    let play: (Pick) -> Void
    /// Reads the clipboard and adds it. A no-op in previews.
    let add: () async -> Picks.Added

    /// What the + says for a moment after a tap that added nothing.
    @State private var adding: Adding?
    private enum Adding: Equatable { case working, hint(String) }

    public init(geometry: NotchGeometry, picks: [Pick], play: @escaping (Pick) -> Void = { _ in },
                add: @escaping () async -> Picks.Added = { .notALink }) {
        self.geometry = geometry; self.picks = picks; self.play = play; self.add = add
    }

    public var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchExclusionTop)
            Spacer(minLength: 0)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Self.rows(picks.count + 1), id: \.lowerBound) { row in
                        HStack(spacing: Self.gap(geometry)) {
                            ForEach(row, id: \.self) { cell($0) }
                            Spacer(minLength: 0)
                        }
                        .frame(height: Self.rowHeight(geometry))
                    }
                }
                .scrollTargetLayout()
            }
            // A page is the scroll view's own height, which is one row.
            .scrollTargetBehavior(.paging)
            .frame(height: Self.rowHeight(geometry))
            .padding(.horizontal, PanelView.inset)
            Spacer(minLength: 0)
        }
        // Clear of the bottom gap, where the page dots are.
        .padding(.bottom, PanelView.bottomGap)
        .frame(width: geometry.openWidth, height: geometry.openHeight)
    }

    /// The picks, then the + last.
    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if index < picks.count { tile(picks[index]) } else { plus }
    }

    private func tile(_ pick: Pick) -> some View {
        Button { play(pick) } label: {
            VStack(spacing: Self.nameGap) {
                cover(pick)
                name(pick.name, colour: Palette.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(pick.name)")
    }

    @ViewBuilder
    private func cover(_ pick: Pick) -> some View {
        let side = Self.side(geometry)
        // A playlist the preview had nothing for gets a note, not the mark:
        // at 72pt the mark is a big green disc that reads as Spotify itself.
        if let symbol = pick.symbol ?? (pick.cover == nil ? "music.note.list" : nil) {
            RoundedRectangle(cornerRadius: PanelView.artCorner)
                .fill(Palette.wash)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.34, weight: .medium))
                        .foregroundStyle(Palette.primary)
                }
        } else {
            ArtworkView(url: pick.cover, side: side, corner: PanelView.artCorner)
        }
    }

    private func name(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(Type.label(12))
            .foregroundStyle(colour)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.side(geometry), height: Self.nameHeight)
    }

    private var plus: some View {
        let side = Self.side(geometry)
        return Button { tapPlus() } label: {
            VStack(spacing: Self.nameGap) {
                RoundedRectangle(cornerRadius: PanelView.artCorner)
                    .strokeBorder(Palette.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: side, height: side)
                    .overlay {
                        switch adding {
                        case .working:
                            ProgressView().controlSize(.small)
                        case .hint(let text):
                            Text(text)
                                .font(Type.label(11))
                                .foregroundStyle(Palette.secondary)
                                .multilineTextAlignment(.center)
                                .padding(6)
                        case nil:
                            Image(systemName: "plus")
                                .font(.system(size: side * 0.3, weight: .regular))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                name("Add", colour: Palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding == .working)
        .accessibilityLabel("Add the copied playlist or album link")
    }

    private func tapPlus() {
        adding = .working
        Task {
            let result = await add()
            switch result {
            case .added: adding = nil; return
            case .already: adding = .hint("Already added")
            case .notALink: adding = .hint("Copy a playlist link first")
            }
            try? await Task.sleep(for: .seconds(2))
            if adding != .working { adding = nil }
        }
    }

    // MARK: - Metrics

    public nonisolated static let columns = 4
    static let nameGap: CGFloat = 4
    static let nameHeight: CGFloat = 16
    static let minimumGap: CGFloat = 8

    /// A cover and its name.
    public static func rowHeight(_ geometry: NotchGeometry) -> CGFloat {
        side(geometry) + nameGap + nameHeight
    }

    /// `count` cells in rows of four.
    nonisolated static func rows(_ count: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: columns).map { $0..<min($0 + columns, count) }
    }

    /// The player's cover size where four fit, smaller on a narrow notch.
    public static func side(_ geometry: NotchGeometry) -> CGFloat {
        let room = geometry.openWidth - PanelView.inset * 2
        return min(PanelView.artSide,
                   ((room - minimumGap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down))
    }

    public static func gap(_ geometry: NotchGeometry) -> CGFloat {
        let room = geometry.openWidth - PanelView.inset * 2
        return (room - side(geometry) * CGFloat(columns)) / CGFloat(columns - 1)
    }
}

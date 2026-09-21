import AppKit
import SwiftUI

/// Holds whichever preview state the capture run is currently looking at.
///
/// **One process for the whole run, not one per state.** Launching an app,
/// putting a window over the menu bar and tearing it down again, nineteen
/// times, is roughly a minute of things appearing and disappearing across the
/// top of the screen of whoever is using the machine. The window here is
/// created once, parked out of the way, and redrawn between captures.
@MainActor
public final class CaptureStage: ObservableObject {
    @Published public var state: PreviewData.State
    @Published public var expanded: Bool
    /// Fill the shell white so its geometry can be measured at all -- a black
    /// shape on a dark menu bar is the same pixels as no shape.
    @Published public var probe: Bool

    public init(state: PreviewData.State, expanded: Bool = false, probe: Bool = false) {
        self.state = state
        self.expanded = expanded
        self.probe = probe
    }

    /// Switch states with **animation off**.
    ///
    /// Otherwise every capture races a 0.38s spring, and the honest fix would
    /// be to sleep long enough for the slowest one -- which is how the
    /// per-state launch got to 2.4s in the first place.
    public func show(_ state: PreviewData.State, expanded: Bool, probe: Bool = false) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.state = state
            self.expanded = expanded
            self.probe = probe
        }
    }

    /// `<state>`, `<state> expanded`, or the bare word `probe`. Returns nil
    /// for an unknown name rather than rendering something plausible.
    public static func parse(_ line: String)
        -> (state: PreviewData.State, expanded: Bool, probe: Bool)? {
        let words = line.split(separator: " ").map(String.init)
        guard let name = words.first else { return nil }
        if name == "probe" { return (PreviewData.all[0], false, true) }
        guard let state = PreviewData.named(name) else { return nil }
        return (state, words.dropFirst().contains("expanded"), false)
    }
}

public struct CaptureStageView: View {
    let geometry: NotchGeometry
    @ObservedObject var stage: CaptureStage

    public init(geometry: NotchGeometry, stage: CaptureStage) {
        self.geometry = geometry; self.stage = stage
    }

    public var body: some View {
        RootView(geometry: geometry, now: stage.state.now,
                 permission: stage.state.permission, expanded: stage.expanded,
                 source: stage.state.source,
                 progress: stage.state.progress, holdBands: stage.state.bands,
                 sourceIcon: PreviewData.stubIcon,
                 probe: stage.probe)
    }
}

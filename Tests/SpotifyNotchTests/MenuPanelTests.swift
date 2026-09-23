import XCTest
import SwiftUI
@testable import SpotifyNotchCore

/// Both pages share one fixed height so the popover never resizes mid-slide,
/// and they are clipped -- so a page that outgrows it loses its last row
/// silently. This is what notices.
@MainActor
final class MenuPanelTests: XCTestCase {
    private func panel(login: MenuPanel.Login) -> MenuPanel {
        MenuPanel(track: nil, playing: false, subtitle: "Nothing playing", hidden: false,
                  toggleHidden: {}, login: login, toggleLogin: { login }, quit: {})
    }

    private func height(_ view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: MenuPanel.width).fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    func testBothPagesFitTheFixedHeight() {
        for login in [MenuPanel.Login.off, .on, .needsApproval] {
            let p = panel(login: login)
            XCTAssertLessThanOrEqual(height(p.main), MenuPanel.height, "main, login \(login)")
            XCTAssertLessThanOrEqual(height(p.settings), MenuPanel.height, "settings, login \(login)")
        }
    }
}

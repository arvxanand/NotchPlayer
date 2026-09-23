import XCTest
import SwiftUI
@testable import NotchPlayerCore

/// Both pages share one fixed height so the popover never resizes mid-slide,
/// and they are clipped -- so a page that outgrows it loses its last row
/// silently. This is what notices.
@MainActor
final class MenuPanelTests: XCTestCase {
    private func panel(login: MenuPanel.Grant, plus: MenuPanel.Grant = .off) -> MenuPanel {
        MenuPanel(track: nil, playing: false, subtitle: "Nothing playing", hidden: false,
                  toggleHidden: {}, login: login, toggleLogin: { login },
                  plus: plus, togglePlus: { plus }, quit: {})
    }

    private func height(_ view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: MenuPanel.width).fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    func testBothPagesFitTheFixedHeight() {
        let states: [MenuPanel.Grant] = [.off, .on, .needsApproval]
        for login in states {
            for plus in states {
                let p = panel(login: login, plus: plus)
                XCTAssertLessThanOrEqual(height(p.main), MenuPanel.height, "main, login \(login)")
                XCTAssertLessThanOrEqual(height(p.settings), MenuPanel.height,
                                         "settings, login \(login), plus \(plus)")
            }
        }
    }
}

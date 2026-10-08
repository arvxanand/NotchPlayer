import XCTest
import SwiftUI
@testable import NotchPlayerCore

/// Both pages share one fixed height so the popover never resizes mid-slide,
/// and they are clipped -- so a page that outgrows it loses its last row
/// silently. This is what notices.
@MainActor
final class MenuPanelTests: XCTestCase {
    /// With the update and virtual-notch switches showing: the tallest the
    /// settings page gets.
    private func panel(login: MenuPanel.Grant, plus: MenuPanel.Grant = .off,
                       update: String? = nil, virtualNotch: Bool? = true) -> MenuPanel {
        MenuPanel(track: nil, playing: false, subtitle: "Nothing playing", hidden: false,
                  toggleHidden: {}, login: login, toggleLogin: { login },
                  plus: plus, togglePlus: { plus },
                  update: update, checkUpdates: true, virtualNotch: virtualNotch,
                  version: "0.3", quit: {})
    }

    private func height(_ view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: MenuPanel.width).fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    func testBothPagesFitTheFixedHeight() {
        let states: [MenuPanel.Grant] = [.off, .on, .needsApproval]
        // Without the virtual-notch switch (every notched Mac) and with it.
        for virtual in [nil, true] as [Bool?] {
            let fixed = MenuPanel.height(virtualNotch: virtual)
            for login in states {
                for plus in states {
                    let p = panel(login: login, plus: plus, virtualNotch: virtual)
                    XCTAssertLessThanOrEqual(height(p.main), fixed, "main, login \(login)")
                    XCTAssertLessThanOrEqual(height(panel(login: login, update: "0.4",
                                                          virtualNotch: virtual).main), fixed,
                                             "main with an update")
                    XCTAssertLessThanOrEqual(height(p.settings), fixed,
                                             "settings, login \(login), plus \(plus), virtual \(String(describing: virtual))")
                }
            }
        }
        XCTAssertEqual(MenuPanel.height(virtualNotch: nil), MenuPanel.height,
                       "a notched Mac's popover must not grow")
    }
}

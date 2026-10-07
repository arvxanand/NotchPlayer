import XCTest
@testable import NotchPlayerCore

/// This display's real numbers, so the arithmetic is checked against a Mac
/// that exists rather than against round figures.
private let builtIn = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                    notchWidth: 208, notchHeight: 37, hasNotch: true)

final class GeometryTests: XCTestCase {
    func testCollapsedWidthIsTheCutoutPlusOneWingEachSide() {
        XCTAssertEqual(builtIn.collapsedWidth,
                       builtIn.notchWidth + NotchGeometry.collapsedSideWidth * 2)
        // The wings are equal so the shape stays centred on the cutout. If
        // they ever stop being equal this is the test that should break.
        XCTAssertEqual(builtIn.collapsedScreenRect.midX, builtIn.notchScreenRect.midX)
    }

    func testThePeekDoesNotTakeOverTheMenuBar() {
        // It covers the menu bar wherever it is drawn, so it should claim the
        // dead space beside the cutout and not much more. matchnotch uses
        // 120pt wings; nothing here needs that room, and every extra point is
        // somebody's menu covered up.
        XCTAssertLessThan(builtIn.collapsedWidth, builtIn.screenFrame.width / 4)
        XCTAssertLessThanOrEqual(NotchGeometry.collapsedSideWidth, 96)
    }

    func testThePeekStaysInsideTheMenuBarStrip() {
        // Load-bearing, not cosmetic: a peek that hangs below the menu bar
        // overhangs a browser's tab bar, which is matchnotch's BUGS #73 and
        // the reason hover-to-expand ships off by default there.
        // It reaches a little past the menu-bar line, and only a little: the
        // physical cutout is taller than the inset, so a shell sized to the
        // inset exactly leaves the housing's edge showing (`housingOverhang`).
        // What matters is that it is nowhere near matchnotch's 26pt.
        XCTAssertEqual(builtIn.collapsedHeight,
                       builtIn.notchHeight + NotchGeometry.housingOverhang)
        XCTAssertLessThanOrEqual(NotchGeometry.housingOverhang, 4,
                                 "past a few points this is a peek that hangs into windows")
        XCTAssertEqual(builtIn.collapsedScreenRect.maxY, builtIn.screenFrame.maxY)
    }

    func testTheWindowIsWideEnoughForTheShouldersToOverhang() {
        // InverseCornerShape draws outside its own rect. A window sized to the
        // shell exactly clips both shoulders into square corners.
        XCTAssertEqual(builtIn.windowWidth,
                       builtIn.openWidth + NotchGeometry.shoulderRadius * 2)
        XCTAssertGreaterThan(builtIn.windowWidth, builtIn.collapsedWidth)
        XCTAssertEqual(builtIn.panelFrame().midX, builtIn.notchScreenRect.midX)
    }

    func testTheWindowHasAlmostNoSlackBelowThePanel() {
        // Every surplus point is a dead zone swallowing clicks while
        // setInteractive(true). Asserting the *gap* rather than the constant,
        // so growing the panel without growing the window also fails.
        let slack = builtIn.windowHeight - builtIn.openHeight
        XCTAssertGreaterThanOrEqual(slack, 0)
        XCTAssertLessThanOrEqual(slack, 24)
    }

    func testTheStayRegionIsWiderThanTheEntryRegionAndContainsIt() {
        // A small door in, a bigger one out (TRAPS #84).
        XCTAssertTrue(builtIn.hoverStayScreenRect.contains(builtIn.notchScreenRect))
        XCTAssertEqual(builtIn.hoverStayScreenRect.width,
                       builtIn.notchScreenRect.width + NotchGeometry.hoverStayMargin * 2)
        // And it must not reach the wings, or brushing the peek's content
        // counts as arriving. It is a leaving region only.
        XCTAssertLessThan(builtIn.hoverStayScreenRect.width, builtIn.collapsedWidth)
    }

    func testTheCaptureRectIsTopLeftOriginForScreencapture() {
        // screencapture -R counts y from the top; every other rect here counts
        // from the bottom, as NSEvent.mouseLocation does. Mixing them puts the
        // footprint check 1206pt below the notch, where it always passes.
        XCTAssertEqual(builtIn.captureRect.minY, 0)
        XCTAssertEqual(builtIn.captureRect.minX, builtIn.notchScreenRect.minX)
        XCTAssertEqual(builtIn.captureRect.size, builtIn.notchScreenRect.size)
    }

    /// A 13" MacBook Pro: no cutout, a 24pt menu bar.
    private let virtual = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        notchWidth: 0, notchHeight: 24, hasNotch: false)

    func testTheVirtualPeekIsJustItsTwoWingsInTheMenuBar() {
        XCTAssertEqual(virtual.collapsedWidth, 144)
        // Exactly the menu bar: no housing to overhang.
        XCTAssertEqual(virtual.collapsedHeight, 24)
        XCTAssertEqual(virtual.collapsedScreenRect.maxY, virtual.screenFrame.maxY)
        XCTAssertEqual(virtual.collapsedScreenRect.midX, virtual.screenFrame.midX)
    }

    func testTheVirtualPanelGrowsToTheNotchedWidthAndStartsBelowTheMenuBar() {
        XCTAssertEqual(virtual.openWidth, 352)
        XCTAssertEqual(virtual.openHeight, 172)
        XCTAssertEqual(virtual.windowWidth, 374)
        XCTAssertEqual(virtual.windowHeight, 188)
        XCTAssertEqual(virtual.notchExclusionTop, 24, "the title would sit in the menu bar")
        XCTAssertEqual(virtual.panelScreenRect.width, 352)
    }

    func testTheVirtualEntryIsExactlyThePeekAndWaitsFirst() {
        // With no cutout the notch rect is zero wide; entering through it
        // would never happen. And no margin: menus are under it.
        XCTAssertEqual(virtual.entryScreenRect, virtual.collapsedScreenRect)
        XCTAssertTrue(virtual.hoverStayScreenRect.contains(virtual.entryScreenRect))
        XCTAssertEqual(virtual.entryDwell, 0.3)
    }

    /// The hard rule: on a notched Mac every new property falls back to what
    /// was there before.
    func testNothingChangesOnANotchedScreen() {
        XCTAssertEqual(builtIn.openWidth, builtIn.collapsedWidth)
        XCTAssertEqual(builtIn.openHeight, 185)
        XCTAssertEqual(builtIn.windowHeight, 201)
        XCTAssertEqual(builtIn.windowWidth, 374)
        XCTAssertEqual(builtIn.notchExclusionTop, 37)
        XCTAssertEqual(builtIn.entryScreenRect, builtIn.notchScreenRect)
        XCTAssertEqual(builtIn.entryDwell, 0)
        // A notch whose inset is not 37 keeps the literal 185 too.
        let smaller = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                    notchWidth: 185, notchHeight: 32, hasNotch: true)
        XCTAssertEqual(smaller.openHeight, 185)
    }
}

/// Full-screen hiding asks the window list whether the menu bar is on the
/// display. Bounds are top-left origin, like `CGDisplayBounds`.
final class FullScreenTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1243)
    private let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

    private func window(_ rect: CGRect, layer: Int) -> [String: Any] {
        [kCGWindowLayer as String: layer,
         kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary]
    }

    func testTheMenuBarOnThisDisplayCountsAsShown() {
        // Measured on this Mac: the Window Server's menu bar, 1920x42.
        let bar = window(CGRect(x: 0, y: 0, width: 1920, height: 42), layer: menuLevel)
        XCTAssertTrue(AppController.menuBarShown([bar], display))
    }

    func testNoMenuBarMeansFullScreen() {
        // A full-screen window on a notched Mac stops below the notch
        // (TRAPS #49) -- which is why the menu bar is asked for instead.
        let app = window(CGRect(x: 0, y: 42, width: 1920, height: 1201), layer: 0)
        XCTAssertFalse(AppController.menuBarShown([app], display))
        XCTAssertFalse(AppController.menuBarShown([], display))
    }

    func testStatusItemsAndOtherDisplaysDoNotCount() {
        // Status items sit one level up, at the menu bar's height.
        let item = window(CGRect(x: 1318, y: 0, width: 38, height: 42), layer: menuLevel + 1)
        let elsewhere = window(CGRect(x: 1920, y: 0, width: 2560, height: 25), layer: menuLevel)
        XCTAssertFalse(AppController.menuBarShown([item, elsewhere], display))
    }
}

final class HoverRegionTests: XCTestCase {
    private let notch = CGRect(x: 856, y: 1206, width: 208, height: 37)
    private let stay = CGRect(x: 816, y: 1206, width: 288, height: 37)
    private let panel = CGRect(x: 760, y: 1059, width: 400, height: 184)

    /// All four combinations, without driving a real pointer.
    func testEntryIsTheCutoutAloneButLeavingTakesTheWiderRegion() {
        XCTAssertEqual(HoverWatcher.hoverRegion(notch: notch, stay: stay, active: nil,
                                                inside: false), notch)
        XCTAssertEqual(HoverWatcher.hoverRegion(notch: notch, stay: stay, active: nil,
                                                inside: true), stay)
    }

    func testAnOpenPanelOwnsTheRegionOutright() {
        // So the pointer can travel down to the transport buttons.
        XCTAssertEqual(HoverWatcher.hoverRegion(notch: notch, stay: stay, active: panel,
                                                inside: false), panel)
        XCTAssertEqual(HoverWatcher.hoverRegion(notch: notch, stay: stay, active: panel,
                                                inside: true), panel)
    }

    func testWithNoStayRegionLeavingFallsBackToTheCutout() {
        XCTAssertEqual(HoverWatcher.hoverRegion(notch: notch, stay: nil, active: nil,
                                                inside: true), notch)
    }

    // MARK: - Waiting: the dwell in, the grace out

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func step(hit: Bool, inside: Bool, since: Date?, at: Double, dwell: Double = 0.3)
        -> (inside: Bool, since: Date?) {
        HoverWatcher.step(hit: hit, inside: inside, since: since,
                          now: t0.addingTimeInterval(at), dwell: dwell,
                          grace: HoverWatcher.exitGrace)
    }

    func testWithNoDwellArrivingIsImmediate() {
        // Every notched Mac: exactly as before the dwell existed.
        let r = step(hit: true, inside: false, since: nil, at: 0, dwell: 0)
        XCTAssertTrue(r.inside)
        XCTAssertNil(r.since)
    }

    func testWithADwellThePointerHasToRestFirst() {
        var r = step(hit: true, inside: false, since: nil, at: 0)
        XCTAssertFalse(r.inside)
        r = step(hit: true, inside: r.inside, since: r.since, at: 0.2)
        XCTAssertFalse(r.inside, "0.2s is a sweep on the way to a menu")
        r = step(hit: true, inside: r.inside, since: r.since, at: 0.31)
        XCTAssertTrue(r.inside)
    }

    func testSweepingOffResetsTheDwell() {
        var r = step(hit: true, inside: false, since: nil, at: 0)
        r = step(hit: false, inside: r.inside, since: r.since, at: 0.2)
        XCTAssertNil(r.since, "leaving must not bank the time already spent")
        r = step(hit: true, inside: r.inside, since: r.since, at: 0.25)
        r = step(hit: true, inside: r.inside, since: r.since, at: 0.5)
        XCTAssertFalse(r.inside, "0.25s since coming back, not 0.5s")
    }

    func testLeavingStillWaitsOutTheGrace() {
        var r = step(hit: false, inside: true, since: nil, at: 0)
        XCTAssertTrue(r.inside)
        r = step(hit: false, inside: r.inside, since: r.since, at: HoverWatcher.exitGrace - 0.01)
        XCTAssertTrue(r.inside)
        r = step(hit: false, inside: r.inside, since: r.since, at: HoverWatcher.exitGrace)
        XCTAssertFalse(r.inside)
    }

    func testAPointInTheWingIsNotAnEntryPoint() {
        // The wings are where the album art and the waveform are drawn, which
        // is where the pointer naturally lands on its way past. Lighting the
        // peek from there is BUGS #73.
        let inWing = CGPoint(x: 800, y: 1220)
        XCTAssertTrue(panel.contains(inWing))
        XCTAssertFalse(HoverWatcher.hoverRegion(notch: notch, stay: stay, active: nil,
                                                inside: false).contains(inWing))
    }
}

/// The frame probe's arithmetic. The measurement is a deliverable of milestone
/// 7, and an unchecked measurement is how this project has been wrong before.
final class FrameProbeTests: XCTestCase {
    private func samples(_ offsets: [Double], heights: [CGFloat])
    -> [(at: Date, height: CGFloat)] {
        let base = Date()
        return zip(offsets, heights).map { (base.addingTimeInterval($0), $1) }
    }

    func testFramesPerSecondCountsIntervalsNotFrames() {
        // Two frames a sixtieth apart is one interval of evidence: 60fps, not
        // 120. Ten frames spanning 0.15s is nine intervals -> 60fps.
        let ten = samples((0..<10).map { Double($0) * 0.0166667 },
                          heights: (0..<10).map { 37 + CGFloat($0) * 16 })
        let line = FrameProbe.describe(ten)
        XCTAssertTrue(line.contains("10 frames"), line)
        XCTAssertTrue(line.contains("60.0 fps"), line)
    }

    func testAnExpandAndACollapseAreTwoBurstsNotAnAverage() {
        let two = samples([0, 0.02, 0.04, 2.0, 2.02, 2.04],
                          heights: [37, 110, 185, 185, 110, 37])
        let report = FrameProbe.describe(two)
        XCTAssertEqual(report.split(separator: "\n").count, 2, report)
        XCTAssertTrue(report.contains("37 -> 185"), report)
        XCTAssertTrue(report.contains("185 -> 37"), report)
    }

    /// One layout pass is not an animation, and reporting it as "1 frame,
    /// 0.000s" would read as a catastrophic result rather than as no result.
    func testASingleLayoutPassIsNotReportedAsAnAnimation() {
        XCTAssertEqual(FrameProbe.describe(samples([0], heights: [37])), "probe: no frames")
        XCTAssertEqual(FrameProbe.describe([]), "probe: no frames")
    }
}

/// Which Macs get a notch drawn. Only the first case is reachable on the Mac
/// this is developed on, which is why the rule is a pure function.
final class NotchPresenceTests: XCTestCase {
    func testAnyScreenWithATopInsetHasTheNotch() {
        XCTAssertEqual(NotchPresence.of([(builtIn: true, topInset: 37)]), .present)
        // Lid open with an external monitor too: the built-in still counts.
        XCTAssertEqual(NotchPresence.of([(builtIn: false, topInset: 0),
                                         (builtIn: true, topInset: 32)]), .present)
    }

    func testABuiltInScreenWithoutACutoutHasNoNotch() {
        // A 13" MacBook Pro or an M1 Air.
        XCTAssertEqual(NotchPresence.of([(builtIn: true, topInset: 0)]), .noNotch)
        XCTAssertEqual(NotchPresence.of([(builtIn: true, topInset: 0),
                                         (builtIn: false, topInset: 0)]), .noNotch)
    }

    func testNoBuiltInScreenIsItsOwnAnswer() {
        // A Mac mini, or a MacBook with the lid shut.
        XCTAssertEqual(NotchPresence.of([(builtIn: false, topInset: 0)]), .noBuiltInScreen)
        XCTAssertEqual(NotchPresence.of([]), .noBuiltInScreen)
    }
}

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
                       builtIn.collapsedWidth + NotchGeometry.shoulderRadius * 2)
        XCTAssertGreaterThan(builtIn.windowWidth, builtIn.collapsedWidth)
        XCTAssertEqual(builtIn.panelFrame().midX, builtIn.notchScreenRect.midX)
    }

    func testTheWindowHasAlmostNoSlackBelowThePanel() {
        // Every surplus point is a dead zone swallowing clicks while
        // setInteractive(true). Asserting the *gap* rather than the constant,
        // so growing the panel without growing the window also fails.
        let slack = NotchGeometry.windowHeight - NotchGeometry.panelHeight
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

    func testAScreenWithNoNotchReportsNoNotch() {
        let external = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                     notchWidth: 0, notchHeight: 24, hasNotch: false)
        XCTAssertFalse(external.hasNotch)
        // The user's choice: built-in only. There is no pill fallback to get
        // wrong, so the exclusion band is zero and the app draws nothing.
        XCTAssertEqual(external.notchExclusionTop, 0)
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

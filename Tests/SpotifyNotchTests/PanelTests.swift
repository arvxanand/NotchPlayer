import XCTest
@testable import SpotifyNotchCore

private let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                     notchWidth: 208, notchHeight: 37, hasNotch: true)

final class ExpansionTests: XCTestCase {
    /// Pure, so all the combinations can be asserted without driving a real
    /// pointer at a real window.
    func testItOpensOnlyWhenThereIsSomethingToOpenInto() {
        XCTAssertTrue(Expansion.shouldExpand(inside: true, hasContent: true, expanded: false))
        // Brushing the cutout while nothing is playing must not open an empty
        // panel -- the notch should look like a notch.
        XCTAssertFalse(Expansion.shouldExpand(inside: true, hasContent: false, expanded: false))
        XCTAssertFalse(Expansion.shouldExpand(inside: false, hasContent: true, expanded: false))
    }

    func testAnOpenPanelStaysOpenWhenTheTrackEnds() {
        // Closing must never require content. Otherwise a track ending while
        // the panel is open would strand it there with nothing to draw and no
        // way to shut it.
        XCTAssertTrue(Expansion.shouldExpand(inside: true, hasContent: false, expanded: true))
        XCTAssertFalse(Expansion.shouldExpand(inside: false, hasContent: false, expanded: true))
        XCTAssertFalse(Expansion.shouldExpand(inside: false, hasContent: true, expanded: true))
    }
}

final class PanelLayoutTests: XCTestCase {
    /// **The constant and the layout must agree.** `NotchGeometry.panelHeight`
    /// is what the shell is framed to and what the hover region is computed
    /// from; `PanelView.height` is what the content actually adds up to. If
    /// they drift, the last row is clipped or there is a band of dead space
    /// swallowing clicks -- and neither shows up as an error.
    func testThePanelHeightConstantMatchesWhatTheLayoutAddsUpTo() {
        XCTAssertEqual(NotchGeometry.panelHeight, PanelView.height(geometry))
    }

    func testTheTransportRowFitsThePanel() {
        XCTAssertLessThan(TransportRow.width, geometry.collapsedWidth - PanelView.inset * 2)
        // Centres 56pt apart: close enough to read as one control, far enough
        // that a trackpad miss does not skip a track when it meant to pause.
        XCTAssertEqual(TransportRow.centreToCentre, 56)
    }

    /// Every transport target is the HIG minimum. The glyphs are smaller on
    /// purpose -- drawn size and tappable size are different questions, and
    /// conflating them is what made matchnotch's targets a seventh of their
    /// intended area.
    func testEveryTransportTargetMeetsTheMinimum() {
        XCTAssertGreaterThanOrEqual(NotchGeometry.minimumHitHeight, 44)
        for glyph in [TransportRow.sideGlyph, TransportRow.centreGlyph] {
            XCTAssertLessThan(glyph, NotchGeometry.minimumHitHeight,
                              "a glyph drawn at its target size leaves no padding to miss into")
        }
        // The audit emits one check per button from the same constant.
        let json = AuditReport.json()
        for name in ["transport-previous", "transport-playpause", "transport-next"] {
            XCTAssertTrue(json.contains(name), "\(name) is drawn but never audited")
        }
    }

    /// **A fixed-height parent turns an overflow into a squeeze**, and only
    /// one of those is visible. The text column is pinned to the cover's
    /// height, so if its contents ever exceed that, SwiftUI crushes the
    /// flexible spacer and every automated check keeps agreeing all is well
    /// (matchnotch TRAPS #90). This is the check that notices.
    func testTheTextColumnFitsBesideTheCover() {
        XCTAssertLessThan(PanelView.detailsFixedHeight, PanelView.artSide,
                          "the column needs \(PanelView.detailsFixedHeight)pt "
                          + "and has \(PanelView.artSide)")
        // And there should be real slack, not a single point of it.
        XCTAssertGreaterThan(PanelView.artSide - PanelView.detailsFixedHeight, 8)
    }

    func testTheTextColumnHasRoomForATitle() {
        let width = PanelView.detailsWidth(geometry)
        XCTAssertGreaterThan(width, 180, "a 17pt title needs more room than \(width)pt")
        // Derived from the same numbers the layout uses, so a wider cover or a
        // bigger inset cannot leave the two disagreeing.
        XCTAssertEqual(width + PanelView.artSide + PanelView.gap + PanelView.inset * 2,
                       geometry.collapsedWidth)
    }

    func testThePanelIsTallerThanThePeekAndFitsItsWindow() {
        XCTAssertGreaterThan(NotchGeometry.panelHeight, geometry.collapsedHeight)
        XCTAssertGreaterThanOrEqual(NotchGeometry.windowHeight, NotchGeometry.panelHeight)
        // Every surplus point is a dead zone swallowing clicks while the panel
        // is interactive.
        XCTAssertLessThanOrEqual(NotchGeometry.windowHeight - NotchGeometry.panelHeight, 24)
    }

    func testNothingLegibleCanSitInTheCameraBand() {
        // The panel reserves the housing's full height before drawing
        // anything. The footprint check proves it per state; this proves the
        // constant it depends on has not been trimmed.
        XCTAssertEqual(geometry.notchExclusionTop, geometry.notchHeight)
        XCTAssertGreaterThan(NotchGeometry.panelHeight,
                             geometry.notchExclusionTop + PanelView.artSide)
    }

    func testTheCornerGrowsWithThePanel() {
        let closed = Shell.bottomRadius(expanded: false)
        let open = Shell.bottomRadius(expanded: true)
        XCTAssertGreaterThan(open, closed)
        // A radius larger than half the strip eats the whole shape.
        XCTAssertLessThanOrEqual(closed, geometry.collapsedHeight / 2)
        XCTAssertLessThanOrEqual(open, NotchGeometry.panelHeight / 2)
    }

    /// **Do the division before writing the code, not after.** The number that
    /// decides whether motion looks fluid is points-per-frame, not duration.
    ///
    /// The bound is traceable rather than invented: matchnotch measured a
    /// 300pt push over 0.32s -- about **940pt/s** -- as visibly jagged, and
    /// the complaint was always "jaggedy at the beginning" because a spring
    /// peaks at the start. Half of that is the budget here. The first version
    /// of this test used a made-up per-frame ceiling that a legitimate panel
    /// height would have failed, which is a test dictating the design rather
    /// than protecting it.
    static let measuredBadVelocity: CGFloat = 940

    func testTheExpandAnimationIsWellUnderTheVelocityThatLooksJagged() {
        let travel = NotchGeometry.panelHeight - geometry.collapsedHeight
        let response: CGFloat = 0.38              // Motion.spring's response
        let velocity = travel / response
        XCTAssertLessThan(velocity, Self.measuredBadVelocity / 2,
                          "\(travel)pt in \(response)s is \(velocity)pt/s; "
                          + "\(Self.measuredBadVelocity)pt/s was measured as jagged")
    }
}

final class CheckSpecTests: XCTestCase {
    /// The shell script asks the binary what to capture. This asserts the
    /// derivation rather than a count somebody has to keep editing.
    func testEveryDrawingStateIsCheckedCollapsedAndExpanded() {
        let specs = PreviewData.checkSpecs
        for state in PreviewData.drawing {
            XCTAssertTrue(specs.contains("--preview \(state.name)"), state.name)
            XCTAssertTrue(specs.contains("--preview \(state.name) --expanded"), state.name)
        }
        XCTAssertEqual(specs.count, PreviewData.drawing.count * 2)
    }

    func testStatesThatDrawNothingAreNeverCaptured() {
        // Capturing one would photograph the desktop through a transparent
        // window and fail for a reason that has nothing to do with the panel.
        for state in PreviewData.all
        where !Presentation.of(now: state.now, permission: state.permission,
                               source: state.source).draws {
            XCTAssertFalse(PreviewData.checkSpecs.contains { $0.contains(state.name) },
                           "\(state.name) draws nothing and must not be captured")
        }
    }

    func testEveryPanelBranchHasAState() {
        let states = PreviewData.all
        XCTAssertTrue(states.contains { ($0.now.track?.name.count ?? 0) > 40 },
                      "no long title -- truncation is never looked at")
        XCTAssertTrue(states.contains { !($0.now.track?.name.allSatisfy(\.isASCII) ?? true) },
                      "no non-Latin title -- font fallback is never looked at")
        // A preview sized exactly to a limit hides the limit.
        let longest = states.compactMap { $0.now.track?.name.count }.max() ?? 0
        XCTAssertGreaterThan(longest, 60, "the longest preview title is only \(longest) characters")
    }

    func testAPinnedPreviewHasAStoppedClock() {
        // `advancing: false` is what makes a capture reproducible; a running
        // clock means two runs photograph two different progress bars.
        for state in PreviewData.all {
            guard let progress = state.progress else { continue }
            XCTAssertFalse(progress.advancing, "\(state.name) has a running clock")
        }
    }
}

final class TransportTests: XCTestCase {
    private let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                         notchWidth: 208, notchHeight: 37, hasNotch: true)

    /// The glyph shows the state, and the label names the action. They are
    /// deliberately opposite, which is why both get asserted.
    func testAPlayingTrackShowsPauseAndAPausedOneShowsPlay() {
        XCTAssertEqual(TransportRow.playPauseSymbol(playing: true), "pause.fill")
        XCTAssertEqual(TransportRow.playPauseSymbol(playing: false), "play.fill")
        XCTAssertEqual(TransportRow.playPauseLabel(playing: true), "Pause")
        XCTAssertEqual(TransportRow.playPauseLabel(playing: false), "Play")
    }

    func testTheThreeTargetsAreEvenlySpacedAndDoNotTouch() {
        let rects = PanelView.transportRects(geometry)
        XCTAssertEqual(rects.map(\.name), ["previous", "playpause", "next"])
        for (a, b) in zip(rects, rects.dropFirst()) {
            XCTAssertEqual(b.rect.midX - a.rect.midX, TransportRow.centreToCentre)
            // A gap between them, so a trackpad miss lands on nothing rather
            // than on the next track.
            XCTAssertFalse(a.rect.intersects(b.rect))
            XCTAssertEqual(b.rect.minX - a.rect.maxX, TransportRow.gap)
        }
    }

    func testTheClusterIsCentredOnTheCutout() {
        let rects = PanelView.transportRects(geometry)
        XCTAssertEqual(rects[1].rect.midX, geometry.notchScreenRect.midX)
        XCTAssertEqual(rects[1].rect.midX, geometry.screenFrame.midX)
    }

    /// The probe script aims real clicks at these. If the arithmetic here
    /// wandered outside the panel, every probe would report "no effect" and
    /// look like a broken button rather than a broken rect.
    func testEveryTargetLandsInsideThePanelAndBelowTheCamera() {
        let panel = CGRect(x: geometry.screenFrame.midX - geometry.collapsedWidth / 2,
                           y: 0, width: geometry.collapsedWidth,
                           height: NotchGeometry.panelHeight)
        for (name, rect) in PanelView.transportRects(geometry) {
            XCTAssertTrue(panel.contains(rect), "\(name) at \(rect) is outside \(panel)")
            XCTAssertGreaterThanOrEqual(rect.minY, geometry.notchExclusionTop,
                                        "\(name) reaches under the camera housing")
        }
    }

    func testTheTargetsAreWhereTheLayoutPutsThem() {
        // Derived from the same constants the HStack lays out with, so the
        // arithmetic and the layout cannot drift without this noticing.
        let rects = PanelView.transportRects(geometry)
        XCTAssertEqual(rects.first!.rect.width, NotchGeometry.minimumHitHeight)
        XCTAssertEqual(rects.map(\.rect.maxX).max()! - rects.map(\.rect.minX).min()!,
                       TransportRow.width)
        XCTAssertEqual(rects[0].rect.minY,
                       geometry.notchExclusionTop + PanelView.topGap
                       + PanelView.artSide + PanelView.transportGap)
    }
}

/// Dragging the progress line to seek. The arithmetic and the two rules that
/// keep a drag from being taken away mid-gesture.
final class ScrubTests: XCTestCase {

    // MARK: - Where a pointer lands

    func testAPointerLandsWhereItIsInTheTrack() {
        XCTAssertEqual(ProgressLine.fraction(atX: 0, width: 280), 0, accuracy: 0.0001)
        XCTAssertEqual(ProgressLine.fraction(atX: 140, width: 280), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ProgressLine.fraction(atX: 280, width: 280), 1, accuracy: 0.0001)
    }

    /// A drag that carries on past either end means the start or the end,
    /// which is what the hand doing it intends.
    func testADragPastTheEndsClampsRatherThanOvershooting() {
        XCTAssertEqual(ProgressLine.fraction(atX: -300, width: 280), 0)
        XCTAssertEqual(ProgressLine.fraction(atX: 9000, width: 280), 1)
    }

    func testAZeroWidthTrackCannotProduceANaN() {
        XCTAssertEqual(ProgressLine.fraction(atX: 40, width: 0), 0)
        XCTAssertEqual(ProgressLine.fraction(atX: .nan, width: 280), 0)
    }

    /// The hit band is far taller than the line, or nobody can grab it -- and
    /// it must stay clear of the transport row, which owns the clicks below.
    /// The band has to be big enough to hit without aiming, and it must stop
    /// short of the transport row, which owns the clicks below it.
    func testTheDraggableBandIsGenerousAndStillClearsTheTransportRow() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                     notchWidth: 208, notchHeight: 37, hasNotch: true)
        XCTAssertGreaterThanOrEqual(ProgressLine.hitHeight, 28,
                                    "20pt was measurably too small in the hand")

        let band = PanelView.progressRect(geometry)
        // The capture says the line's centre is 103pt from the top of the
        // window. A probe that aims anywhere else tests nothing.
        XCTAssertEqual(band.midY, 103, accuracy: 0.5)
        let transportTop = PanelView.transportRects(geometry).map(\.rect.minY).min() ?? 0
        XCTAssertLessThan(band.maxY, transportTop,
                          "the scrub band reaches into the transport buttons")
        XCTAssertGreaterThan(transportTop - band.maxY, 8, "no margin between the two targets")
        // Centred on the line, not hanging off it. Probed live at both edges:
        // 12pt either side seeks, 17 above and 19 below do not.
        XCTAssertEqual(band.midY - band.minY, band.maxY - band.midY, accuracy: 0.01)
        XCTAssertEqual(ProgressLine.pad, (ProgressLine.hitHeight - ProgressLine.thickness) / 2)
    }

    // MARK: - The panel staying open

    /// A drag that leaves the panel is ordinary: the pointer runs past the
    /// bottom edge while the hand keeps going. Collapsing then would take the
    /// control out from under it.
    func testADragHoldsTheOpenPanelOpenWhenThePointerLeaves() {
        XCTAssertTrue(Expansion.shouldExpand(inside: false, hasContent: true,
                                             expanded: true, holding: true))
        // And the moment it is released, leaving means leaving again.
        XCTAssertFalse(Expansion.shouldExpand(inside: false, hasContent: true,
                                              expanded: true, holding: false))
    }

    /// Holding cannot *open* anything. A drag has to start on the panel, so a
    /// stuck flag must not be able to pin an empty notch open.
    func testHoldingCannotOpenAClosedPanel() {
        XCTAssertFalse(Expansion.shouldExpand(inside: false, hasContent: true,
                                              expanded: false, holding: true))
        XCTAssertFalse(Expansion.shouldExpand(inside: true, hasContent: false,
                                              expanded: false, holding: true))
    }

    // MARK: - The command

    func testSeekWritesThePositionInSecondsWithADecimalPoint() {
        let source = SpotifyBridge.Command.seek(42.5).source
        XCTAssertTrue(source.contains("set player position to 42.500"), source)
        XCTAssertFalse(source.contains(","), "a comma decimal parses as an AppleScript list")
        XCTAssertFalse(source.contains("e+"), "exponent notation does not parse")
    }

    /// Doubles print as exponents past a certain size, and AppleScript cannot
    /// read that. A 90-minute DJ set is a real track length.
    func testALongTrackStillProducesPlainDigits() {
        for seconds in [0.0, 0.0001, 5400.0, 99999.5] {
            let source = SpotifyBridge.Command.seek(seconds).source
            XCTAssertFalse(source.contains("e+"), source)
            XCTAssertFalse(source.contains("-"), "negative positions are clamped: \(source)")
        }
        // `contains("0.000")` passed "-10.000" here, which is the string this
        // assertion exists to reject. Anchor it to the end.
        XCTAssertTrue(SpotifyBridge.Command.seek(-10).source.hasSuffix("position to 0.000"),
                      SpotifyBridge.Command.seek(-10).source)
    }

    /// Every other script is compiled once and held forever. A seek carries
    /// its argument in its source, so caching it would grow a dictionary of
    /// near-identical scripts for the life of the process.
    func testSeekScriptsAreNotCachedAndTheFixedOnesAre() {
        XCTAssertFalse(SpotifyBridge.Command.seek(1).cacheable)
        for command in SpotifyBridge.Command.simple { XCTAssertTrue(command.cacheable) }
    }

    func testEveryCommandHasAName() {
        for command in SpotifyBridge.Command.simple + [.seek(1)] {
            XCTAssertFalse(command.name.isEmpty)
        }
    }
}

import XCTest
@testable import NotchPlayerCore

final class ArtworkURLTests: XCTestCase {
    private let cover = URL(string:
        "https://i.scdn.co/image/ab67616d0000b273e045aa197ada995407bf92fc")!

    func testTheSixHundredAndFortyPixelURLIsRewrittenToThreeHundred() {
        // `artwork url` hands over the 640px variant -- 226KB measured -- to
        // draw a 25pt thumbnail.
        let fetched = ArtworkCache.fetchURL(for: cover)
        XCTAssertEqual(fetched.lastPathComponent,
                       "ab67616d00001e02e045aa197ada995407bf92fc")
        XCTAssertEqual(fetched.host, cover.host)
        // The hash after the prefix is the identity of the image and must
        // survive untouched, or the swap silently fetches a different album.
        XCTAssertEqual(fetched.lastPathComponent.dropFirst(16),
                       cover.lastPathComponent.dropFirst(16))
    }

    func testAnUnfamiliarPrefixIsLeftAlone() {
        // Podcast and playlist images use different prefixes. A blind
        // 16-character swap would turn them into a 404 -- which, since the
        // loader validates the body, shows up as a missing cover rather than
        // as anything resembling an error.
        for other in ["https://i.scdn.co/image/ab6765630000ba8a1234567890abcdef12345678",
                      "https://i.scdn.co/image/short",
                      "https://example.com/cover.jpg"] {
            let url = URL(string: other)!
            XCTAssertEqual(ArtworkCache.fetchURL(for: url), url, other)
        }
    }

    func testRewritingIsIdempotent() {
        // The service may hand back a URL that has already been through this.
        let once = ArtworkCache.fetchURL(for: cover)
        XCTAssertEqual(ArtworkCache.fetchURL(for: once), once)
    }

    func testTwoAlbumsCannotCollideOnDisk() {
        let a = URL(string: "https://i.scdn.co/image/ab67616d0000b273aaaa")!
        let b = URL(string: "https://i.scdn.co/image/ab67616d0000b273bbbb")!
        XCTAssertNotEqual(ArtworkCache.filename(for: a), ArtworkCache.filename(for: b))
        // And the name must be a single flat path component.
        XCTAssertFalse(ArtworkCache.filename(for: a).contains("/"))
    }

    /// **The collision that actually happens**, and the one the first version
    /// of the test above missed: two different URLs whose *last components*
    /// match. A mutation keying the filename on `lastPathComponent` stayed
    /// green against two URLs that differed in their last component, which is
    /// no test of a collision at all. matchnotch hit this as two clubs both
    /// wearing whichever badge was cached as `500.png` first.
    func testTwoHostsSharingAFilenameDoNotShareACacheEntry() {
        let a = URL(string: "https://i.scdn.co/image/cover.jpg")!
        let b = URL(string: "https://mosaic.scdn.co/image/cover.jpg")!
        XCTAssertEqual(a.lastPathComponent, b.lastPathComponent, "premise of this test")
        XCTAssertNotEqual(ArtworkCache.filename(for: a), ArtworkCache.filename(for: b))
    }
}

final class ArtMemoryTests: XCTestCase {
    /// A real PNG, built here rather than checked in, because what is being
    /// tested is the decode-and-shrink path rather than any particular image.
    private func png(_ side: Int) -> Data {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    func testAnOversizedCoverIsShrunkToWhatIsActuallyDrawn() {
        let out = ArtMemory.downscaled(png(600))
        let side = try! XCTUnwrap(out).size
        XCTAssertLessThanOrEqual(max(side.width, side.height), ArtMemory.maxPixels)
        // Square in, square out -- a stretched cover is worse than none.
        XCTAssertEqual(side.width, side.height, accuracy: 1)
    }

    func testAnAlreadySmallCoverIsNotUpscaled() {
        let side = try! XCTUnwrap(ArtMemory.downscaled(png(64))).size
        XCTAssertEqual(side.width, 64, accuracy: 1)
    }

    func testBytesThatAreNotAnImageDecodeToNothing() {
        // HTTP 200 is not "the image exists": matchnotch's image host answers
        // an unknown id with 200 and a 263-byte XML error document.
        XCTAssertNil(ArtMemory.downscaled(Data("<Error>NoSuchKey</Error>".utf8)))
        XCTAssertNil(ArtMemory.downscaled(Data()))
    }
}

final class BandsTests: XCTestCase {
    func testSyntheticBarsAreDeterministic() {
        // A preview render has to be identical run to run, or a check that
        // compares pictures is comparing two different ones.
        XCTAssertEqual(Bands.synthetic(at: 12.5), Bands.synthetic(at: 12.5))
        XCTAssertNotEqual(Bands.synthetic(at: 12.5), Bands.synthetic(at: 12.9))
    }

    func testSyntheticBarsStayInRangeOverALongRun() {
        for step in 0..<4000 {
            let values = Bands.synthetic(at: Double(step) * 0.037)
            XCTAssertEqual(values.count, Bands.count)
            for v in values {
                XCTAssertGreaterThanOrEqual(v, 0)
                XCTAssertLessThanOrEqual(v, 1)
            }
        }
    }

    func testSyntheticBarsAreBassTilted() {
        // A flat distribution reads as a row of identical twitching sticks,
        // not as a spectrum. Averaged over a long run so this is about the
        // tilt rather than about one frame.
        var low = 0.0, high = 0.0
        let third = Bands.count / 3
        for step in 0..<2000 {
            let v = Bands.synthetic(at: Double(step) * 0.041)
            low += Double(v.prefix(third).reduce(0, +))
            high += Double(v.suffix(third).reduce(0, +))
        }
        XCTAssertGreaterThan(low, high * 1.3, "bass should dominate: \(low) vs \(high)")
    }

    func testTheEnvelopeRisesFasterThanItFalls() {
        let up = Bands.envelope([0, 0], toward: [1, 1])
        let down = Bands.envelope([1, 1], toward: [0, 0])
        XCTAssertGreaterThan(up[0], 1 - down[0],
                             "attack must outrun decay or transients are lost")
    }

    func testTheEnvelopeConvergesAndNeverLeavesRange() {
        var values = Bands.silent
        for _ in 0..<200 { values = Bands.envelope(values, toward: [Float](repeating: 1, count: Bands.count)) }
        for v in values { XCTAssertEqual(v, 1, accuracy: 0.01) }
        for v in Bands.envelope([0.5], toward: [99]) { XCTAssertLessThanOrEqual(v, 1) }
        for v in Bands.envelope([0.5], toward: [-99]) { XCTAssertGreaterThanOrEqual(v, 0) }
    }

    func testMismatchedCountsTakeTheTargetRatherThanCrashing() {
        // The tap's band count can change if the format does; dropping the
        // smoothing for one frame is better than an index out of range in an
        // audio callback.
        XCTAssertEqual(Bands.envelope([0, 0], toward: [1, 1, 1]), [1, 1, 1])
    }
}

final class PeekLayoutTests: XCTestCase {
    private let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                         notchWidth: 208, notchHeight: 37, hasNotch: true)

    func testEachWingHoldsItsContentWithoutReachingTheCutout() {
        // The wings are equal and sized to the wider requirement. If content
        // grows past this, it is drawn under the camera housing, where it is
        // invisible on real hardware and nobody would notice from the code.
        let needed = PeekView.cutoutInset + PeekView.contentWidth
        XCTAssertLessThanOrEqual(needed, NotchGeometry.collapsedSideWidth,
                                 "a wing needs \(needed)pt and has \(NotchGeometry.collapsedSideWidth)")
    }

    func testTheWaveformIsTheWiderOfTheTwoWings() {
        // Documents which side sets the wing width, so a change to the other
        // one does not silently start setting it.
        XCTAssertEqual(PeekView.contentWidth, WaveformView.width)
        XCTAssertGreaterThan(WaveformView.width,
                             PeekView.markSide + PeekView.markGap + PeekView.artSide)
    }

    func testNothingInThePeekIsTallerThanTheStrip() {
        for height in [PeekView.artSide, PeekView.markSide,
                       WaveformView.defaultHeight.upperBound] {
            XCTAssertLessThan(height, geometry.collapsedHeight,
                              "\(height)pt does not fit a \(geometry.collapsedHeight)pt strip")
        }
    }

    func testTheWaveformWidthMatchesTheBarsItDraws() {
        // Derived, not written twice: the last bar has no gap after it.
        XCTAssertEqual(WaveformView.width,
                       CGFloat(Bands.count) * WaveformView.barWidth
                       + CGFloat(Bands.count - 1) * WaveformView.gap)
    }

    func testSilentBarsAreStillVisible() {
        // Paused draws a row of dots, which is what says "paused" without a
        // second glyph. A zero-height bar would say nothing at all.
        XCTAssertGreaterThan(WaveformView.defaultHeight.lowerBound, 0)
    }
}

final class PreviewDataTests: XCTestCase {
    func testAnUnknownStateNameIsNil() {
        // matchnotch's equivalent falls through to `default: .idle`, so a
        // typo renders a blank notch and reads as a bug in the app rather
        // than a bug in the command line.
        XCTAssertNil(PreviewData.named("playin"))
        XCTAssertNil(PreviewData.named(""))
        XCTAssertNotNil(PreviewData.named("playing"))
    }

    func testEveryStateIsNamedOnceAndCaptioned() {
        XCTAssertEqual(Set(PreviewData.names).count, PreviewData.all.count)
        for state in PreviewData.all {
            XCTAssertFalse(state.caption.isEmpty, "\(state.name) has no caption")
            XCTAssertFalse(state.name.contains(" "), "\(state.name) would split in the shell")
        }
    }

    /// The check script asks the binary which states to capture. This is what
    /// stops that set quietly growing to include one that draws nothing --
    /// which would capture the desktop through a transparent window and fail
    /// for a reason that has nothing to do with the panel.
    func testTheCheckedSetIsExactlyTheStatesThatDraw() {
        // **Asked of `Presentation`, not of `Now`.** `nopermission` has no
        // track and still draws -- that is the whole point of it -- so keying
        // this off `now.draws` would quietly drop the one state that exists
        // to stop the app failing silently.
        XCTAssertEqual(
            Set(PreviewData.drawing.map(\.name)),
            Set(PreviewData.all
                .filter { Presentation.of(now: $0.now, permission: $0.permission).draws }
                .map(\.name)))
        XCTAssertEqual(Set(PreviewData.all.map(\.name))
                        .subtracting(PreviewData.drawing.map(\.name)),
                       ["stopped", "notrunning"])
        XCTAssertTrue(PreviewData.drawing.contains { $0.name == "nopermission" })
    }

    func testEveryBranchThePeekCanDrawHasAState() {
        let states = PreviewData.all
        XCTAssertTrue(states.contains { $0.now.isPlaying }, "no playing state")
        XCTAssertTrue(states.contains { if case .track(_, .paused, _) = $0.now { return true }
                                        else { return false } }, "no paused state")
        XCTAssertTrue(states.contains { $0.now.track?.artworkURL == nil && $0.now.draws },
                      "no state without a cover -- the placeholder is never looked at")
        XCTAssertTrue(states.contains { $0.now == .notRunning }, "no Spotify-closed state")
        XCTAssertTrue(states.contains { $0.now == .stopped }, "no nothing-loaded state")
        // Both ends of the bar geometry, not just the middle.
        XCTAssertTrue(states.contains { ($0.bands?.max() ?? 0) > 0.9 }, "no loud state")
        XCTAssertTrue(states.contains { b in (b.bands.map { $0.allSatisfy { $0 < 0.35 } } ?? false) },
                      "no quiet state")
    }
}

final class OneMarkTests: XCTestCase {
    private let cover = URL(string: "https://i.scdn.co/image/ab67616d0000b273aaaa")

    /// **The invariant a capture found and the code did not.** Rendering the
    /// `noart` state showed two Spotify logos side by side -- the standalone
    /// mark plus the mark standing in for the missing cover -- and every test
    /// at the time was green.
    func testExactlyOneSpotifyMarkIsEverDrawn() {
        for url in [cover, nil] {
            for hasImage in [true, false] {
                // A decoded image with no URL cannot happen; the memory is
                // keyed by URL.
                if url == nil && hasImage { continue }
                let standalone = PeekView.showsStandaloneMark(artworkURL: url)
                let placeholder = ArtworkView.showsPlaceholderMark(url: url, hasImage: hasImage)
                XCTAssertNotEqual(standalone, placeholder,
                                  "url=\(String(describing: url)) hasImage=\(hasImage) "
                                  + "draws \(standalone && placeholder ? "two" : "no") marks")
            }
        }
    }

    func testAPendingCoverDrawsNeitherAMarkNorAGap() {
        // The case that made the bug subtle: with a URL but no image yet, the
        // square is empty and the standalone mark carries the branding. An
        // empty square is invisible on black, so nothing moves when the cover
        // arrives.
        XCTAssertTrue(PeekView.showsStandaloneMark(artworkURL: cover))
        XCTAssertFalse(ArtworkView.showsPlaceholderMark(url: cover, hasImage: false))
    }

    func testATrackWithNoCoverPutsTheMarkWhereTheCoverWouldBe() {
        XCTAssertFalse(PeekView.showsStandaloneMark(artworkURL: nil))
        XCTAssertTrue(ArtworkView.showsPlaceholderMark(url: nil, hasImage: false))
    }
}

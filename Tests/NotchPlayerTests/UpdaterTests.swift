import XCTest
@testable import NotchPlayerCore

final class UpdaterTests: XCTestCase {
    func testTheRealReleaseJSONGivesTheVersionPageAndDmg() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/release-latest", withExtension: "json"))
        let release = try Updater.Release.parse(Data(contentsOf: url))
        XCTAssertEqual(release.version, "0.2")
        XCTAssertEqual(release.htmlUrl.absoluteString, "https://github.com/arvxanand/NotchPlayer/releases/tag/v0.2")
        XCTAssertEqual(release.dmg?.absoluteString,
                       "https://github.com/arvxanand/NotchPlayer/releases/download/v0.2/NotchPlayer.dmg")
    }

    func testNewerIsNumericNotAlphabetical() {
        XCTAssertTrue(Updater.isNewer("0.3", than: "0.2"))
        XCTAssertTrue(Updater.isNewer("0.10", than: "0.9"))
        XCTAssertTrue(Updater.isNewer("0.3.1", than: "0.3"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.9"))
        XCTAssertFalse(Updater.isNewer("0.3", than: "0.3"))
        XCTAssertFalse(Updater.isNewer("0.2", than: "0.3"))
    }

    func testWhoUpdatesThemselves() {
        let app = "/Applications/NotchPlayer.app"
        XCTAssertEqual(Updater.placement(version: "0.3", bundlePath: app, writable: true, brew: false), .inPlace)
        // brew upgrade keeps track of the version; an app that swapped itself would lose it.
        XCTAssertEqual(Updater.placement(version: "0.3", bundlePath: app, writable: true, brew: true), .hidden)
        // make_app.sh's default: a local build.
        XCTAssertEqual(Updater.placement(version: "0.1", bundlePath: app, writable: true, brew: false), .hidden)
        // Not an admin.
        XCTAssertEqual(Updater.placement(version: "0.3", bundlePath: app, writable: false, brew: false),
                       .releasePage)
        // Run from the dmg's quarantine without being moved (TRAPS #63).
        let translocated = "/private/var/folders/x/T/AppTranslocation/ABC/d/NotchPlayer.app"
        XCTAssertEqual(Updater.placement(version: "0.3", bundlePath: translocated, writable: true, brew: false),
                       .releasePage)
    }
}

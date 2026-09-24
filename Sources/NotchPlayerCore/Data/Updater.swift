import AppKit
import Security

/// Updates the app from the menu bar, the way a browser does: GitHub's latest
/// release is checked at launch and daily, downloaded in the background, and
/// one click swaps it in and restarts.
///
/// **What makes a download genuine is Apple's check, not ours.** The new copy
/// has to satisfy this running copy's own designated requirement -- the same
/// bundle id, signed by the same "NotchPlayer" certificate (`make_app.sh`) --
/// or it is never installed. An ad-hoc build's requirement is its own exact
/// hash, so a local build can't pass it and falls back to the release page.
///
/// **Only published releases count.** GitHub's `releases/latest` skips drafts,
/// so the owner trying the draft and pressing Publish is the gate.
///
/// A copy that can't replace itself -- running translocated (TRAPS #63), or
/// in a folder the user can't write to -- still says an update is out; the
/// click opens the release page instead. A Homebrew install is left to
/// `brew upgrade`, which would lose track of an app that updated itself.
@MainActor
public enum Updater {
    public struct Available: Equatable, Sendable {
        public let version: String
        let page: URL
        /// Downloaded and checked, waiting for the click. Nil: the click opens `page`.
        let staged: URL?
    }

    /// What the menu shows; nil when there is nothing newer.
    public private(set) static var available: Available? {
        didSet { if available != oldValue { changed?() } }
    }
    /// The menu bar's dot.
    public static var changed: (() -> Void)?

    static let enabledKey = "checkForUpdates"
    /// On unless switched off.
    public static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { check() } else { available = nil }
        }
    }

    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    /// Whether this copy updates itself, opens the release page, or stays out of it.
    public static var placement: Placement {
        let app = Bundle.main.bundleURL.path, files = FileManager.default
        return placement(version: current, bundlePath: app,
                         writable: files.isWritableFile(atPath: app)
                             && files.isWritableFile(atPath: (app as NSString).deletingLastPathComponent),
                         brew: files.fileExists(atPath: "/opt/homebrew/Caskroom/notchplayer"))
    }

    /// At launch, then every 24 hours. ponytail: a timer, not a saved "last
    /// checked" date -- the app runs from login, so launch plus daily is daily.
    public static func start() {
        guard placement != .hidden else { return print("update: not for this copy (\(current))") }
        check()
        let daily = Timer(timeInterval: 24 * 60 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { check() }
        }
        RunLoop.main.add(daily, forMode: .common)
    }

    private static var checking = false

    static func check() {
        guard enabled, !checking, placement != .hidden else { return }
        checking = true
        Task {
            defer { checking = false }
            guard let release = await latest() else { return }
            let version = release.version
            guard isNewer(version, than: current) else { return print("update: \(current) is the latest") }
            guard available?.version != version else { return }
            var staged: URL?
            if placement == .inPlace, let dmg = release.dmg {
                staged = await download(dmg, version: version)
            }
            print("update: \(version) " + (staged == nil ? "on the release page" : "ready"))
            available = Available(version: version, page: release.htmlUrl, staged: staged)
        }
    }

    /// The row's click.
    public static func install() {
        guard let update = available else { return }
        guard let staged = update.staged else { NSWorkspace.shared.open(update.page); return }
        let app = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(app, withItemAt: staged)
        } catch {
            print("update: couldn't replace \(app.path): \(error)")
            NSWorkspace.shared.open(update.page)
            return
        }
        print("update: installed \(update.version), restarting")
        // The new copy waits for this one to exit: the duplicate-instance
        // guard in main.swift would quit it otherwise. Through `open`, because
        // the audio tap needs a LaunchServices launch (TRAPS #30). The path is
        // $0, so no quoting.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                              app.path]
        do { try relaunch.run() } catch { print("update: couldn't restart: \(error)") }
        NSApp.terminate(nil)
    }

    // MARK: - Network

    /// `NOTCHPLAYER_UPDATE_URL` points it at a fake release for testing; a
    /// `file://` one works.
    static let latestURL = URL(string: ProcessInfo.processInfo.environment["NOTCHPLAYER_UPDATE_URL"]
        ?? "https://api.github.com/repos/arvxanand/NotchPlayer/releases/latest")!
    /// Ephemeral: no cookies and no cache on disk.
    private static let session = URLSession(configuration: .ephemeral)

    private static func latest() async -> Release? {
        do {
            let (data, response) = try await session.data(from: latestURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("update: check answered \(http.statusCode)"); return nil
            }
            return try Release.parse(data)
        } catch {
            print("update: check failed: \(error)"); return nil
        }
    }

    /// ponytail: downloaded again on each launch that finds it (1.3 MB); keep
    /// the staged copy across launches if that ever matters.
    private static func download(_ dmg: URL, version: String) async -> URL? {
        do {
            let (file, _) = try await session.download(from: dmg)
            defer { try? FileManager.default.removeItem(at: file) }
            // hdiutil and ditto block, so off the main thread.
            return try await Task.detached { try stage(file, version: version) }.value
        } catch {
            print("update: \(version) not installable: \(error)"); return nil
        }
    }

    /// The dmg's app, copied out to the cache and checked.
    nonisolated static func stage(_ dmg: URL, version: String) throws -> URL {
        let files = FileManager.default
        let dir = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchPlayer/update")
        try? files.removeItem(at: dir)
        try files.createDirectory(at: dir, withIntermediateDirectories: true)
        let mount = dir.appendingPathComponent("dmg"), app = dir.appendingPathComponent("NotchPlayer.app")
        try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                "-mountpoint", mount.path)
        defer { try? run("/usr/bin/hdiutil", "detach", mount.path, "-force") }
        try run("/usr/bin/ditto", mount.appendingPathComponent("NotchPlayer.app").path, app.path)
        try verify(app, version: version)
        return app
    }

    /// Signed like this running copy, and the version it claims to be.
    nonisolated static func verify(_ app: URL, version: String) throws {
        var me: SecCode?, mine: SecStaticCode?, requirement: SecRequirement?, new: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &new) == errSecSuccess, let new
        else { throw Failure("can't read the signatures") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate
                                   | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(new, flags, requirement)
        guard status == errSecSuccess else { throw Failure("not signed like this copy (\(status))") }
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleShortVersionString"] as? String == version else {
            throw Failure("says it is \(plist?["CFBundleShortVersionString"] ?? "nothing"), not \(version)")
        }
    }

    private nonisolated static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("\((tool as NSString).lastPathComponent) exited \(process.terminationStatus)")
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: - Pure, so a test can call them

    public enum Placement: Equatable, Sendable { case hidden, inPlace, releasePage }

    public nonisolated static func placement(version: String, bundlePath: String,
                                             writable: Bool, brew: Bool) -> Placement {
        // make_app.sh's default: a local build, always "behind" a release.
        if brew || version == "0.1" { return .hidden }
        if bundlePath.contains("/AppTranslocation/") || !writable { return .releasePage }
        return .inPlace
    }

    /// Numeric, so 0.10 is newer than 0.9 and 0.3.1 than 0.3.
    public nonisolated static func isNewer(_ version: String, than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }

    /// The parts of GitHub's release JSON this uses.
    public struct Release: Decodable, Equatable, Sendable {
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
        struct Asset: Decodable, Equatable, Sendable {
            let name: String
            let browserDownloadUrl: URL
        }

        /// The tag is the version: v0.3 -> 0.3.
        public var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
        /// Always this name, so the README's releases/latest/download link works.
        var dmg: URL? { assets.first { $0.name == "NotchPlayer.dmg" }?.browserDownloadUrl }

        public nonisolated static func parse(_ data: Data) throws -> Release {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Release.self, from: data)
        }
    }
}

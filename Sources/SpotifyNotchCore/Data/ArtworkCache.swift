import AppKit

/// Album covers, fetched once and kept on disk.
///
/// Adapted from matchnotch's `CrestCache`, which is exactly this problem. Two
/// changes: the URL is rewritten to a smaller variant before fetching, and the
/// bytes are decoded and downscaled on the way into memory.
public actor ArtworkCache {
    public static let shared = ArtworkCache()

    /// Spotify's artwork URL encodes its own size in the path prefix. `artwork
    /// url` hands over the 640px one -- 226KB to draw a 24pt thumbnail.
    ///
    /// Measured on 14 Sep 2026: `…0000b273` is 640px/226KB, `…00001e02` is
    /// 300px/36KB, `…00004851` is 64px/2.4KB, and all three answer 200.
    static let sourcePrefix = "ab67616d0000b273"
    static let fetchPrefix = "ab67616d00001e02"

    /// One fetch per track, not two. 300px covers the panel's 72pt art at 2x
    /// (144px) with room to spare, and the peek's 24pt downscales from the
    /// same bytes -- so a second request for the 64px variant would save 33KB
    /// and cost a round trip.
    ///
    /// **Rewritten only when the prefix is the one we measured.** Podcast and
    /// playlist images use different prefixes, and a blind 16-character swap
    /// would corrupt them into a 404 -- which, per TRAPS, would then not even
    /// look like an error.
    public static func fetchURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix(sourcePrefix) else { return url }
        let swapped = fetchPrefix + name.dropFirst(sourcePrefix.count)
        return url.deletingLastPathComponent().appendingPathComponent(swapped)
    }

    private var memory: [String: Data] = [:]
    private let directory: URL

    public init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("SpotifyNotch/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Raw bytes rather than an `NSImage`: `NSImage` is not `Sendable`, so the
    /// caller builds the image on its own side of the actor boundary.
    public func data(for url: URL?) async -> Data? {
        guard let url else { return nil }
        let wanted = Self.fetchURL(for: url)
        let key = wanted.absoluteString
        if let hit = memory[key] { return hit }

        let file = directory.appendingPathComponent(Self.filename(for: wanted))
        if let cached = try? Data(contentsOf: file), NSImage(data: cached) != nil {
            memory[key] = cached
            return cached
        }
        guard let (bytes, response) = try? await URLSession.shared.data(from: wanted),
              (response as? HTTPURLResponse)?.statusCode == 200,
              // **HTTP 200 is not "the image exists."** matchnotch's image host
              // answers an unknown id with 200, `content-type: application/xml`
              // and a 263-byte error document, and a loader that checks only
              // the status caches that as a picture -- which then shows up as a
              // blank square rather than as anything resembling an error.
              // Validate the body, not the envelope.
              NSImage(data: bytes) != nil
        else { return nil }
        try? bytes.write(to: file)
        memory[key] = bytes
        return bytes
    }

    /// Flat filename keyed on the whole URL, so two albums cannot collide.
    static func filename(for url: URL) -> String {
        let safe = url.absoluteString.replacingOccurrences(
            of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
        return String(safe.suffix(120)) + ".img"
    }
}

/// Decoded covers, on the main actor, synchronously readable.
///
/// `ArtworkCache` is an actor, so a view that only had that would draw at
/// least one frame with no cover and then fade it in -- invisible while
/// nothing moves, obvious the moment a track changes. This holds the decoded
/// image so a cover already seen is present on the first frame.
///
/// **Keyed by URL, which is what makes the early return safe.** matchnotch
/// records the opposite mistake: an `if image != nil { return }` guard keyed to
/// the view meant a view reused for a different club kept wearing the old
/// badge. Keyed by URL, "already decoded" is a statement about the image
/// rather than about whoever is asking for it.
@MainActor
public final class ArtMemory: ObservableObject {
    public static let shared = ArtMemory()

    /// The largest the app ever draws a cover is 72pt, so 144px at 2x. Storing
    /// the 300px original would be four times the memory for pixels nothing
    /// ever asks for -- and this process never exits.
    public nonisolated static let maxPixels: CGFloat = 144
    /// ponytail: 24 covers, evicted oldest-first. ~2MB at 144px RGBA. Swap for
    /// an NSCache if album-hopping ever makes the eviction visible.
    public static let capacity = 24

    @Published public private(set) var images: [String: NSImage] = [:]
    private var order: [String] = []
    private var inFlight: Set<String> = []

    public init() {}

    public func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return images[ArtworkCache.fetchURL(for: url).absoluteString]
    }

    /// Fire and forget; publishes when the bytes arrive and decode.
    public func load(_ url: URL?) {
        guard let url else { return }
        let key = ArtworkCache.fetchURL(for: url).absoluteString
        guard images[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task { [weak self] in
            let bytes = await ArtworkCache.shared.data(for: url)
            await MainActor.run { self?.store(key, bytes) }
        }
    }

    private func store(_ key: String, _ bytes: Data?) {
        inFlight.remove(key)
        guard let bytes, let image = Self.downscaled(bytes) else { return }
        images[key] = image
        order.append(key)
        while order.count > Self.capacity, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
    }

    /// Decode once, at the size actually drawn.
    ///
    /// `nonisolated` because it touches no state: it is bytes in, image out,
    /// which is what makes the decode-and-shrink path testable without a
    /// main-actor hop.
    nonisolated static func downscaled(_ bytes: Data) -> NSImage? {
        guard let source = NSImage(data: bytes) else { return nil }
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(size.width, size.height))
        guard scale < 1 else { return source }
        let target = NSSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target))
        out.unlockFocus()
        return out
    }
}

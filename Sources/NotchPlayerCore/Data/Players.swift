import Combine
import Foundation

/// Both music apps, and which one the notch shows.
///
/// Redraws whoever reads `current` when either service changes, so a view
/// observes this one object and asks it, rather than watching two.
@MainActor
public final class Players: ObservableObject {
    public let spotify = PlayerService(source: .spotify)
    public let music = PlayerService(source: .appleMusic)
    private var last = Source.spotify
    private var bag: [AnyCancellable] = []

    public init() {
        bag.append(spotify.objectWillChange.merge(with: music.objectWillChange)
            .sink { [weak self] in self?.objectWillChange.send() })
        for service in [spotify, music] {
            let source = service.source
            bag.append(service.$now.sink { [weak self] now in
                if now.isPlaying { self?.last = source }
            })
        }
    }

    public func start() {
        spotify.start()
        music.start()
    }

    /// The one the notch shows right now.
    public var current: PlayerService {
        let draws = Set(Source.allCases.filter { source in
            let service = source == .spotify ? spotify : music
            return Presentation.of(now: service.now, permission: service.permission).draws
        })
        let source = Self.pick(last: last, playing: Self.playing(spotify: spotify.now.isPlaying,
                                                                 music: music.now.isPlaying),
                               draws: draws)
        return source == .spotify ? spotify : music
    }

    /// Who is playing. Both: Spotify, which was here first.
    nonisolated static func playing(spotify: Bool, music: Bool) -> Source? {
        spotify ? .spotify : music ? .appleMusic : nil
    }

    /// Whoever is playing; with nobody playing, the last one that did, unless
    /// it has nothing to draw (quit, or nothing loaded) and the other has.
    nonisolated static func pick(last: Source, playing: Source?, draws: Set<Source>) -> Source {
        if let playing { return playing }
        let other: Source = last == .spotify ? .appleMusic : .spotify
        return draws.contains(last) || !draws.contains(other) ? last : other
    }
}

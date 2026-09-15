import Foundation
import os

/// Counts the frames the expand animation actually renders.
///
/// **Why this exists at all.** The animation's speed is asserted in a test as
/// arithmetic -- 148pt over 0.38s -- and arithmetic cannot tell you whether
/// the frames were delivered. matchnotch measured the same binary at 25-50fps
/// under launchd's default `Standard` process type and 55-59fps with
/// `Interactive`, so every animation number taken from a terminal build is of
/// a different program than the one the user runs. This is how the number gets
/// taken from the shipping one.
///
/// It counts the values SwiftUI's animation driver actually pushes through
/// `InverseCornerShape.animatableData` -- one per rendered frame. Not a
/// display link, which ticks whether or not anything was drawn, and not a
/// `GeometryReader`, which does not see an animated frame interpolate at all
/// (`docs/TRAPS.md` #35).
///
/// Off unless asked. Idle cost is one atomic bool per layout pass.
public final class FrameProbe: @unchecked Sendable {
    public static let shared = FrameProbe()

    private var lock = os_unfair_lock_s()
    private var recording = false
    /// `value` is the shape's morphing corner radius, which rides the same
    /// spring as the height. What is being measured is the timing.
    private var samples: [(at: Date, height: CGFloat)] = []

    /// A pause longer than this ends one animation and starts another, so an
    /// expand and the collapse after it are reported separately rather than
    /// averaged into one meaningless number.
    static let burstGap: TimeInterval = 0.25

    public func begin() {
        os_unfair_lock_lock(&lock)
        recording = true
        samples.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
    }

    /// Called from the view's layout. Cheap and non-blocking by construction:
    /// a lock, a comparison, and an append of two words.
    public func record(_ height: CGFloat) {
        os_unfair_lock_lock(&lock)
        if recording, samples.last?.height != height {
            samples.append((Date(), height))
        }
        os_unfair_lock_unlock(&lock)
    }

    public func report() -> String {
        os_unfair_lock_lock(&lock)
        let taken = samples
        recording = false
        os_unfair_lock_unlock(&lock)
        return Self.describe(taken)
    }

    /// Pure, so the arithmetic that turns samples into a frame rate can be
    /// tested without an animation -- the measurement is the deliverable here,
    /// and a measurement nobody checked is the thing this project keeps
    /// finding (`docs/TRAPS.md` #1, #19, #24).
    public nonisolated static func describe(_ samples: [(at: Date, height: CGFloat)]) -> String {
        let bursts = split(samples)
        guard !bursts.isEmpty else { return "probe: no frames" }
        return bursts.enumerated().map { index, burst -> String in
            let span = burst.last!.at.timeIntervalSince(burst[0].at)
            let from = Int(burst[0].height.rounded())
            let to = Int(burst.last!.height.rounded())
            // n frames over n-1 intervals. Counting n/span reports 60fps for
            // two frames a sixtieth apart, which is one interval of evidence.
            let fps = span > 0 ? Double(burst.count - 1) / span : 0
            return String(format: "probe: burst %d  %d frames  %.3fs  %.1f fps  %d -> %d",
                          index + 1, burst.count, span, fps, from, to)
        }.joined(separator: "\n")
    }

    nonisolated static func split(_ samples: [(at: Date, height: CGFloat)])
    -> [[(at: Date, height: CGFloat)]] {
        var bursts: [[(at: Date, height: CGFloat)]] = []
        for sample in samples {
            if let last = bursts.last?.last,
               sample.at.timeIntervalSince(last.at) <= burstGap {
                bursts[bursts.count - 1].append(sample)
            } else {
                bursts.append([sample])
            }
        }
        // A single sample is a layout pass, not an animation.
        return bursts.filter { $0.count > 1 }
    }

    // MARK: - Names the tool and the app agree on

    public static let startNotification = "local.spotifynotch.probe.start"
    public static let reportNotification = "local.spotifynotch.probe.report"
}

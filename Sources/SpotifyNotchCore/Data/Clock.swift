import Foundation

/// Elapsed and remaining, formatted.
///
/// Its own type because it is the kind of thing that gets written inline in a
/// view body, and then the only way to test it is to restate it in the test
/// file -- which stays green through any change to the real code.
public enum Clock {
    /// `m:ss`, growing to `h:mm:ss` past an hour. Negative values keep the
    /// sign in front, which is how a remaining time reads: `-3:58`.
    ///
    /// Rounded **down**, not to nearest: a track at 0.9s should read `0:00`,
    /// because a clock that shows `0:01` before a second has elapsed is wrong
    /// in the direction people notice.
    public static func mmss(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        // `seconds < 0` is already false for -0.0 by IEEE rules, so this
        // happened to render "0:00" at the end of a track rather than
        // "-0:00". Correct, but by accident -- written out so it survives
        // somebody rearranging the arithmetic above it.
        let negative = seconds <= -1
        let total = Int(abs(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                         : String(format: "%d:%02d", m, s)
        return negative ? "-" + body : body
    }

    /// What the right-hand label shows. Clamped at zero so a stale stamp
    /// cannot render `-0:-3`.
    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        return mmss(-max(0, duration - position))
    }
}

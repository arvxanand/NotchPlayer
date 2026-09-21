import AppKit

/// The system media keys, sent rather than registered.
///
/// **This reverses a decision, on purpose.** The brief said no media keys,
/// and that was about *registering* them -- claiming F7/F8/F9 globally, which
/// fights every other app that wants them and was rejected for good reason.
/// Sending one is the opposite: it asks the system to do what the keyboard
/// would have done, and nothing is claimed.
///
/// **The caveat, which the user knows and which belongs on screen nowhere
/// else:** a media key goes to whatever app the system currently considers
/// the media-key target, which is usually the last thing that played but is
/// not guaranteed to be the app the notch is showing. Spotify does not use
/// this path at all -- it is controlled by name over Apple Events, which
/// cannot go to the wrong app.
public enum MediaKeys {
    public enum Key: Int, CaseIterable, Sendable {
        /// NX_KEYTYPE_PLAY / NEXT / PREVIOUS, from `IOKit/hidsystem/ev_keymap.h`.
        case playpause = 16
        case next = 17
        case previous = 18
    }

    public static func send(_ key: Key) {
        for phase in [true, false] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(phase ? 0xa00 : 0xb00)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1(for: key, down: phase), data2: -1)
            else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// The key and its phase, packed the way the window server expects: key
    /// code in the high sixteen bits, `0xa` for down and `0xb` for up in the
    /// next byte. Arithmetic, so it is asserted rather than trusted -- a
    /// wrong constant here is a button that silently does nothing.
    public static func data1(for key: Key, down: Bool) -> Int {
        (key.rawValue << 16) | ((down ? 0xa : 0xb) << 8)
    }
}

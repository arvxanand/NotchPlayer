# Fixtures

Captured off the wire on 14 Sep 2026 from Spotify 1.2.99.317 on macOS 15.7.7,
except where the filename says otherwise.

| file | provenance |
|---|---|
| `notification-playing.json` | real `PlaybackStateChanged` userInfo, value types preserved |
| `notification-paused.json` | the same event on pause -- `Player State` is `Paused`, capitalised |
| `notification-stringly-typed.json` | the same fields with every numeric as a string, to exercise the lenient reader |
| `applescript-read.json` | the nine-item list, as `NSAppleEventDescriptor.stringValue` returns it |
| `applescript-no-artwork.CONSTRUCTED.json` | **not captured.** A podcast or local file has no artwork URL; nobody has played one through this app, so the shape is inferred from the dictionary. Replace it with a real capture the first time a podcast plays. |

A fixture whose provenance is not obvious from its name is a fixture someone
will eventually trust more than it deserves.

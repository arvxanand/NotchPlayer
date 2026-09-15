# SpotifyNotch

Spotify now-playing in the MacBook notch. Swift 6 / SwiftUI + AppKit, no
dependencies.

Read `HANDOFF.md` before writing any code, and `docs/TRAPS.md` before
debugging anything.

## Build and run

```bash
./tools/verify.sh              # everything checkable, in one command
./make_app.sh release          # build the bundle, restart the agent if loaded
./tools/install-agent.sh       # load it at login (first time only)
```

## When something looks wrong

```bash
.build/debug/SpotifyNotch --read        # what Spotify is actually saying
.build/debug/SpotifyNotch --watch 30    # every state change, stamped, no UI
.build/debug/SpotifyNotch --list-previews
```

The waveform is the exception: the audio tap needs macOS to launch the app, or
TCC silently hands it nothing but zeros (`docs/TRAPS.md` #30).

```bash
open --stdout /tmp/bands.txt --stderr /tmp/bands.txt \
     -a SpotifyNotch.app --args --bands 8   # live bars, or "no live audio"
```

## Checks

| | |
|---|---|
| `tools/verify.sh` | build, tests, notch footprint, contrast, hygiene, docs |
| `tools/check_notch.sh` | nothing legible behind the camera housing, every state. One parked window, ~17s |
| `tools/hit_probe.sh` | the transport targets are live across their whole 44pt. **Changes playback** |
| `tools/frame_probe.sh` | how many frames the expand animation really renders, measured on the running agent |
| `tools/sweep.sh` | nothing of ours left running; the reference agent is still up |
| `tools/reset-permissions.sh` | make macOS re-ask for Automation and Audio Capture |
| `tools/pixel_check.py` | assert about a window capture: `--unlit`, `--bounds` |
| `tools/crop.py` | crop and enlarge a capture so a 37pt strip can be looked at |

`verify.sh` runs everything except `hit_probe.sh`, which clicks real buttons.

## Using it

A waveform glyph in the menu bar: what is playing, **Hide from the Notch**
(stands the app down without quitting -- for when it collides with another
notch app), and Quit. After a Quit:

```bash
launchctl kickstart -k gui/$(id -u)/com.aravmanand.spotifynotch
```

## Docs

| | |
|---|---|
| `HANDOFF.md` | start here, cold |
| `docs/TRAPS.md` | classes of mistake, with the fix |
| `docs/BUGS.md` | specific defects, what they cost |
| `docs/DECISIONS.md` | why things are the way they are |

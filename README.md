# SpotifyNotch

Now-playing in the MacBook notch. Swift 6 / SwiftUI + AppKit, no dependencies.

Collapsed, while something plays: a cover and a live waveform -- a real FFT of
the audio itself -- either side of the camera housing. Hover the cutout and it
expands into a panel. Idle, it draws nothing and the notch looks like a notch.

**Spotify** gets the full panel: cover, track, artist, a progress bar you can
drag to seek, and transport addressed to Spotify by name. **Anything else
making sound** -- a video, a stream -- gets its app's icon, its name, a real
waveform of its audio, and transport over system media keys. Not a title:
macOS gated the API that would give one (`docs/DECISIONS.md`).

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
.build/debug/SpotifyNotch --sources 20  # who is making sound, and which one wins
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
| `tools/hit_probe.sh` | the transport targets are live across their whole 44pt. **Changes playback**, and refuses to run while the app is up |
| `tools/frame_probe.sh` | how many frames the expand animation really renders, measured on the running agent |
| `tools/sweep.sh` | nothing of ours left running; the reference agent is still up |
| `tools/reset-permissions.sh` | make macOS re-ask for Automation and Audio Capture |
| `tools/pixel_check.py` | assert about a window capture: `--unlit`, `--bounds` |
| `tools/crop.py` | crop and enlarge a capture so a 39pt strip can be looked at. Takes **pixels**, and captures are 2x |

`verify.sh` runs everything except `hit_probe.sh`, which clicks real buttons.

## Using it

Hover the notch to open the panel. Click or drag Spotify's progress bar to seek --
the target is the 30pt band around the line, not the line itself. Move the
pointer away and it closes.

A waveform glyph in the menu bar is the only other control: what is playing,
**Hide from the Notch** (stands the app fully down -- no panel, no hover
polling, no audio tap -- for when it collides with another notch app), and
Quit. Hidden survives a relaunch. After a Quit:

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
| `docs/WANTED.md` | what we chose not to build yet, and why |
| `NEXT-SESSION.md` | a prompt to paste into a fresh chat: what to read, where we left off |

## Privacy

The audio is read into a 93ms ring, turned into fourteen numbers, and
overwritten. Nothing is recorded, nothing is sent: the app makes exactly one
network call, for the album cover, to Spotify's own CDN. App names and track
titles are never written to the logs, and conferencing apps are never tapped
at all -- not hidden from the display, never chosen, so their audio is never
read. `HANDOFF.md` has the details.

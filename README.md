# NotchPlayer

Spotify now-playing in the MacBook notch. Swift 6 / SwiftUI + AppKit, no
dependencies.

Collapsed, while music plays: the album cover and a live waveform -- a real
FFT of Spotify's own audio -- either side of the camera housing. Hover the
cutout and it expands into a panel with the cover, the track, a progress bar
you can drag to seek, and play/pause/prev/next. Idle, it draws nothing and the
notch looks like a notch.

## Build and run

```bash
./tools/verify.sh              # everything checkable, in one command
./make_app.sh release          # build the bundle, restart it if running
open NotchPlayer.app          # start it; then Launch at Login in its menu
```

## When something looks wrong

```bash
.build/debug/NotchPlayer --read        # what Spotify is actually saying
.build/debug/NotchPlayer --watch 30    # every state change, stamped, no UI
.build/debug/NotchPlayer --list-previews
```

The waveform is the exception: the audio tap needs macOS to launch the app, or
TCC silently hands it nothing but zeros.

```bash
open --stdout /tmp/bands.txt --stderr /tmp/bands.txt \
     -a NotchPlayer.app --args --bands 8   # live bars, or "no live audio"
```

## Checks

| | |
|---|---|
| `tools/verify.sh` | build, tests, notch footprint, contrast, hygiene, docs |
| `tools/check_notch.sh` | nothing legible behind the camera housing, every state. One parked window, ~17s |
| `tools/hit_probe.sh` | the play/pause and + targets are live across their whole 44pt, and only there. **Changes playback** and opens Spotify, and refuses to run while the app is up |
| `tools/frame_probe.sh` | how many frames the expand animation really renders, measured on the running app |
| `tools/sweep.sh` | nothing of ours left running; the reference agent is still up |
| `tools/reset-permissions.sh` | make macOS re-ask for Automation and Audio Capture |
| `tools/pixel_check.py` | assert about a window capture: `--unlit`, `--bounds` |
| `tools/crop.py` | crop and enlarge a capture so a 39pt strip can be looked at. Takes **pixels**, and captures are 2x |

`verify.sh` runs everything except `hit_probe.sh`, which clicks real buttons.

## Using it

Hover the notch to open the panel. Click or drag the progress bar to seek --
the target is the 30pt band around the line, not the line itself. Move the
pointer away and it closes.

The **+** at the end of the title row is for saving the song. By default it
opens the song in Spotify (its album, with the song highlighted) so you can
add it there. Turn on **Save with Spotify's +** in settings and it presses
Spotify's own + for you: a song you haven't saved goes to Liked Songs, and one
you have opens Spotify's playlist picker. That needs macOS's Accessibility
permission, and it brings Spotify to the front. If anything is missing (no
permission, or a Spotify update that moved the button) the + goes back to
opening the song. No login and no network; local files and podcasts get no +.

A waveform glyph in the menu bar is the only other control: what is playing,
**Hide from the Notch** (stands the app fully down -- no panel, no hover
polling, no audio tap -- for when it collides with another notch app), and
Quit. Hidden survives a relaunch. The gear opens settings:

- **Launch at login** -- a normal macOS login item, listed in System Settings
  -> General -> Login Items.
- **Cover colour on the progress bar** -- the line takes the album cover's main
  colour; a black-and-white cover keeps it white.
- **Save with Spotify's +** -- off by default. Turning it on asks for
  Accessibility; until that's allowed the row reads "Allow in Accessibility…"
  and takes you there. **After every update** macOS forgets the permission
  (the app isn't signed with a developer certificate): the next + click
  asks again, and one Allow fixes it.

After a Quit:

```bash
open NotchPlayer.app
```

Logs go to `~/Library/Logs/NotchPlayer.log`.


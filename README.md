<div align="center">

<!-- Logo slot. There is no app icon yet (make_app.sh ships none on purpose --
     an icon is a second way to launch the app, and a second instance stacks a
     second panel on the same notch). When you draw one, wire it up like this:

<picture>
  <source media="(prefers-color-scheme: dark)"  srcset="assets/logo-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.png">
  <img src="assets/logo-light.png" alt="NotchPlayer" width="120">
</picture>
-->

# NotchPlayer

**Spotify now-playing, in the MacBook notch.**

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/github/license/arvxanand/NotchPlayer)](LICENSE)
[![Release](https://img.shields.io/github/v/release/arvxanand/NotchPlayer?include_prereleases&sort=semver)](https://github.com/arvxanand/NotchPlayer/releases)
[![Downloads](https://img.shields.io/github/downloads/arvxanand/NotchPlayer/total)](https://github.com/arvxanand/NotchPlayer/releases)

</div>

<div align="center">

<img src="assets/demo/hero.gif" alt="NotchPlayer expanding out of the MacBook notch" width="800">

</div>

---

Collapsed, while music plays: the album cover and a live waveform — a real FFT
of Spotify's own audio — either side of the camera housing. Hover the cutout
and it expands into a panel with the cover, the track, a progress bar you can
drag to seek, and the transport row. Idle, it draws nothing and the notch looks
like a notch.

No login, no Spotify developer account, no network calls beyond the album
cover. Swift 6 / SwiftUI + AppKit, zero third-party dependencies.

## Features

<table>
<tr>
<td width="50%">

<img src="assets/demo/media.gif" alt="Album cover and live waveform beside the notch" width="400">

</td>
<td width="50%">

### Now playing, at a glance

The cover on one side of the camera housing, a live waveform on the other.
The waveform is a real FFT of Spotify's output through a Core Audio process
tap — 14 bars, computed in memory, never stored and never sent anywhere.

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/transport.gif" alt="Transport row with seek, shuffle and repeat" width="400">

</td>
<td width="50%">

### Full transport

Play/pause, previous, next, and a progress bar you can click or drag to seek —
the target is the 30pt band around the line, not the line itself. Shuffle and
repeat sit in the same row; repeat cycles off → all → one, and NotchPlayer
loops the song itself for "one".

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/save.gif" alt="The plus button saving the current song" width="400">

</td>
<td width="50%">

### Save the song

The **+** at the end of the title row. By default it opens the song in Spotify
so you can add it there. Turn on **Save with Spotify's +** and it presses
Spotify's own + for you — unsaved goes straight to Liked Songs, already-saved
opens the playlist picker.

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/settings.gif" alt="The settings panel" width="400">

</td>
<td width="50%">

### Stays out of the way

A waveform glyph in the menu bar is the only other control: what's playing,
**Hide from the Notch** (stands the app fully down — no panel, no hover
polling, no audio tap), and Quit. The gear opens settings: launch at login,
cover colour on the progress bar, and the + behaviour.

</td>
</tr>
</table>

## Install

There is no signed download — NotchPlayer isn't in the App Store and isn't
notarised, so you build it yourself. It takes about a minute.

```bash
git clone https://github.com/arvxanand/NotchPlayer.git
cd NotchPlayer
./make_app.sh release
open NotchPlayer.app
```

Then turn on **Launch at Login** from the menu bar item.

### Requirements

| | |
|---|---|
| macOS | 15.0 or later |
| Swift | 6.0 toolchain (Xcode 16+) |
| Spotify | the desktop app, signed in |

### Permissions it will ask for

| Permission | Why | When |
|---|---|---|
| **Automation** | read the track and send play/pause/skip to Spotify | first launch |
| **Audio Recording** | the waveform — Spotify's output only, analysed in memory | first launch |
| **Accessibility** | optional, only for pressing Spotify's own **+** | when you enable it |

Because the app is ad-hoc signed rather than signed with a paid developer
certificate, macOS forgets these **after every rebuild or update**. One Allow
fixes it; `tools/reset-permissions.sh` forces macOS to re-ask when it gets
stuck.

## Using it

Hover the notch to open the panel; move the pointer away and it closes. Click
the title, artist or cover to open that thing in Spotify — the title opens the
album with the song highlighted rather than restarting the track.

The **+** needs a word of explanation. Spotify's AppleScript dictionary exposes
a `starred` property that does nothing, so there is no scriptable way to like a
song. NotchPlayer instead presses Spotify's real + through the Accessibility
API — the same channel VoiceOver uses. It's off by default, it's your own
click being relayed, and it brings Spotify to the front. If anything is missing
— permission not granted, or a Spotify update moved the button — the + quietly
falls back to opening the song. Local files and podcasts get no +.

## Build from source

```bash
./tools/verify.sh              # everything checkable, in one command
./make_app.sh release          # build the bundle, restart it if running
```

SwiftPM can't produce a bundle, and a bundle is required for `LSUIElement`
(no dock icon), a stable bundle identifier, and the usage-description strings
TCC shows you — hence `make_app.sh` rather than plain `swift build`.

### When something looks wrong

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

Logs go to `~/Library/Logs/NotchPlayer.log`.

### Checks

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

### Rebuilding the demo GIFs

The README animations are built from screen recordings that live outside git
(`recordings/` is ignored; only the built GIFs in `assets/demo/` are committed).

```bash
brew install gifski gifsicle ffmpeg
./scripts/build-all.sh              # recordings/raw/*.mov -> assets/demo/*.gif
```

Each recording is already cropped around the notch. Every GIF is 50fps and
forced under 5MB: the script gives up width first, then adds lossy
compression, then drops to 33fps, and fails loudly rather than committing
something huge. It also fails if the frame timing comes out uneven.

## Contributing

Issues and pull requests are welcome. Two things worth knowing before you open
one:

- `./tools/verify.sh` should pass. It's the same thing CI would run.
- The notch is a hard constraint, not a layout suggestion. `check_notch.sh`
  exists because "looks fine on my display" has been wrong more than once.

## License

[GPL-3.0](LICENSE). You can use, modify and redistribute this, including
commercially — but if you distribute a modified version, its source has to stay
open under the same license.

NotchPlayer is not affiliated with, endorsed by, or connected to Spotify AB. It
controls the Spotify desktop app through macOS's own automation interfaces and
needs a running, signed-in Spotify client; it does not stream, download or
redistribute any audio.

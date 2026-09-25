# Building and contributing

Everything for people who clone the repo. Using the app is in the
[README](README.md).

NotchPlayer is Swift 6 with SwiftUI and AppKit, and has zero third-party
dependencies. It reads and controls Spotify through its AppleScript
dictionary, and the waveform is a real FFT of Spotify's output from a Core
Audio process tap.

## Before you open a pull request

Issues and pull requests are welcome. Two things are worth knowing first:

- `./tools/verify.sh` should pass. CI doesn't run it (it needs a Mac with a
  notch), so run it yourself before opening one.
- The notch is a hard constraint, not a layout suggestion. `check_notch.sh`
  exists because "looks fine on my display" has been wrong more than once.

## Build from source

Needs macOS 15 and **Xcode 16** (tested with 16.0, Swift 6.0). The free
Command Line Tools aren't enough yet: their Swift 6.2 didn't finish compiling
this project in over ten minutes.

```bash
git clone https://github.com/arvxanand/NotchPlayer.git
cd NotchPlayer
./tools/verify.sh              # everything checkable, in one command
./make_app.sh release          # build the bundle, restart it if running
open NotchPlayer.app
```

Quit a downloaded copy first. Both have the same bundle id, and a second copy
refuses to start while one is running.

SwiftPM can't produce a bundle, and a bundle is required for `LSUIElement`
(no dock icon), a stable bundle identifier, and the usage-description strings
TCC shows you. That's why there's `make_app.sh` rather than plain `swift build`.

Your build is ad-hoc signed, so macOS treats each rebuild as a new app and
may ask for the permissions again (`tools/reset-permissions.sh` helps). A
plain build is version 0.1, which never checks for updates.

## How the + works

Spotify's AppleScript dictionary has a `starred` property that does nothing,
so there's no scriptable way to like a song, and the Web API needs a developer
app capped at five users. So with **Save with Spotify's +** on, NotchPlayer
presses Spotify's own + through the Accessibility API, the same channel
VoiceOver uses. For a song you haven't saved, it opens the title's **Add to
playlist** menu instead, so nothing is ever added without a pick. If anything
is missing (the permission, or a Spotify update moved the button), the +
falls back to opening the song. `SpotifyPlus.swift` has the details.

## When something looks wrong

```bash
swift build                            # the debug binary these use
.build/debug/NotchPlayer --read        # what Spotify is actually saying
.build/debug/NotchPlayer --watch 30    # every state change, stamped, no UI
.build/debug/NotchPlayer --list-previews
```

The waveform is the exception: the audio tap needs macOS to launch the app, or
TCC silently hands it nothing but zeros.

```bash
open --stdout /tmp/bands.txt --stderr /tmp/bands.txt \
     ./NotchPlayer.app --args --bands 8   # live bars, or "no live audio"
```

A local-file song's cover is found through Spotify's own index
(`LocalCover.swift`). To check it from the app's own process, with a local
song playing:

```bash
open -n -W --stdout /tmp/local.txt ./NotchPlayer.app --args --local-cover
```

Logs go to `~/Library/Logs/NotchPlayer.log`.

## Checks

| | |
|---|---|
| `tools/verify.sh` | build, tests, notch footprint, contrast, hygiene, docs |
| `tools/check_notch.sh` | nothing legible behind the camera housing, every state. One parked window, ~17s |
| `tools/hit_probe.sh` | the play/pause and + targets are live across their whole 44pt, and only there. **Changes playback** and opens Spotify, and refuses to run while the app is up |
| `tools/frame_probe.sh` | how many frames the expand animation really renders, measured on the running app |
| `tools/sweep.sh` | no preview window or debug build left running |
| `tools/reset-permissions.sh` | make macOS re-ask for Automation, Audio Capture and Accessibility |
| `tools/make-dmg.sh` | pack `NotchPlayer.app` into `NotchPlayer.dmg`, the same way the release workflow does |
| `swift tools/make-icon.swift` | redraw the app icon (`assets/AppIcon.icns`) and the README logo |
| `tools/pixel_check.py` | assert about a window capture: `--unlit`, `--bounds` |
| `tools/crop.py` | crop and enlarge a capture so a 39pt strip can be looked at. Takes **pixels**, and captures are 2x |

`verify.sh` runs everything except `hit_probe.sh`, which clicks real buttons.

## Rebuilding the demo GIFs

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

## Releasing a version

For the maintainer.

1. Tag `main` and push the tag. The version is the tag without the `v`.

   ```bash
   git tag v0.3 origin/main && git push origin v0.3
   ```

2. The `release` workflow builds `NotchPlayer.dmg` with Xcode 16.0, signs
   it with the NotchPlayer certificate (repo secrets `SIGNING_P12` and
   `SIGNING_P12_PASSWORD`), checks its signer, entitlement, version and
   bundle id from inside the dmg, and attaches it to a **draft** release,
   which only people with write access can see. Run by hand from a branch
   (Actions → release → Run workflow), it only builds and checks.
3. Download the dmg from the draft, try it, and click **Publish release**.
   **Publishing is what updates everyone:** the README's download link and
   every copy's update check only see published releases.
4. Update the cask in
   [homebrew-notchplayer](https://github.com/arvxanand/homebrew-notchplayer)
   (`Casks/notchplayer.rb`): set `version` to the new version and `sha256` to
   the value in the workflow's job summary. Until then, `brew upgrade` keeps
   installing the old one.

`tools/make-dmg.sh` makes the same dmg locally, after `./make_app.sh release`.

# HANDOFF

Written for starting cold without reading the codebase.

## What this is

A macOS app that turns the MacBook notch into a Spotify now-playing display.
Collapsed, while music plays: album art and a live waveform in the menu-bar
strip either side of the physical cutout, with the Spotify mark. Hovering the
cutout expands a panel downward with larger art, track and artist, progress,
and play/pause/prev/next. Idle draws nothing.

Swift 6 / SwiftUI + AppKit. **Zero third-party dependencies.**

Reference project: `~/side-projects/matchnotch`, a shipping notch app. Its
`Notch/` folder is copied here rather than rewritten, and
`~/side-projects/docs/TRAPS.md` (96 entries) still applies in full. This
project's own `docs/TRAPS.md` has the ones it found for itself.

## The rules that break a new notch app

1. **The panel is click-through until it opens, and never active.** Collapsed,
   `ignoresMouseEvents = true`, so hover is *polled* from
   `NSEvent.mouseLocation` against rects in `NotchGeometry` -- see
   `HoverWatcher`; `Expansion` flips `setInteractive` once the panel is open
   and wants the click. Two consequences for anything you add to the panel:
   **`.onHover` never fires at all** (tracking areas want an active app, and
   this one never activates -- `docs/TRAPS.md` #40), so no control may use
   hover as its only affordance; and a **drag needs `acceptsFirstMouse`**,
   which is why the content is hosted in `FirstMouseHostingView`. A `Button`
   works without it because it acts on mouse-up, which hid that for four
   milestones (#37).
2. **`swift build` does not update the running agent.** `./make_app.sh
   release` does, and kickstarts the agent itself if one is loaded.
3. **`screencapture -R` does not contain the panel; `-o -l <windowid>`
   does.** The collapsed peek *is* self-verifiable, contrary to the inherited
   rule -- see "Looking at it" below. What a capture cannot show is how the
   peek sits against the real hardware. For that, ask for a phone photo and
   say you have not seen it.
4. **Never `pkill -f SpotifyNotch`** -- kill the pid you launched.
   `tools/sweep.sh` finds what you missed.
5. **The audio tap only works when macOS launches the app.** Permission
   belongs to the *responsible* process, so running the bundle's executable
   from a shell makes the terminal responsible and TCC denies silently -- the
   tap is created, buffers arrive, and every sample is zero. Use
   `open --stdout FILE --stderr FILE -a SpotifyNotch.app --args ...`. See
   `docs/TRAPS.md` #30, which cost an hour of debugging a tap that was
   already correct.

## Verify

```bash
./tools/verify.sh
```

Six stages: build with warnings as failures, tests, notch footprint across
every drawing state, HIG contrast, nothing left running, doc numbering and
cross-references. About 30s. Anything visual still needs eyes.

The footprint stage drives **one** parked window rather than launching the app
per state -- see `docs/BUGS.md` #11. If you change it, test it behind a
kill-timer; two rewrites deadlocked with a panel on the user's screen
(`docs/BUGS.md` #12).

Two checks are deliberately **not** in it, because both change real state:

```bash
./tools/hit_probe.sh    # clicks the real transport buttons
```

Run that after touching the panel's layout. It is the only thing that can see
`docs/TRAPS.md` #21 -- and it **refuses to run while the installed app is up**,
because two panels at the same coordinates make it measure the wrong one
(`docs/TRAPS.md` #39).

## Current state

**Shipped, and running as a LaunchAgent.** All eight milestones: the skeleton,
the Spotify bridge, the peek, the panel, the transport, the five states, the
Core Audio tap, shipping -- plus what came after it: a menu-bar item,
drag-to-seek, and a waveform that costs a fifth of what it used to.

145 tests, `verify.sh` green on all six stages, 19 footprint states clean.

Verified by measurement, by capture, or by driving the real pointer:

- Shell is **352 x 39 pt** collapsed, **352 x 185 pt** expanded, in every
  state. Concave top shoulders overhang ~8pt each side. The 39 is 37pt of
  menu-bar inset plus 2pt of `housingOverhang`, below.
- Nothing behind the camera housing in any of the 19 states -- every drawing
  state, collapsed *and* expanded.
- **Hover opens the panel on the live app**, with real Spotify data.
- **The transport buttons work on the live app**, and clicking does not change
  the frontmost application.
- **The whole 44pt target is live, and only the target** -- proved by
  `hit_probe.sh`, and proved to be a real check by breaking `.contentShape`
  on purpose and watching it fail while every unit test of the day stayed
  green.
- `PlaybackStateChanged` fires and carries the whole track payload;
  `player position` is writable.
- Cold cache downloads the **300px** cover variant (35KB, not the 226KB
  `artwork url` hands over).
- The System Settings deep link lands on the **Automation** pane -- opened and
  photographed, not assumed.
- **The shell is 2pt taller than `safeAreaInsets.top`** -- the physical cutout
  is slightly taller than the inset, and a shell sized to the inset exactly
  leaves the housing's bottom edge showing. Reported by the user looking at
  the hardware; it does not appear in any capture, so
  `NotchGeometry.housingOverhang` can only be changed the same way.
- **The Automation grant survived a rebuild** -- one rebuild, one launch, no
  -1743. Not many data points, but the first evidence either way.
- **58.3 fps expanding, 60.0 collapsing**, measured on the launchd-launched
  agent with `ProcessType = Interactive` -- and with Low Power Mode **on**.
  42 frames over 0.70s: the spring's tail is longer than its 0.38s nominal
  response, which is what a spring does. `./tools/frame_probe.sh`.
- **What it costs while music plays: 1.7% of a core**, of which 0.8% is the tap
  and the FFT. It was 8.9% until the bars moved from SwiftUI to `CALayer`s --
  SwiftUI's per-frame update was the whole cost, at about 0.3% per frame per
  second whatever the frame contained (`docs/DECISIONS.md`). Still measured
  under Low Power Mode, which inflates both numbers.
- **A second launch is refused** -- the guard was broken until milestone 7
  actually tried it (`docs/BUGS.md` #15).
- **The scrub band is 30pt tall and centred on the line** -- probed live: the
  centre and 12pt either side seek, 17pt above and 19pt below do not, and the
  transport row below is untouched. It was effectively 3pt at first, which is
  unhittable (`docs/TRAPS.md` #41).
- **The progress bar seeks.** Click or drag, on the live app: a click at 25.2%
  of a 230s track landed at 58s, a drag to 82.9% landed at 191s, and a drag
  released *outside* the panel still committed and did not collapse it. Needed
  `acceptsFirstMouse` first -- a non-key window never delivered the mouse-down
  a drag begins with (`docs/TRAPS.md` #37).
- **The notch follows whatever is playing**, not just Spotify: the peek
  draws that app's icon and the waveform is its audio. Verified against a
  real browser video -- detected through its helper process, `waveform live
  (44100Hz)`, and bars at different heights half a second apart.
- **"Producing output" is not "making a sound"** (`docs/TRAPS.md` #42), which
  is why a source that goes quiet for 5s is stood down and why Spotify's own
  answer about itself outranks listening to it.
- **The installed bundle reads Spotify and starts the tap.** Which needed the
  `com.apple.security.automation.apple-events` entitlement first: the hardened
  runtime had been refusing every event with -1743 and no prompt
  (`docs/BUGS.md` #14).
- **92 deliberate mutations; 90 red.** The two that stayed green were bad
  mutations rather than gaps (`docs/TRAPS.md` #19). Four of the ninety only
  went red after the tests that missed them were fixed -- including one where
  the assertion `contains("0.000")` happily accepted `"-10.000"`.
- **The live waveform draws from the tap.** Three captures half a second
  apart, with music playing: fourteen bass-tilted bars at different heights
  each time, and `waveform live (44100Hz)` in the log. Both sources move, so
  this is the only way to tell them apart.
- **The waveform is real.** A process tap on Spotify's pid, launched the way
  macOS launches it, delivers audio and the bars follow it:
  `|▆▅▂▃▂▃▃▃▂▂▃▁ ▁|  peak 0.83` and the shape moving with the music. The tap
  reported **44100Hz**, not the 48000 the brief measured -- it follows the
  output device, so the rate is read at runtime and handed to the analyzer.
- **The menu-bar item stands the app down.** Hide stops the panel, the hover
  polling and the tap; the item stays, because it is the only way back.

## What has never been checked

Say so rather than implying otherwise:

- **What Spotify reports for an ad, a podcast or a local file.** The
  no-artwork fixture is marked `CONSTRUCTED` for exactly this reason.
- **Whether a track change fires the notification.** It is the same name with
  a different `Track ID`, and every notification is handled identically, so
  it is moot by construction -- but nobody has watched one.
- **Whether ad-hoc signing re-prompts for TCC on every build.** The refusal
  that prompted this question turned out not to be TCC at all: the hardened
  runtime was blocking Apple Events for want of an entitlement
  (`docs/BUGS.md` #14). With that fixed the bundle reads Spotify normally. How
  a *rebuild* behaves after a genuine grant is still untested.
- **Anything on an external display or in clamshell.** Nothing was attached.
- **An output-device change mid-track.** The rebuild path that handles it is
  written and reasoned, and nobody has unplugged anything.
- **Anything with Low Power Mode off.** `pmset -g` says `lowpowermode 1`, so
  every performance number above is of a throttled machine. The honest version
  of the CPU figure needs it off.
- **The permission states against a real refusal.** They render from preview
  data. `tools/reset-permissions.sh` then declining is the only way to confirm
  the app reaches them.
- **How any of it looks against the real hardware.**

## The five answers

There is no single "nothing playing". `Presentation.of(now:permission:)` is
the one place that decides.

| | drawn |
|---|---|
| Spotify not running | nothing |
| Spotify open, nothing loaded | nothing |
| read failed, unknown reason | nothing; last good value kept, retry in 2s |
| Automation refused, track known | full panel; transport row becomes a sentence and a link |
| Automation refused at launch | the mark alone in the peek; panel says what is wrong |

Anything about rendering asks `Presentation.draws`, never `Now.draws` --
`docs/BUGS.md` #8.

## How it fits together

- `SpotifyBridge` -- everything over Apple Events. Scripts compiled once and
  held (**3.34ms** in-process against **220-270ms** shelling out to
  `osascript`, measured). Four error codes, four different answers.
- `SpotifyService` -- the single publisher. Event-driven: the playback
  notification carries the whole track, so the ordinary case costs no Apple
  Event at all. A 5s reconcile tick **only while playing**, a wake observer,
  and launch/terminate observers.
- `Presentation` / `Now` / `Permission` -- what is true, and what to draw.
- `Expansion` -- hover to open, the `setInteractive` flip, and `hold`, which
  keeps the panel open through a drag that wanders out of it.
- `RootView` -> `PeekView` / `PanelView` -- a function of plain values, so
  every preview state renders through the production hierarchy.
- `ProgressLine` -- click or drag to seek. Writes once, on release; the
  service takes the new position as true immediately, because Spotify
  publishes nothing for a seek.
- `MenuBarItem` / `MenuPanel` -- the only user-facing control: what is
  playing, Hide, Quit.
- `Bands` / `Spectrum` / `Analyzer` -- the waveform's arithmetic, pure and
  tested against tones whose answer is known in advance. Hann window, 1024
  samples, 14 log-spaced bands, peak per band, decibels, attack/decay.
- `AudioTap` -- the part that cannot be tested: process object, tap, aggregate
  device, IOProc. Fails quietly to synthetic bars in every direction.
- `WaveformView` / `BarsLayer` -- a capture draws fixed values in SwiftUI;
  anything that moves is fourteen `CALayer`s driven by one timer that pulls a
  frame from the tap, or synthetic bars when the tap has nothing.

## Flags

| | |
|---|---|
| `--read` | one full Apple Event read, printed. First thing to run when the panel looks wrong |
| `--watch [seconds]` | every state change the service publishes, stamped. No UI |
| `--preview <state>` | pin a fixed state; `--list-previews` names them |
| `--expanded` | with `--preview`, pin the panel open |
| `--probe` | fill the shell white so its geometry can be captured |
| `--render <subject> <path> [--side N]` | one view offscreen to a PNG, large enough to judge: `mark`, `peek`, `artwork`, `waveform`, `menu`, `progress` |
| `--notchrect` | the camera housing in `screencapture -R` coordinates |
| `--hit-rects` | the transport targets **and the scrub band** in screen coordinates, for the probes |
| `--check-states` | what `check_notch.sh` should capture |
| `--capture-server` | stay alive, take `<state> [expanded]` or `probe` on stdin, answer `ready`. Exits after 30s idle |
| `--offscreen` | park the window at the bottom-right, out of the way of whoever is using the machine |
| `--bands [seconds]` | the real tap as a text meter, labelled live or not. The only way to tell a working tap from the fallback |
| `--probe-signal start\|report` | drive the running agent's frame probe; `tools/frame_probe.sh` wraps it |
| `--audit` | the HIG check list as JSON |

`--preview` and `--probe` also print `window`, `size`, `housing` and `shell`
to stdout, which is how the scripts find the window to capture.

## Next

`docs/WANTED.md` -- four things deliberately not built, each with the reason.
The one to read first is the note on Low Power Mode: every performance number
in this file was taken with it on.

## Looking at it

```bash
.build/debug/SpotifyNotch --preview noart --expanded    # prints its window id
screencapture -x -o -l <window id> shot.png             # -o, and -l not -R
/usr/bin/python3 tools/crop.py shot.png out.png X Y W H 3
```

`crop.py` takes **pixels**, and a capture is 2x -- passing points gives you
the top-left quarter (`docs/TRAPS.md` #20). `pixel_check.py` asserts about a
capture: `--unlit` for the housing band, `--bounds` for the shell.

A black shape on a dark menu bar is the same pixels as no shape, which is what
`--probe` is for.

## Testing hover

The pointer has to actually move: the panel is click-through, so there is no
event to synthesise and `HoverWatcher` polls the real cursor.
`CGWarpMouseCursorPosition` quantises to whole pixels, so a restored position
can differ from the saved one by under a point.

## Working on the user's machine

- **Testing against real Spotify changes their playback.** Record
  `player position` first and restore it afterwards.
- **A leaked preview cannot be quit by the user** -- no dock icon, no menu bar
  item, no Quit. Run `tools/sweep.sh` after anything that launches one.
- **Before trusting a hygiene check, break it.** Both of the original ones
  answered "fine" for an hour while neither was true (`docs/BUGS.md` #10).
  Three separate times in this project the instrument has been the broken
  thing (`docs/TRAPS.md` #1, #19, #24).

## Running it

Installed as a LaunchAgent (`./tools/install-agent.sh`), so it starts at login
and `launchctl kickstart -k gui/$(id -u)/com.aravmanand.spotifynotch` brings it
back after a Quit. `KeepAlive` is `SuccessfulExit: false` on purpose -- quitting
from the menu stays quit.

The **menu-bar item** (a waveform glyph) is the only user-facing control:
what is playing, **Hide from the Notch** -- which stands the app fully down,
panel, hover polling and audio tap -- and Quit. Hidden survives a relaunch.

To remove it entirely: `launchctl bootout gui/$(id -u)/com.aravmanand.spotifynotch`
and delete `~/Library/LaunchAgents/com.aravmanand.spotifynotch.plist`.

## Was milestone 7

**Shipped.**

- `ProcessType = Interactive`, and the frame rate measured on the agent rather
  than on a terminal build: **58.3 fps**.
- The duplicate guard confirmed against a real second launch, which is how it
  was found to have never worked (`docs/BUGS.md` #15).
- The Automation entitlement, without which the bundle could not read Spotify
  at all (`docs/BUGS.md` #14).
- A menu-bar item, so the app can be stood down when it collides with the
  user's other notch app.

Still open, and deliberately: the CPU numbers were taken under Low Power Mode,
and the waveform's drawing cost has an upgrade path nobody has needed yet
(`docs/DECISIONS.md`).

The tap chain, for reference, all of it now verified working rather than
probed:

PID ->
`kAudioHardwarePropertyTranslatePIDToProcessObject` -> `CATapDescription`
(muteBehavior **unmuted** -- the user must still hear their music) ->
`AudioHardwareCreateProcessTap` -> aggregate device with the tap UUID under
`kAudioSubTapUIDKey` -> `AudioDeviceCreateIOProcIDWithBlock` ->
`AudioDeviceStart`. Format came back **44100 Hz, 2ch, 32-bit float packed** --
the output device's rate, not a constant.

Two things to hold on to:

- **`AVAudioEngine` cannot be retargeted to a tap-backed aggregate.** Setting
  `kAudioOutputUnitProperty_CurrentDevice` returns `noErr` and the engine
  keeps reading the default *input*, so you get microphone audio or silence
  with no error anywhere. Use the IOProc block directly.
- **There is no public API to check `NSAudioCaptureUsageDescription`**, so
  "the tap never delivered a buffer" is a normal state, not an error. Fall
  back to synthetic bars if nothing arrives within 2s.

FFT via `vDSP` from Accelerate -- a system framework, so still zero
dependencies.

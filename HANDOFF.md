# HANDOFF

Written for starting cold without reading the codebase.

## What this is

A macOS app that turns the MacBook notch into a now-playing display.

Collapsed, while something is playing: a cover and a live waveform in the
menu-bar strip either side of the physical cutout. Hovering the cutout expands
a panel downward. Idle, it draws nothing and the notch looks like a notch.

Two kinds of source:

- **Spotify** gets everything -- album cover, track, artist, a progress bar
  you can drag to seek, and transport addressed to Spotify by name.
- **Anything else making sound** -- a video, a stream, a film -- gets its
  app's icon, its app's name, a real waveform of its audio, and transport
  over system media keys. Not a title, because macOS will not give one out
  (`docs/DECISIONS.md`).

The waveform is a real FFT of the audio, taken with a Core Audio process tap.

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
6. **"Producing output" is not "making a sound".**
   `kAudioProcessPropertyIsRunningOutput` says an app holds an audio stream
   open. Spotify reports it right through a pause; a browser reports it for
   about a minute after a video stops. Anything that treats it as "is
   audible" is wrong in a way that looks right (`docs/TRAPS.md` #42).

## Verify

```bash
./tools/verify.sh
```

Six stages: build with warnings as failures, tests, notch footprint across
every drawing state, HIG contrast, nothing left running, doc numbering,
cross-references and the `DECISIONS.md` index. About 30s. Anything visual
still needs eyes.

The footprint stage drives **one** parked window rather than launching the app
per state -- see `docs/BUGS.md` #11. If you change it, test it behind a
kill-timer; two rewrites deadlocked with a panel on the user's screen
(`docs/BUGS.md` #12).

Two checks are deliberately **not** in it, because both change real state:

```bash
./tools/hit_probe.sh     # clicks the real transport buttons
./tools/frame_probe.sh   # drives the real pointer at the notch
```

Run `hit_probe` after touching the panel's layout. It is the only thing that
can see `docs/TRAPS.md` #21 -- and it **refuses to run while the installed app
is up**, because two panels at the same coordinates make it measure the wrong
one (`docs/TRAPS.md` #39).

## Current state

**Shipped and running as a LaunchAgent**, through all eight milestones plus
the work after them: a menu-bar item, drag-to-seek, a waveform that costs a
fifth of what it used to, and following any app's audio rather than only
Spotify's.

**166 tests**, `verify.sh` green on all six stages, **23 footprint states**
clean. 103 deliberate mutations, 101 red -- the two that stayed green were bad
mutations rather than gaps (`docs/TRAPS.md` #19), and several of the rest only
went red after the tests that missed them were fixed, including an assertion
that accepted `"-10.000"` as containing `"0.000"`.

### Verified by measurement, capture, or driving the real pointer

**The shell**

- **352 x 39 pt** collapsed, **352 x 185 pt** expanded, in every state.
  Concave top shoulders overhang ~8pt each side. The 39 is 37pt of menu-bar
  inset plus 2pt of `housingOverhang`.
- **The 2pt overhang exists because the physical cutout is taller than the
  inset**, and a shell sized to the inset leaves the housing's edge showing.
  Reported by the user looking at the hardware; it appears in no capture, so
  it can only be changed the same way.
- Nothing behind the camera housing in any of the 23 states -- every drawing
  state, collapsed *and* expanded.

**Interaction**

- **Hover opens the panel on the live app**, with real Spotify data.
- **The transport buttons work**, and clicking does not change the frontmost
  application.
- **The whole 44pt target is live, and only the target** -- proved by
  `hit_probe.sh`, and proved to be a real check by breaking `.contentShape`
  on purpose and watching it fail while every unit test of the day stayed
  green.
- **The progress bar seeks.** A click at 25.2% of a 230s track landed at 58s,
  a drag to 82.9% landed at 191s, and a drag released *outside* the panel
  still committed without collapsing it.
- **The scrub band is 30pt tall and centred on the line** -- the centre and
  12pt either side seek, 17pt above and 19pt below do not, and the transport
  row is untouched.
- **The menu-bar item stands the app down.** Hide stops the panel, the hover
  polling and the tap; the item stays, because it is the only way back.
- **A second launch is refused** -- the guard had never worked until a real
  second launch was tried (`docs/BUGS.md` #15).

**Spotify**

- `PlaybackStateChanged` fires and carries the whole track payload;
  `player position` is writable.
- Cold cache downloads the **300px** cover variant (35KB, not the 226KB
  `artwork url` hands over).
- The System Settings deep link lands on the **Automation** pane -- opened and
  photographed, not assumed.
- **The installed bundle reads Spotify**, which needed the
  `com.apple.security.automation.apple-events` entitlement: the hardened
  runtime refused every event with -1743 and no prompt (`docs/BUGS.md` #14).
- **The Automation grant survived a rebuild** -- one rebuild, one launch, no
  -1743. One data point, but the first evidence either way.

**Audio**

- **The waveform is real.** A process tap, launched the way macOS launches
  the app, delivers audio and the bars follow it. Three captures half a
  second apart show bars at different heights -- both sources move, so that
  is the only way to tell live from synthetic.
- **It follows any app**, verified against a real browser video: detected
  through the browser's *helper* process, `waveform live (44100Hz)` in the
  log, bars moving with the video.
- The tap reported **44100 Hz**, not the 48000 the brief measured -- it
  follows the output device, so the rate is read at runtime.
- **An app can hold a stream open while silent** (Claude Desktop does), so a
  source that delivers nothing but digital silence is passed over. Verified:
  with Spotify paused and Claude idling, the notch shows Spotify.

**Performance** (all under Low Power Mode, which inflates every number)

- **58.3 fps expanding, 60.0 collapsing** on the launchd-launched agent with
  `ProcessType = Interactive`. 42 frames over 0.70s: a spring's tail is
  longer than its nominal response.
- **1.7% of a core while music plays**, of which 0.8% is the tap and the FFT.
  It was 8.9% until the bars moved from SwiftUI to `CALayer`s -- SwiftUI's
  per-frame update was the entire cost, at ~0.3% per frame per second
  whatever the frame contained.

## What has never been checked

Say so rather than implying otherwise:

- **Anything with Low Power Mode off.** `pmset -g` says `lowpowermode 1`, so
  every performance number above is of a throttled machine.
- **What Spotify reports for an ad, a podcast or a local file.** The
  no-artwork fixture is marked `CONSTRUCTED` for exactly this reason.
- **Whether a track change fires the notification.** Same name, different
  `Track ID`, and every notification is handled identically -- moot by
  construction, but nobody has watched one.
- **Whether a rebuild re-prompts for TCC** after a genuine grant.
- **Anything on an external display or in clamshell.** Nothing was attached.
- **An output-device change mid-track.** The rebuild path is written and
  reasoned; nobody has unplugged anything.
- **The permission states against a real refusal.** They render from preview
  data; `tools/reset-permissions.sh` then declining is the only confirmation.
- **Media keys reaching the app the notch is showing.** They reached a
  browser video once and appear to have reached Spotify on the next press --
  the ambiguity is inherent (`docs/DECISIONS.md`).
- **How any of it looks against the real hardware**, beyond the one photo the
  user sent of the collapsed peek.

## What gets drawn

`Presentation.of(now:permission:source:)` is the one place that decides, and
anything about rendering asks `Presentation.draws`, never `Now.draws`
(`docs/BUGS.md` #8).

| | drawn |
|---|---|
| something other than Spotify is playing | that app's icon, its name, live bars, media-key transport |
| Spotify playing or paused | cover, title, artist, progress, scrubbing, transport |
| Spotify not running | nothing |
| Spotify open, nothing loaded | nothing |
| read failed, unknown reason | nothing; last good value kept, retry in 2s |
| Automation refused, track known | full panel; transport row becomes a sentence and a link |
| Automation refused at launch | the mark alone in the peek; panel says what is wrong |

## How it fits together

- `SpotifyBridge` -- everything over Apple Events. Scripts compiled once and
  held (**3.34ms** in-process against **220-270ms** shelling out to
  `osascript`, measured). Four error codes, four different answers. A seek is
  the one script that is not cached, because its source carries its argument.
- `SpotifyService` -- the single publisher. Event-driven: the playback
  notification carries the whole track, so the ordinary case costs no Apple
  Event at all. A 5s reconcile tick **only while playing**, a wake observer,
  and launch/terminate observers.
- `AudioSources` -- who is making sound, from Core Audio property listeners
  rather than a poll. Owns the dwell, the exclusions, "most recent wins" and
  the stand-down, all as pure functions with tests.
- `AudioTap` -- the part that cannot be tested: process object, tap,
  aggregate device, IOProc. Pulled, not published: the view asks for a frame
  when it is about to draw one.
- `Bands` / `Spectrum` / `Analyzer` -- the waveform's arithmetic, tested
  against tones whose answer is known in advance. Hann window, 1024 samples,
  14 log-spaced bands, peak per band, decibels, attack/decay.
- `Presentation` / `Now` / `Permission` -- what is true, and what to draw.
- `Expansion` -- hover to open, the `setInteractive` flip, and `hold`, which
  keeps the panel open through a drag that wanders out of it.
- `RootView` -> `PeekView` / `PanelView` / `AppPanel` -- functions of plain
  values, so every preview state renders through the production hierarchy.
- `ProgressLine` -- click or drag to seek. Writes once, on release; the
  service takes the new position as true immediately, because Spotify
  publishes nothing for a seek.
- `MediaKeys` -- three keys, sent and never registered.
- `BarsLayer` -- fourteen `CALayer`s and one timer. SwiftUI builds it once.
- `MenuBarItem` / `MenuPanel` -- the only user-facing control.

## Flags

| | |
|---|---|
| `--read` | one full Apple Event read, printed. First thing to run when the panel looks wrong |
| `--watch [seconds]` | every state change the service publishes, stamped. No UI |
| `--sources [seconds]` | who is making sound, as it changes, with the chosen one named. The `--read` of the any-audio half |
| `--bands [seconds]` | the real tap as a text meter, labelled live or not. The only way to tell a working tap from the fallback |
| `--preview <state>` | pin a fixed state; `--list-previews` names them |
| `--expanded` | with `--preview`, pin the panel open |
| `--probe` | fill the shell white so its geometry can be captured |
| `--render <subject> <path> [--side N]` | one view offscreen to a PNG: `mark`, `peek`, `artwork`, `waveform`, `menu`, `progress` |
| `--notchrect` | the camera housing in `screencapture -R` coordinates |
| `--hit-rects` | the transport targets and the scrub band, in screen coordinates |
| `--check-states` | what `check_notch.sh` should capture |
| `--capture-server` | stay alive, take `<state> [expanded]` or `probe` on stdin, answer `ready`. Exits after 30s idle |
| `--offscreen` | park the window at the bottom-right, out of the way |
| `--probe-signal start\|report` | drive the running agent's frame probe |
| `--audit` | the HIG check list as JSON |

`--preview` and `--probe` also print `window`, `size`, `housing` and `shell`
to stdout, which is how the scripts find the window to capture.

**Two of these lied once.** `--sources` and `--bands` each held their Combine
subscription in a local that fell out of scope, so they reported on something
they had stopped listening to. If a diagnostic here disagrees with the app,
suspect the diagnostic first -- seven times out of seven so far.

## Running it

Installed as a LaunchAgent (`./tools/install-agent.sh`), so it starts at login
and `launchctl kickstart -k gui/$(id -u)/com.aravmanand.spotifynotch` brings
it back after a Quit. `KeepAlive` is `SuccessfulExit: false` on purpose --
quitting from the menu stays quit.

The **menu-bar item** (a waveform glyph) is the only user-facing control:
what is playing, **Hide from the Notch** -- which stands the app fully down,
panel, hover polling and audio tap -- and Quit. Hidden survives a relaunch.

To remove it entirely: `launchctl bootout gui/$(id -u)/com.aravmanand.spotifynotch`
and delete `~/Library/LaunchAgents/com.aravmanand.spotifynotch.plist`.

## Privacy, because it was asked and the answers are commitments

- **Audio samples never leave the ring**: 4096 floats, ~93ms, overwritten
  ~11x/s, freed when the tap stops. No file write and no socket exists in
  that path.
- **One network call in the whole app**, the album cover from Spotify's own
  CDN (`ArtworkCache`). The any-audio work added none.
- **Nothing about what is playing is written to disk.** App names and titles
  never reach `out.log` or `error.log`.
- **Conferencing apps are never tapped** -- not filtered from the display,
  never chosen, so no tap is built and their audio is never read.

## Next

`docs/WANTED.md`, five items. The named one is **milestone 10, a browser
extension**: the notch can follow a video but can only name the app, because
no browser exposes which tab is audible and macOS gates the API that would
give a title. The design, and why an extension rather than the global
Apple-Events JavaScript switch, is in
`~/.claude/plans/i-want-to-build-parsed-cascade.md`.

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
  item, no Quit. Run `tools/sweep.sh` after anything that launches one, and
  never put a launch inside `$(...)`, which waits for it.
- **Before trusting a hygiene check, break it.** Both of the original ones
  answered "fine" for an hour while neither was true (`docs/BUGS.md` #10).
  Seven separate times in this project the instrument has been the broken
  thing (`docs/TRAPS.md` #1, #19, #24, #39, #41, and both diagnostics above).

## The tap chain, for reference

PID -> `kAudioHardwarePropertyTranslatePIDToProcessObject` (or straight from
`AudioSources`, which already has the object) -> `CATapDescription`
(muteBehavior **unmuted** -- the user must still hear their audio) ->
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

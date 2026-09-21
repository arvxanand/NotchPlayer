# Bugs

Numbered, never reused, newest last. An entry stays after it is fixed -- the
fix is the useful part. Symptom, cause, fix, what it cost to find.

`TRAPS.md` is the generalisable lesson; this is the specific defect. Most
entries here point at one.

---

1. **The progress track was below the contrast floor, and a comment said it
   was not.** `M0`

   White at 0.22 on black, copied from matchnotch's `faint`, measures
   **1.79:1**. The unfilled part of a progress bar is a non-text element that
   carries state, so its floor is 3:1. Raised to 0.35 -- and that was still
   wrong, because 0.35 composites to `#595959` at **2.996:1**, which the HIG
   checker prints rounded as `3.0`. Two comments in the source claimed
   "exactly 3.00:1". Now 0.36 (`#5C5C5C`, 3.14:1).

   Found by running the checker rather than trusting the inherited constant.
   See `TRAPS.md` #6.

2. **The footprint check measured the menu bar, not the panel.** `M0`

   Inherited from matchnotch, where it still does. It screen-captures the
   camera housing's coordinates and asserts the pixels are black -- but a
   screen capture over the menu-bar strip does not contain the panel at all,
   so it reports CLEAN whenever the menu bar there happens to be dark,
   **including when the app is not running**. Verified by running it against
   nothing: `peak RGB 0/255, CLEAN`.

   Fixed by capturing the panel's own window by id, which does contain it.
   The binary prints `window`, `size`, `housing` and `shell` on stdout in
   preview and probe modes so the script can find it. See `TRAPS.md` #2, #3.

3. **`testTwoAlbumsCannotCollideOnDisk` could not collide.** `M2`

   It used two URLs that differed in their last path component, so a mutation
   keying the cache filename on `lastPathComponent` instead of the whole URL
   stayed green. The real collision is two URLs whose last components *match*.
   Found by the mutation run, not by review -- the test's name was a claim
   nobody had checked. See `TRAPS.md` #18.

4. **Two Spotify marks in the no-artwork state.** `M2`

   A podcast rendered the peek's standalone mark *and* the mark standing in
   for the missing cover, side by side at two different sizes. Each `if` was
   correct in its own file; the bug only exists between them. Every test was
   green.

   Found by capturing the `noart` state and looking at it. Fixed with three
   cases rather than two -- cover loaded, cover **pending** (draws nothing),
   no URL at all -- and both decisions lifted into functions
   (`PeekView.showsStandaloneMark`, `ArtworkView.showsPlaceholderMark`) so a
   test can assert exactly one is true for every combination.
   See `TRAPS.md` #16.

5. **`Clock.remaining` relied on IEEE signed-zero semantics by accident.** `M3`

   At the end of a track it rendered `0:00` rather than `-0:00`, which is
   correct -- but only because `-0.0 < 0` is false, not because anything said
   so. A rearrangement of the arithmetic above it would have silently changed
   the output. Made explicit (`seconds <= -1`).

6. **An animation test that would have rejected a legitimate design.** `M4`

   The expand-travel budget was written against an invented per-frame ceiling.
   Adding the transport row took the panel to a perfectly reasonable 148pt of
   travel, which the test failed -- a test dictating the design rather than
   protecting it. Rebounded against matchnotch's *measured* 940pt/s
   "visibly jagged" figure; we run at 389pt/s.

7. **The peek slid 36pt under the camera housing.** `M5`

   The permission state hides the waveform, and the hiding was written as
   `Group { if showsWaveform { ... } }`. With the condition false that is an
   `EmptyView`, which occupies no space -- a `.frame(width:)` on nothing is
   still nothing. The HStack measured 280pt inside its 352pt frame, SwiftUI
   distributed the difference, and the left wing moved right into the cutout,
   where it is invisible on real hardware. Green at shell-local `44..59`
   became `80..95`; the cutout starts at 72.

   No error, no warning, 93 tests green. **`tools/check_notch.sh` caught it on
   the first run after the state was added.** Fixed with an `else` branch
   holding a real placeholder. See `TRAPS.md` #22.

8. **Two places asked `Now.draws` when the question was
   `Presentation.draws`.** `M5`

   Adding a state that draws *without* a track broke both:
   `PreviewData.drawing` silently excluded the permission state from every
   footprint check, and `AppController` reported a 37pt shell for a 185pt
   panel so the bounds check failed for an unrelated reason. One was caught by
   a test, the other by the check. See `TRAPS.md` #23.

9. **The permission panel said the same thing twice.** `M5`

   `PermissionPanel` leads with "Can't reach Spotify" and an explanation, then
   embedded a `PermissionNote` that explained it again in different words --
   reading as two problems rather than one. Found by capture. The note now
   takes an optional explanation and the panel passes none.

10. **Both process-hygiene checks reported "fine" for an hour while neither
    was true.** `M5`

    `pgrep -fl 'spotifyNotch/\.build'` never matched, because previews launch
    as `.build/debug/SpotifyNotch` with no directory prefix in argv. And
    `launchctl list | grep -c matchnotch` counts a *line*, which exists
    whether or not the job has a live PID.

    Cost: a preview process from a timed-out `check_notch.sh` ran unattended
    on the user's notch for an hour, and the user's own `matchnotch` agent was
    down for roughly five hours without either being noticed. Spotify's
    playback position was also found moved, with no established cause -- the
    leaked instance is the only plausible candidate and that is not proof.

    Fixed by `tools/sweep.sh`, which matches the **executable** rather than
    the command line and asks `launchctl` for the PID field rather than
    grepping for the line. `verify.sh` runs it every time. It has been shown
    failing against a real leak, a stopped agent, and a caller whose own
    command line mentions the binary. See `TRAPS.md` #24, #25.

11. **The footprint check put nineteen windows over the menu bar the user was
    typing under.** `M5`

    Reported by the user: "im typing and then it will stop me typing bc i
    guess it keeps popping up." The check launched the app once per state,
    each launch putting a panel across the top of the screen for 2.4s and
    tearing it down -- about fifty seconds of that, over the exact strip
    somebody works under.

    **The mechanism was never established.** The frontmost application does
    not change during a run (measured), and a system-wide accessibility focus
    query returned nothing useful. Three plausible contributors were fixed
    rather than one confirmed one:

    - `NotchPanel.canBecomeKey` was unconditionally `true`. A click-through
      panel that can take keyboard focus is wrong regardless; it is now
      `!ignoresMouseEvents`.
    - Nineteen process launches became **one** `--capture-server` process
      taking state names on stdin.
    - `--offscreen` parks the window at the bottom-right corner. Safe because
      the assertion is in window-local coordinates, so where the window sits
      has no bearing on it.

    Run time went from ~50s to 17s, and `verify.sh` as a whole to 29s. If the
    interruption persists, the cause is still open.

12. **Two hangs in a row rewriting that check, both leaving a window on the
    user's screen.** `M5`

    First: `mapfile -t SPECS < <(...)`. macOS ships **bash 3.2**, which has no
    `mapfile`; it failed, the array stayed empty, and the script sat there.
    Second: `exec 3> "$FIFO"` -- opening a fifo write-only **blocks until
    something opens the read end**, and the read end was the server launched
    on the next line. A deadlock, with the panel up.

    Both were cleaned up by hand within a minute or two, but this is the same
    incident as #10 twice more. Two things came out of it: the capture server
    now has a **30s idle watchdog** so an abandoned one terminates itself
    regardless of what the driving script does, and anything that launches a
    window is now tested behind an explicit kill-timer rather than run loose.

13. **The analyzer was sized for 48kHz while the tap ran at 44.1kHz.** `M6`

    `AudioTap` read `kAudioTapPropertyFormat` -- and then built `Analyzer()`
    with its default sample rate, which is the 48000 the brief's probe
    measured in September. The band edges are computed from that rate, so
    every bar would have been pointing at a frequency about 9% away from the
    one it was drawing, permanently, with the bars still moving convincingly.

    Found by printing the format in a scratch probe rather than by any test:
    the numbers are internally consistent at either rate, and nothing on
    screen distinguishes them. The fix is one argument
    (`Analyzer(sampleRate: chain.format.mSampleRate)`), and the general rule is
    `docs/TRAPS.md` #31 -- a format you asked for is only useful if you then
    use it.

14. **The bundle could never send an Apple Event, and it looked like the user
    had said no.** `M6`

    `make_app.sh` signed with `--options runtime` and no entitlements file, so
    the hardened runtime refused every Apple Event with -1743 before it left
    the process. Every read from the bundle failed; the app sat in the
    `permissionNeeded` state forever.

    It survived this long because nothing had needed the *bundle* to talk to
    Spotify: the whole of milestones 1 through 5 was verified with the debug
    binary, which is unsigned and runs under the terminal's identity. Milestone
    6 was the first thing that needed the app launched the way macOS launches
    it (`docs/TRAPS.md` #30), and the two failures compounded -- a tap that
    only works when LaunchServices starts the app, and an app that only works
    when it is not the one doing the asking.

    Diagnosis cost more than the fix, because `tccutil reset` and a relaunch
    are the obvious moves and both do nothing: there is no prompt to re-ask
    (`docs/TRAPS.md` #34). One entitlement in the signing step, and the same
    launch that had been refused four times a second came up with
    `waveform live (44100Hz)` and real Spotify data.

15. **The duplicate-instance guard never fired, because it counted itself.**
    `M7`

    `runningApplications(withBundleIdentifier:).count > 1` assumed the asking
    process is in that list. It is not, or not yet: registration happens when
    `NSApplication` starts, and the guard runs before that. So a second launch
    saw one instance, concluded all was well, and put a second panel on the
    notch -- which is the exact thing the guard exists to prevent.

    It survived five milestones because nobody had ever launched a second copy;
    milestone 7 says to confirm it against a real second launch, and the first
    real second launch broke it. Now it filters its own pid and asks whether
    any *other* instance exists, which does not depend on registration timing
    at all. Verified the same way it failed: with the agent running,
    `./SpotifyNotch.app/Contents/MacOS/SpotifyNotch` prints "SpotifyNotch is
    already running" and exits 0, and one instance remains.

16. **A paused video kept the notch for a minute after the user started their
    music.** `M9`

    Reported from use, not from a test: "it still says I'm playing from
    Aside... oh, now it fixed itself after about a minute". Exactly a minute
    is the tell -- that is how long the browser held its audio stream open
    after the video was paused.

    `AudioSources` ranked candidates by when their stream appeared, and a
    stream that is open but silent looks identical to one that is playing
    (`docs/TRAPS.md` #42). The browser's stream was newer than Spotify's, so
    it kept winning until it closed on its own.

    Fixed from both ends. Spotify's own state now decides whether Spotify is a
    candidate, because we can ask it rather than infer it -- a paused Spotify
    no longer holds a place in the ranking at all. And the tap stands a source
    down after five seconds of silence rather than only when it never made a
    sound, so a paused anything releases the notch in about five seconds
    instead of whenever its stream happens to close.

    The measurement that found it: `--sources` running across a deliberate
    four-second pause, showing `chosen: Spotify` unbroken the whole way
    through -- the state never changed, because as far as Core Audio was
    concerned nothing had.

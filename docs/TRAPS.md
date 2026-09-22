# Traps

Things that cost real time here. One numbered entry each, symptom first, so
the entry is findable from what you are seeing rather than from what was
wrong. `~/side-projects/docs/TRAPS.md` has matchnotch's 96 and they all still
apply; these are the ones this project found for itself.

Numbers are never reused. matchnotch's collided three times, once with 43-46
each existing twice for weeks, so `tools/verify.sh` runs
`grep -oE '^[0-9]+\.' docs/TRAPS.md | sort -n | uniq -d` and requires it to
print nothing. Keep the `N.` at column zero or the check cannot see the entry.

1. **A mutation harness that greps for "with 0 failures" reports every test as
   fake.** Six deliberate mutations all came back "STILL GREEN" and the tests
   were fine. `swift test` prints an `Executed N tests, with 0 failures` line
   *per suite*, so when `GeometryTests` fails, `HoverRegionTests` and
   `PaletteTests` still each print one, and `grep -q` finds them. The
   conclusion drawn from it -- "the tests are worthless" -- was confidently
   wrong and nearly led to rewriting all of them. **Use the exit code.** And
   note the shape: the *instrument* was the broken thing, which is
   matchnotch's TRAPS #56 arriving inside twenty minutes.

2. **`screencapture -R` over the menu-bar strip does not contain the panel.**
   Measured: an A/B capture of 520pt of strip with the panel running and not
   running differed in **zero columns**, while `CGWindowListCopyWindowInfo`
   reported the window onscreen at alpha 1.0 with correct bounds.
   `screencapture -o -l <windowid>` does capture it, in full. So the collapsed
   peek *is* self-verifiable -- by window capture, never by screen capture.
   matchnotch's CLAUDE.md rule 4 ("screenshots composite the notch away") is
   right about `-R` and wrong as a general claim.

3. **A black shape on a dark menu bar is the same pixels as no shape at all.**
   This is what makes #2 expensive rather than merely surprising: the first
   footprint check came back `peak RGB 0/255 CLEAN` and was believed, then
   came back identically **with the app not running**. matchnotch's
   `notch_footprint_check.py` has the same property -- it reports CLEAN
   whenever the menu bar there happens to be dark, so it is measuring the menu
   bar, not the panel. Two consequences here: `check_notch.sh` captures the
   window by id, and `--probe` fills the shell white so its geometry can be
   measured at all. **A check whose pass state is indistinguishable from its
   subject not existing is not a check.**

4. **`grep -o 'id=[0-9]*'` matches the `id` inside `pid`.** Cost one confused
   "could not create image from window" against a window id of 19531, which
   was the process id. Anchor it: `sed -n 's/.* id=\([0-9]*\).*/\1/p'`.

5. **`InverseCornerShape` draws outside its own rect**, starting at
   `rect.minX - topRadius`, so a shape framed at exactly `collapsedWidth`
   inside a window of exactly `collapsedWidth` has both shoulders clipped --
   and a clipped concave shoulder is a square corner, which is the one detail
   that separates a notch app from a black rectangle parked under the camera.
   `NotchGeometry.windowWidth` adds `shoulderRadius * 2`. Measured overhang is
   8pt against the 11pt radius, because the curve's tip is sub-pixel thin;
   11 is kept because tuning a constant to a measurement of anti-aliasing is
   not tuning.

6. **A constant chosen to sit on a contrast threshold sits on the wrong side
   of it.** white@0.35 on black composites to `#595959`, which the HIG checker
   prints as `3.0` and which actually measures **2.996:1** -- so the progress
   track was specified, twice in comments, as "exactly 3.00:1" and was below
   the non-text minimum. 0.36 is 3.14:1. **Read the unrounded number.**

7. **A hand-kept audit list cannot see a colour that did not exist when it was
   written.** `PaletteTests` enumerated two levels by name and passed a
   mutation that added a whole third palette level and audited none of it --
   matchnotch's documented drift, reproduced in this repo within the hour.
   `Palette.levels` is now the one list; `AuditReport` and the tests both
   iterate it. A level declared *outside* that array is still invisible to
   both, and that is the thing to look for when the audit looks too clean.

8. **A `static func` on a `@MainActor` class inherits the isolation**, so a
   pure function written specifically so tests could call it without a real
   pointer could not be called from a test. `nonisolated static func`. The
   error is clear; the reason it is worth an entry is that the function's own
   doc comment claimed it was callable and the comment was wrong.

9. **Spotify's AppleScript dictionary contradicts itself about `duration`.**
   The `sdef` description reads "The length of the track in seconds" and the
   type is `integer`; the value returned for a 3:29 track is `209000`. It is
   milliseconds. `player position` is the one in seconds, as a float. Also in
   that dictionary: `artwork` is documented "deprecated and will never be set.
   Use the 'artwork url' instead" -- so artwork is always a download, and any
   plan that lists `artwork (image data)` as available surface is working from
   a stale reading.

10. **The Spotify artwork URL encodes its own size in the path prefix.**
    `ab67616d0000b273…` is 640px / 226KB, `…00001e02` is 300px / 36KB,
    `…00004851` is 64px / 2.4KB; all answer 200. `artwork url` hands you the
    640 one, so the default path downloads 226KB to draw a 24pt thumbnail.

11. **The playback notification carries the entire track payload, and the plan
    assumed it was only a trigger.** `com.spotify.client.PlaybackStateChanged`
    arrives with `Name`, `Artist`, `Album`, `Album Artist`, `Duration`,
    `Playback Position`, `Player State`, `Track ID`, `Has Artwork`,
    `Track Number`, `Disc Number`, `Play Count` and `Popularity` in its
    `userInfo`. So the ordinary case needs **no Apple Event at all** -- not
    the 3.34ms, not the permission, nothing. The brief's "on each notification
    read `player position` once" describes a round trip that is not needed.
    Apple Events are left doing four jobs: the read at launch before any
    notification has fired, the artwork URL (the one field omitted), the
    reconcile tick, and sending commands. **Look at what an event actually
    carries before designing a read around it.**

12. **`Player State` is capitalised in the notification and lowercase in
    AppleScript.** `Playing`/`Paused` from `userInfo`, `playing`/`paused` from
    `player state as text`. One enum, two vocabularies, and a `==` against
    either spelling is wrong on the other path. Decode case-insensitively and
    leave an unknown value visibly unknown -- matchnotch's #96 with a second
    spelling bolted on.

13. **`NSAppleEventDescriptor.int32Value` rounds a `doub` descriptor.**
    `player position` comes back as `doub`; `int32Value` on `23.69` is `24`,
    silently quantising the progress bar to whole seconds. `stringValue` is
    correct for `utxt`, `long` **and** `doub`, so one uniform path over the
    list is both lazier and the only correct one.

14. **A seek made while Spotify is paused publishes nothing.** Measured: a
    `set player position` while paused produced no notification, and the
    reconcile tick is deliberately off while paused (a timer is only cheap if
    the pixels change). So the position can be stale until playback resumes.
    Currently invisible, because the collapsed peek draws no progress bar --
    the fix is one `refresh()` when the panel expands, which is the moment it
    starts mattering. Recorded so it is a known ceiling rather than a bug
    somebody rediscovers.

15. **A default argument expression is evaluated nonisolated**, so
    `init(bridge: SpotifyBridge = SpotifyBridge())` does not compile on a
    `@MainActor` type even though the initialiser itself is isolated. Take an
    optional and build it in the body. Nested *types* are a separate case:
    they never inherit the enclosing actor's isolation, and `nonisolated`
    cannot be applied to them at all.

16. **Two Spotify marks, and every test was green.** The peek draws a small
    mark outboard of the cover, and `ArtworkView` draws the mark when there is
    no cover -- so a podcast rendered both, side by side, at two different
    sizes. It reads as a rendering bug and it is invisible in the code, which
    has one `if` in each of two files that are correct on their own.
    Found by capturing the `noart` state and *looking at it*.
    The fix has three cases, not two: cover loaded (cover + standalone mark),
    cover **pending** (empty square + standalone mark), no URL at all (mark in
    the square, standalone hidden). Pending drawing the mark would have shown
    two logos for the length of every download.
    Both decisions are now functions -- `PeekView.showsStandaloneMark` and
    `ArtworkView.showsPlaceholderMark` -- specifically so a test can *call*
    them and assert that exactly one is true for every combination. A rule
    restated in a test file instead of called stays green through any change
    to the real code.

17. **`check_notch.sh` hung for two minutes on a stale binary.** A flag was
    added to `main.swift`, the script was run without rebuilding, and the
    binary it invoked did not know the flag -- so it fell through to
    `app.run()` and the `while read` loop waited forever on output that was
    never coming. This is matchnotch's rule 2 ("`swift build` does not update
    the running notch") arriving in a new costume, and it will keep doing
    that. The script now rebuilds when any source is newer than the binary.
    **Any script that shells out to your own binary should check it is not
    older than the code it is testing.**

18. **A collision test that cannot collide.** `testTwoAlbumsCannotCollideOnDisk`
    used two URLs differing in their last path component, so a mutation that
    keyed the cache filename on `lastPathComponent` instead of the whole URL
    stayed **green**. The real collision is two different URLs whose last
    components *match* -- `i.scdn.co/image/cover.jpg` against
    `mosaic.scdn.co/image/cover.jpg`. The test's name was a claim; the mutation
    run was what checked it. **Name a test after the failure it prevents, then
    ask whether its inputs can actually produce that failure.**

19. **A mutation that does not mutate reports a false gap.** Two of eleven
    mutations in the milestone-3 run came back "STILL GREEN", and both times
    the test was fine and the mutation was not.
    One changed `String(format: "%d:%02d", m, s)` to use `total / 60` -- but
    that branch only runs when `h == 0`, where `m` *is* `total / 60`. The text
    changed and the behaviour did not.
    The other was a `sed` pattern written with `\\\\(` against a source
    containing `\\(`, so it matched nothing and silently did no work; `sed`
    exits 0 when its pattern does not match.
    **Before believing a green mutation, check the file actually changed and
    that the change alters behaviour.** This is the second time the mutation
    *harness* has been the broken thing -- see #1. A tool used to judge tests
    needs its own sanity check more than the tests do.

20. **Cropping a 2x capture with point coordinates silently gives you the
    top-left quarter.** `screencapture` writes backing pixels, so a 374x153pt
    window is a 748x306px file, and asking `crop.py` for `352x137` returns a
    quarter of the panel -- which looks like a layout bug, because the content
    that should be centred is off the right edge. Twenty seconds to spot, but
    only because the wrongness was gross. A crop that is off by a factor of
    two in a *subtle* direction would have been read as a design problem and
    fixed in the wrong place.

21. **`.contentShape` before `.frame` passes every unit test.** Proved here
    rather than inherited: putting the modifier in the wrong order on the
    transport button left all 88 tests green, left the centre of the button
    working, and killed the outer 22pt of a 44pt target. A real click probe
    caught it immediately:

    ```
    ok    the glyph itself                      x=960   HIT
    FAIL  inside the frame, right of the glyph  x=978   got DEAD, wanted HIT
    FAIL  inside the frame, left of the glyph   x=942   got DEAD, wanted HIT
    ok    past the frame, in the gap            x=988   DEAD
    ```

    **The centre still works, which is why it survives casual testing** -- you
    press the button, it responds, and the four-clicks-in-five that miss feel
    like a trackpad problem. matchnotch had this at six call sites, each with
    a comment claiming a 44pt target, and found it from a phone video.
    `tools/hit_probe.sh` runs the probe above. It is not in `verify.sh`
    because it clicks real buttons and therefore changes playback; run it
    after touching the panel's layout. **A rule that no unit test can see
    needs a check that is not a unit test**, and that check needs to be shown
    failing before it is believed.

22. **`Group { if x { View() } }` with `x` false is an `EmptyView`, and an
    `EmptyView` occupies nothing -- so the parent silently re-centres
    everything.** The permission peek hides the waveform, which emptied the
    right wing. The HStack then measured 280pt inside its 352pt frame, SwiftUI
    distributed the difference, and the whole left wing slid **36pt right --
    straight under the camera housing**, where it is invisible on real
    hardware. `44..59` became `80..95` in a cutout that starts at 72.

    Nothing errored. No warning, no layout complaint, and `swift test` stayed
    green because this is SwiftUI's arithmetic, not ours. A `.frame(width:)`
    applied to nothing is still nothing, so the wing did not even hold its
    own width.

    **`tools/check_notch.sh` is what noticed**, on the first run after the
    state was added -- which is the entire argument for that check existing.
    The fix is an `else` branch with a real placeholder
    (`Color.clear.frame(width:height:)`), not a conditional frame.

    Family resemblance to matchnotch's #59 (`Color.clear` is greedy) and #57
    (a fixed-height frame centres a taller child): **SwiftUI resolves a layout
    it cannot satisfy by moving things, never by complaining**, and the result
    is always a picture that looks deliberate.

23. **Two places asked `Now.draws` when the question was `Presentation.draws`.**
    Adding a state that draws *without* a track -- the permission prompt --
    broke both: `PreviewData.drawing` silently excluded it from every footprint
    check, and `AppController` reported a 37pt shell for a 185pt panel so the
    bounds check failed for a reason unrelated to the bug in front of it.
    One was caught by a test, the other by the check. **When a predicate moves
    to a new type, grep for the old one** -- `draws` existed on two types and
    reading fine at both call sites is exactly how it survives review.

24. **Two hygiene checks that reported "fine" for an hour while neither was
    true.** Both were mine, both read plausibly, and both were the wrong
    question.

    `pgrep -fl 'spotifyNotch/\.build'` never matched anything, because the
    previews are launched as `.build/debug/SpotifyNotch` -- a relative path,
    with no directory prefix in argv. So "leaks: none" was printed after every
    milestone while a process from a timed-out run sat on the notch for an
    hour.

    `launchctl list | grep -c matchnotch` counts a **line**, and the line
    exists whether or not the job has a live PID. The reference app was down
    and the check kept answering 1. `launchctl list` prints `-` in the PID
    column for a loaded-but-not-running job; ask for `$1`, not for the count.

    `tools/sweep.sh` does both properly and `verify.sh` runs it. **A check
    that can only print "fine" is not a check** -- run it once against the
    failure it is supposed to catch before trusting it. That is now three
    separate times in this project that the instrument was the broken thing
    (#1, #19, this one).

25. **Killing a hung script's child restarts the script.** `check_notch.sh`
    was blocked in `while read ... < <("$BIN" --check-states)` against a
    binary that did not have the flag. Killing that binary did not clean
    anything up -- it *unblocked the read*, and the script cheerfully carried
    on launching previews onto the notch an hour after it had been abandoned.
    Kill the script first, then its children, then sweep for orphans: a
    preview whose parent dies is reparented to `launchd` (ppid 1) and outlives
    everything you thought you had killed.

26. **macOS ships bash 3.2, and a bash 4 builtin fails silently.** `mapfile`
    does not exist there; under `set -uo pipefail` (no `-e`) the array simply
    stays empty and the script carries on into a deadlock. Neither `readarray`
    nor `declare -A` nor `${var^^}` is available either. Use
    `while IFS= read -r x; do ... done < <(...)`, and remember that
    `/bin/bash --version` is the authority, not whatever bash is on `PATH`.

27. **`exec 3> fifo` blocks until a reader opens the other end.** If the reader
    is a process the same script launches on the next line, that is a
    deadlock. `exec 3<> fifo` opens read-write and returns immediately, which
    is the standard idiom and the only one that works when the script owns
    both ends.

28. **`sed -n 's/pattern/\1/p'` keeps the part of the line it did not match.**
    Scraping a count with `s/^checking \([0-9]*\) states/\1/p` returned
    `19 in one window` the moment the line grew a suffix, and the integer
    comparison downstream failed with a message about the wrong thing. For
    extracting a field, use `awk '{print $2}'`; `s///p` is for rewriting a
    line, not for reading one.

29. **Anything that puts a window on screen needs a watchdog of its own.** The
    driving script's `trap cleanup EXIT` is the first defence and it is not
    enough: it does nothing when the script deadlocks, and nothing for a child
    reparented to launchd. The capture server now exits after 30s with no
    input, so nobody can leave one on the notch by making a mistake in a shell
    script. **A process the user cannot quit must be able to quit itself.**

30. **A process tap's permission belongs to the *responsible* process, not to
    the binary you ran.** `M6` Run the app's own executable from a shell and
    the terminal is responsible; a terminal has no
    `NSAudioCaptureUsageDescription`, so TCC denies without ever prompting --
    and denial does not look like denial. `AudioHardwareCreateProcessTap`
    returns `noErr`, the aggregate is created, the IOProc fires forty times a
    second with 1024 frames a time, and **every sample is exactly 0.0**. The
    same binary in the same bundle, launched through LaunchServices, delivers
    real audio immediately.

    So: `open -a SpotifyNotch.app --args --bands 8`, never
    `./SpotifyNotch.app/Contents/MacOS/SpotifyNotch --bands 8`. Use
    `open --stdout FILE --stderr FILE` to see what it printed -- `open`
    detaches stdout otherwise, and this is the whole reason an earlier attempt
    to read the result out of `log show` came back empty and looked like a
    failure of the tap.

31. **`kAudioTapPropertyFormat` follows the current output device.** `M6` The
    brief's probe measured 48000 Hz; an hour of the user's afternoon later,
    with a USB output selected, the same call returned **44100 Hz**. Sizing
    the log band edges for a hard-coded rate puts every bar ~9% off the
    frequency it claims, and nothing on screen would ever reveal it. Ask the
    tap, pass the answer to the analyzer (`docs/BUGS.md` #13).

32. **Digital silence and no permission are the same bytes.** `M6` There is no
    public API to check or request `NSAudioCaptureUsageDescription`, so the
    only signal available is that the samples are all zero -- which is also
    what a genuinely silent passage looks like. The rule has to be a timeout
    (`AudioTap.hasGoneSilent`), and it has to be reversible: one non-zero
    sample and the waveform is live again on the next frame.

33. **A rebuilt ad-hoc-signed bundle can lose its Automation grant.** `M6`
    `./make_app.sh release` re-signs, and the next launch logged
    `Automation permission refused (-1743)` four times -- so `SpotifyService`
    never reached `.track(playing)` and the tap it drives never started. The
    app was not broken and the code had not changed. Check `--read` from the
    **bundle** before concluding anything about the live app, and reach for
    `tools/reset-permissions.sh` when the answer is -1743.

34. **The hardened runtime blocks Apple Events unless the app is entitled to
    send them, and the failure is indistinguishable from a denied user.** `M6`
    `codesign --options runtime` without
    `com.apple.security.automation.apple-events` makes every event fail with
    **-1743**, the same `errAEEventNotPermitted` a refusal produces -- and
    macOS **never prompts**, because there is no TCC decision to make. So
    `tccutil reset AppleEvents` changes nothing, relaunching changes nothing,
    and the app looks like one the user denied months ago.

    The tell is that there was never a prompt. A real denial was preceded by a
    dialog somebody clicked. If -1743 arrives on the very first event of a
    freshly reset bundle, suspect the signature, not the user --
    `codesign -d --entitlements - SpotifyNotch.app` settles it in a second.

    Ad-hoc signing does not exempt anything: `--sign -` still applies the
    hardened runtime's rules. `make_app.sh` writes the entitlement now
    (`docs/BUGS.md` #14).

35. **A `GeometryReader` inside an animated `.frame()` never sees the
    animation.** `M7` The frame probe's first version reported the drawn height
    through a preference and counted the changes; it recorded exactly one
    value per transition -- the destination -- for an animation that visibly
    took 0.7 seconds. SwiftUI interpolates the *rendered* geometry without
    re-running the layout pass that feeds a reader, so the reader sees the
    start and the end and nothing in between.

    The value SwiftUI's driver does set once per rendered frame is
    `animatableData`. Hook that (matchnotch's `PageProbe` does the same), and
    only on **one** shape per animation: two shapes animating the same value
    double every count.

36. **`open -a` will not start a second copy of an app that is running**, so a
    measurement that needs two processes silently measures one twice. Both
    `pgrep` lookups returned the same pid and the comparison read "tap only
    8.90%, full agent 8.90%" -- a perfectly plausible wrong answer. `open -n`
    is the flag. The tell was the two numbers being *identical* rather than
    close.

37. **A `Button` survives a non-key window; a `DragGesture` does not.** `M8`
    The panel never activates the app, so it is almost never the key window,
    and AppKit hands an inactive window's first click to the window rather than
    to the view under it -- unless that view returns `acceptsFirstMouse`. A
    SwiftUI `Button` acts on mouse-**up** and works anyway, which is why the
    transport row worked for four milestones and hid this completely. A drag
    needs the mouse-**down** that was being eaten: the progress line could not
    be grabbed at all, with no error and no gesture, the pointer just sliding
    over it. Host the content in an `NSHostingView` subclass that returns true
    (matchnotch needed the same subclass for its popover).

38. **A `ZStack` is as tall as its tallest child, and a shape inside one fills
    that.** `M8` Adding a 7pt knob to the stack holding the 3pt progress bar
    made the *bar* 7pt along its whole length. The outer `.frame(height: 3)`
    did not stop it: a frame positions content it cannot shrink. Give each
    shape its own height and put the knob in an `.overlay`, which cannot
    influence the size of what it sits on. Found by measuring a capture --
    at 3pt against 7pt on a black panel, the eye does not notice.

39. **A window probe must not run while the installed agent is up.** `M8`
    `hit_probe.sh` launches its own panel, and the agent's panel is at the same
    coordinates on the same window level -- so the clicks land on whichever is
    on top and the probe reports the transport row as dead. It looks exactly
    like a regression in the panel, which is an hour spent hunting one that is
    not there. The probe now refuses to run when the app is up, and the same
    caution applies to anything else that drives the real pointer at the notch.

40. **`.onHover` never fires on this panel.** `M8` Tracking areas want an
    active application, and this one is `.accessory` and never activates --
    verified by capturing the panel with the pointer sitting on the progress
    line, which drew its resting state. So no control here can use hover as its
    only affordance: the scrub knob is drawn whenever the line is draggable
    rather than revealed by pointing at it.

41. **An enlarged hit area is three separate mistakes, and only a live probe
    tells you which one you made.** `M8` The scrub band was wrong twice before
    it was right, and both wrong versions looked correct in the code and in a
    capture:

    - `.contentShape(Rectangle())` on an outer view whose **gesture is on an
      inner one** does nothing. The shape and the gesture have to be on the
      same view. Only the 3pt line answered, which the user reported as "it
      works about half the time".
    - `.frame(height: 30)` on a child of a `GeometryReader` does **not** centre
      it -- the reader pins children to its top-leading corner -- and a
      `.offset` to correct that moved the drawing without moving the band. The
      result hung entirely below the line: dead 11pt above it, live 22pt below
      it, reaching into the transport row.
    - Symmetric `.padding` is the version that works, because it cannot be
      asymmetric: pad, shape, gesture, then negative padding to give the layout
      back. `docs/TRAPS.md` #21's ordering rule, with the gesture in the middle.

    The probe is three clicks at the band's centre and both edges, checking
    whether `player position` moved. Reasoning about which of the three is
    wrong, from the code, is how two of them shipped.

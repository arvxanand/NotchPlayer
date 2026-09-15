# Decisions

Why things are the way they are, so a later change is an argument rather than
a surprise. Fixed by the user and not to be re-opened: Spotify only via its
AppleScript dictionary; a real FFT from a Core Audio process tap on Spotify's
PID; show and control, no scrubbing in v1; zero third-party dependencies.


- [Copy matchnotch's `Notch/` rather than rewrite it](#copy-matchnotchs-notch-rather-than-rewrite-it)
- [The peek stays inside the menu-bar strip](#the-peek-stays-inside-the-menu-bar-strip)
- [No global hotkey and no media-key registration](#no-global-hotkey-and-no-media-key-registration)
- [No app icon](#no-app-icon)
- [`--probe` exists because the peek is otherwise unmeasurable](#probe-exists-because-the-peek-is-otherwise-unmeasurable)
- [Hardened runtime, ad-hoc signed, unsandboxed](#hardened-runtime-ad-hoc-signed-unsandboxed)
- [The notification is the data source, not just the trigger](#the-notification-is-the-data-source-not-just-the-trigger)
- [`Permission` is tracked separately from `Now`](#permission-is-tracked-separately-from-now)
- [The artwork URL comes from Spotify, not from an unauthenticated endpoint](#the-artwork-url-comes-from-spotify-not-from-an-unauthenticated-endpoint)
- [Peek content is centred in the strip, not on the menu bar's own centre line](#peek-content-is-centred-in-the-strip-not-on-the-menu-bars-own-centre-line)
- [The cover is 25pt, the corner 5pt](#the-cover-is-25pt-the-corner-5pt)
- [Exactly one Spotify mark, ever](#exactly-one-spotify-mark-ever)
- [One artwork fetch per track, at 300px](#one-artwork-fetch-per-track-at-300px)
- [The panel grows downward and keeps its width](#the-panel-grows-downward-and-keeps-its-width)
- [The title truncates; it never wraps](#the-title-truncates-it-never-wraps)
- [Peek and panel cross-fade rather than swap](#peek-and-panel-cross-fade-rather-than-swap)
- [The panel refreshes the moment it opens](#the-panel-refreshes-the-moment-it-opens)
- [Transport is three plain buttons, not stock controls](#transport-is-three-plain-buttons-not-stock-controls)
- [44pt targets, 18 and 22pt glyphs, 56pt apart](#44pt-targets-18-and-22pt-glyphs-56pt-apart)
- [The transport row's spacing was measured, not chosen](#the-transport-rows-spacing-was-measured-not-chosen)
- [Clicking the panel does not steal focus](#clicking-the-panel-does-not-steal-focus)
- [`Presentation` resolves what to draw; the views do not](#presentation-resolves-what-to-draw-the-views-do-not)
- [A refusal costs the cover and the buttons, nothing else](#a-refusal-costs-the-cover-and-the-buttons-nothing-else)
- [The settings link was verified, not assumed](#the-settings-link-was-verified-not-assumed)
- [`SuspendingClock` for progress interpolation](#suspendingclock-for-progress-interpolation)
- [The progress line is a value and a rect](#the-progress-line-is-a-value-and-a-rect)
- [`verify.sh` uses exit codes, not greps, for the test stage](#verifysh-uses-exit-codes-not-greps-for-the-test-stage)

## Copy matchnotch's `Notch/` rather than rewrite it

It has already solved everything that is about the notch rather than about
Spotify, and rewriting it means rediscovering 96 traps one at a time. The copy
is *smaller* than the original: there is one panel width, so `wideWidth` and
`panelFrame(contentWidth:)` are gone; and there is no swipe gesture, so
`HoverWatcher` loses its global scroll monitor and with it the whole question
of whether a global monitor needs an `NSApplication`.

## The peek stays inside the menu-bar strip

`collapsedHeight == notchHeight`, nothing hanging below. matchnotch's peek
hangs 26pt into what is usually a browser's tab bar, which is why brushing the
cutout lit it from across the screen, and why hover-to-expand ships **off by
default** there. Staying in the strip makes that class of bug unreachable,
which is what lets hover be this app's primary gesture as designed.

## No global hotkey and no media-key registration

Spotify's own Now Playing already answers the media keys. Registering them too
means designing around a conflict; not registering them means there is no
conflict. It also removes matchnotch's TRAPS #33 -- the click that opens a
panel from a menu bar is itself an outside click, and with clicks detected by
polling, the race made "Open panel" look dead.

## No app icon

TRAPS #65: an icon is a second way to launch the app, and a second instance
stacks a second panel on the same notch with no dock icon and no Quit to get
rid of either. `main.swift` guards on the bundle id anyway; not shipping an
icon keeps the guard a backstop rather than the only defence.

## `--probe` exists because the peek is otherwise unmeasurable

A black shape on a dark menu bar is the same pixels as no shape (TRAPS #3), so
"the shoulders are drawn" would be a claim with nothing behind it. `--probe`
fills the shell white, `check_notch.sh` captures the window by id, and
`tools/pixel_check.py` asserts the bounds. The first run measured 400x37pt
with 8pt of shoulder overhang, which is the first time anything about the
collapsed peek has been verified rather than inferred.

## Hardened runtime, ad-hoc signed, unsandboxed

Unsandboxed because App Sandbox blocks Apple Events without a temporary
exception for `com.spotify.client`, and this is not going to the App Store.
Hardened runtime because the brief asks for it. The cost is real and not yet
measured: an ad-hoc signature changes on every build, so macOS may treat each
build as a new app and re-ask for Automation and Audio Capture.
`tools/reset-permissions.sh` is the way out. If it turns out to re-prompt on
every build, the fix is a self-signed identity from Keychain Access, which
gives a stable designated requirement.

## The notification is the data source, not just the trigger

Measured on 14 Sep 2026: `PlaybackStateChanged` carries the whole track in its
`userInfo`, so the ordinary case costs no Apple Event. The plan was written
expecting to read `player position` on every notification; that read is gone.
What remains on Apple Events: the launch read, the artwork URL, the reconcile
tick, and commands.

Also measured, and why the reconcile tick is not optional: play and pause each
fired exactly once, and ~4s of uninterrupted playing fired nothing at all.

## `Permission` is tracked separately from `Now`

Falls straight out of the above. `DistributedNotificationCenter` needs no
permission, so with Automation refused the app still knows the track, the
artist, the album and the position -- it cannot fetch the cover or send a
command. Folding that into one enum would force a choice between showing a
permission error over a perfectly readable track and hiding the reason the
buttons do nothing. So `.denied` degrades to "everything but the artwork and
the controls" rather than to a dead end.

The consequence worth remembering: **the app is useful before the user grants
anything.** The Automation prompt should therefore not be provoked at launch
for its own sake.

## The artwork URL comes from Spotify, not from an unauthenticated endpoint

`https://open.spotify.com/oembed?url=<track uri>` would return a thumbnail
without Apple Events or auth, which would make the whole display work with
zero permissions. Not taken: it adds a network round trip to a third-party
endpoint per track change to avoid a 3.34ms local call the app already needs
permission for in order to have working buttons. Worth reopening only if the
no-permission path ever has to include artwork.

## Peek content is centred in the strip, not on the menu bar's own centre line

The menu bar's optical centre was measured, not guessed: capturing 300pt of
real menu bar and finding the rows that differ from their own median puts the
glyph band at pt 14.0-27.5, 13.5pt tall, centred at **20.8**. The geometric
centre of the 37pt strip is 18.5, so menu bar content sits 2.3pt lower than
the obvious answer.

Content here is centred at 18.5 anyway. Four variants were rendered -- 24 and
26pt covers against both alignments -- and at 20.8 the cover reads as sitting
low, with visibly more black above it than below. The measurement is right
about a 13.5pt glyph in a 37pt bar; it is wrong about a 25pt cover, because
the black shell is a strong frame and the eye centres against *that*, not
against status items 30pt away across a black gap.

Kept here rather than deleted because "align to the menu bar" is an obvious
idea that someone will have again.

## The cover is 25pt, the corner 5pt

25 in a 37pt strip leaves exactly 6pt above and below. 24 left the strip
looking underfilled; 26 was tight against a shell whose bottom corners already
curve. A 6pt corner on a 24pt square read as an iOS app icon rather than a
record sleeve -- obvious in the render, invisible in the number.

## Exactly one Spotify mark, ever

Three cases rather than two, and the pending case is the subtle one. See
`docs/TRAPS.md` #16.

## One artwork fetch per track, at 300px

The URL encodes its own size and `artwork url` hands over the 640px variant --
226KB to draw a 25pt thumbnail. 300px is 36KB and covers the panel's 72pt
cover at 2x with room; the peek downscales from the same bytes. Fetching the
64px variant too would save 33KB and cost a round trip.

The swap only fires when the prefix is the measured album-art one. Podcast and
playlist images use different prefixes and a blind 16-character swap would
turn them into a 404 -- which, because the loader validates the body rather
than the status code, would show up as a missing cover rather than an error.

## The panel grows downward and keeps its width

352pt in both states, 37pt tall collapsed and 137 expanded. One width means
`NotchGeometry` needs no `wideWidth` and no `panelFrame(contentWidth:)`, and
the shoulders never move -- only the bottom edge travels, which is what makes
the morph read as the notch stretching rather than as a window appearing.

100pt of travel at the spring's 0.38s response is ~4.4pt per frame average at
60Hz. The division is done in a test rather than after the fact, because the
number that decides whether motion looks fluid is points-per-frame and
matchnotch spent four architectural fixes learning that.

## The title truncates; it never wraps

A title that wraps changes the panel's height, and a panel that resizes per
track jumps every time the song does. `longtitle` exists as a preview state
specifically so the truncation is looked at, and its title is comfortably past
the limit rather than sized to it -- preview data sized *to* a cap hides the
cap.

## Peek and panel cross-fade rather than swap

Both layers are always present, with opacity animated. Not a `.transition`
combined with `.opacity`, which makes both views semi-transparent at once so
they show through each other. Here they never overlap: the peek's content is
in the wings and the panel's is below the menu-bar line.

The panel fades in over 0.14s with a 0.06s delay, **not** timed to the spring.
A spring's last few percent of travel is its slowest, so a fade matched to its
nominal duration visibly hangs at the end. The shell reaches most of its
height early and the content should arrive then.

## The panel refreshes the moment it opens

A seek made in Spotify's own window while paused publishes no notification,
and the reconcile tick is off while paused -- so the stored position can be
stale. It is invisible in the peek, which draws no progress bar. Opening the
panel is the exact moment it starts mattering, so that is where the re-read
goes. `Expansion.onOpen`.

## Transport is three plain buttons, not stock controls

The panel never becomes key, and AppKit draws its own controls in the inactive
grey style in a window like that -- so a stock button would look disabled,
which for a play button is the worst possible lie. matchnotch carries three
entries about this (#5, #31, #49) and ends up hand-drawing its switch. A
`.plain` button with an explicit `.foregroundStyle` has no inactive state to
draw, so the problem never arises. Confirmed by capture: the glyphs render
white, not grey.

## 44pt targets, 18 and 22pt glyphs, 56pt apart

Drawn size and tappable size are different questions. The centre glyph is
bigger because it is the one people aim at without looking; every target is
the HIG minimum regardless. 56pt centre-to-centre is close enough to read as
one control and far enough that a trackpad miss lands in the 12pt gap rather
than skipping a track when it meant to pause -- and a test asserts that gap
exists.

`tools/hit_probe.sh` clicks the real thing to prove the whole target is live.
See `docs/TRAPS.md` #21 for why a unit test cannot do this.

## The transport row's spacing was measured, not chosen

Three spacings rendered; the gaps above and below the glyphs came out 23/25,
19/21 and 16/18. All balanced, so the question was only tightness -- and the
text block above has a ~20pt gap of its own between the artist and the
progress line. 19/21 matches that rhythm. 16 reads as cramped against a block
spaced more loosely than itself; 23 reads as a separate zone.

## Clicking the panel does not steal focus

Verified, not assumed: clicking play/pause on the live app left the frontmost
application unchanged. `.nonactivatingPanel` plus an `.accessory` activation
policy is what does it. Worth re-checking if either ever changes -- matchnotch
TRAPS #19 records that `.nonactivatingPanel` does not prevent *programmatic*
activation, so a future `NSApp.activate` anywhere would undo this quietly.

## `Presentation` resolves what to draw; the views do not

There are four ways to have nothing playing -- Spotify closed, Spotify open
with nothing loaded, Automation refused, and a read that did not come back --
and they are not the same answer. `Presentation.of(now:permission:)` turns the
two axes into the three things that can actually be on screen, so the rule is
a function a test can call rather than a pile of `if`s in a view body.

`draws` lives on it, and `PreviewData.drawing`, `AppController` and the
footprint check all ask it. `Now.draws` still exists and is the wrong question
for anything about rendering -- see `docs/TRAPS.md` #23.

## A refusal costs the cover and the buttons, nothing else

This is downstream of the notification carrying the whole payload. With Apple
Events refused the panel still knows the track, the artist and the position;
only the artwork fetch and the three commands need permission. So `.denied`
mid-track is a fully readable panel whose transport row is replaced by a
sentence -- not an error screen, and not three buttons that swallow every
press.

The one state that draws without music is a refusal *at launch*, when nothing
is known at all. Without it the app is silently dead and the user has no way
to find out why, which is the failure `Now.unknown` exists to prevent. It
cannot fire while Spotify is quit: `refresh` answers `.notRunning` without
sending an Apple Event, so there is nothing to be refused.

## The settings link was verified, not assumed

`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`
opens System Settings directly on the **Automation** pane on macOS 15.7.7 --
checked by opening it and photographing the window. A deep link that silently
lands on the wrong pane is worse than a plain sentence, because the user
follows it and finds nothing.

## `SuspendingClock` for progress interpolation

Spotify's `player position` does not advance while the Mac is asleep, and a
`SuspendingClock` does not either -- so the two agree across a lid close
without any correction. `ContinuousClock` counts sleep and would come back
wrong by exactly its duration. The `NSWorkspace.didWakeNotification` re-read
stays as well, because matchnotch's TRAPS #91 is specifically that an existing
observer on the right notification is not coverage.

## The progress line is a value and a rect

Scrubbing was deferred, not rejected, and `player position` is writable. Built
as `(fraction, rect)` so the drag is a gesture plus one write rather than a
rewrite.

## `verify.sh` uses exit codes, not greps, for the test stage

TRAPS #1. Greping for "with 0 failures" matches a sibling suite that passed
while the one you broke was red.

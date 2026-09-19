# Wanted

Things we decided not to build yet, in plain terms. Each one says why it was
left out, so picking it up later is a decision and not an excavation.

Nothing here is a bug. `docs/BUGS.md` is for those.

## 1. Drag the progress bar to scrub

Right now the progress line shows the position; it does not accept a drag.

Deferred in v1 on purpose, but built to be picked up: `player position` is
writable (checked), and the line is drawn as a fraction plus a rect, so this
is a drag gesture and one write rather than a rewrite.

## 2. A switch to turn off the album-art download

The one thing that leaves the machine is the cover image, fetched from
Spotify's own CDN with the URL Spotify hands over. Everything else -- the
audio, the track data -- is local.

If you want literally nothing outbound, this is a menu toggle plus a
`UserDefaults` flag. The fallback already exists: the Spotify mark stands in
whenever there is no cover.

## 3. Make the waveform cheaper to draw

Measured: the tap and the FFT cost 0.8% of a core; the whole app costs ~8.9%
while the bars move at 30fps. The arithmetic is free, the drawing is not.

Two things that did **not** help, both measured: a `Canvas` instead of
fourteen views, and taking the bars out of the layout. The real fix is a
`CALayer` the tap writes into, skipping SwiftUI's per-frame work entirely.

Not taken because every number above was measured with Low Power Mode on, and
tuning against a distorted measurement buys complexity and nothing else.
**Re-measure with it off before touching this.**

## 4. Show something for ads, podcasts and local files

Nobody has seen what Spotify reports for any of them. A podcast is probably
just a track with a different artist line, and an ad probably has no artwork
-- but "probably" is why there is no special handling and one test fixture is
marked `CONSTRUCTED`.

Watch `--watch` while an ad plays, then decide. Guessing at a vendor's ad
metadata is how you ship a boolean that is wrong six months later.

## 5. External display and clamshell

Explicitly out of scope: built-in display only, nothing drawn with the lid
shut. The code already behaves correctly by construction -- it looks for a
screen with a notch and draws nothing when there isn't one -- but it has never
been run with a monitor attached.

## 6. Launch at login as a toggle

Installing and removing the LaunchAgent is two shell commands
(`tools/install-agent.sh`, `launchctl bootout`). A checkbox in the menu panel
would be friendlier. Small, and nobody has needed it yet.

## Decided against, not deferred

So these don't come back as suggestions:

- **Media keys and a global hotkey.** They would fight every other app that
  claims them, and hovering the notch is the gesture. `docs/DECISIONS.md`.
- **An app icon.** A second way to launch is a second panel on one notch.
- **Anything other than Spotify.** Fixed at the start.
- **Third-party dependencies.** Also fixed at the start, and still zero.

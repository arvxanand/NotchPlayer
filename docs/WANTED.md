# Wanted

Things we decided not to build yet, in plain terms. Each one says why it was
left out, so picking it up later is a decision and not an excavation.

Nothing here is a bug. `docs/BUGS.md` is for those.

**Done since this list was written:** dragging the progress bar to scrub, and
making the waveform cheap to draw -- 8.9% of a core down to 1.7%, by taking
SwiftUI out of the per-frame path.

## 1. A switch to turn off the album-art download

The one thing that leaves the machine is the cover image, fetched from
Spotify's own CDN with the URL Spotify hands over. Everything else -- the
audio, the track data -- is local.

If you want literally nothing outbound, this is a menu toggle plus a
`UserDefaults` flag. The fallback already exists: the Spotify mark stands in
whenever there is no cover.

## 2. Show something for ads, podcasts and local files

Nobody has seen what Spotify reports for any of them. A podcast is probably
just a track with a different artist line, and an ad probably has no artwork
-- but "probably" is why there is no special handling and one test fixture is
marked `CONSTRUCTED`.

Watch `--watch` while an ad plays, then decide. Guessing at a vendor's ad
metadata is how you ship a boolean that is wrong six months later.

## 3. External display and clamshell

Explicitly out of scope: built-in display only, nothing drawn with the lid
shut. The code already behaves correctly by construction -- it looks for a
screen with a notch and draws nothing when there isn't one -- but it has never
been run with a monitor attached.

## 4. Launch at login as a toggle

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

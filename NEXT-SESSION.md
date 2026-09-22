# Prompt for a fresh session

Paste everything below the line into a new chat, in this repo.

---

You are picking up a macOS app I have been building with you across several
sessions: **SpotifyNotch**, in `~/spotifyNotch`. It turns the MacBook notch
into a now-playing display with a real FFT waveform, and it is installed and
running on this machine as a LaunchAgent right now.

## First, read — do not write anything yet

Read these in order, completely, before you touch code or answer me:

1. `HANDOFF.md` — written to be read cold. Start here. Pay attention to "The
   rules that break a new notch app" and "What has never been
   checked".
2. `docs/TRAPS.md` — 41 entries, classes of mistake with the fix. Read before
   debugging anything.
3. `docs/BUGS.md` — 15 specific defects and what each cost.
4. `docs/DECISIONS.md` — 35 entries, why things are the way they are. Do not
   re-open a decision without reading its entry first.
5. `docs/WANTED.md` — what we deliberately have not built.
6. `README.md` — the commands.

Then skim the code: `Sources/SpotifyNotchCore/Data/` (Spotify bridge, the
tap, the FFT) and `Sources/SpotifyNotchCore/Views/`.

When you are done, tell me in a few sentences what the app does, what the
open bug is, and what you think the next step is. **Do not start coding until
I answer.**

## Where we left off

Everything through **milestone 8** is committed and shipped: drag-to-seek,
the CALayer waveform, the menu-bar item. `./tools/verify.sh` is green except
for one line about `matchnotch` — that is my other notch app being down, it
is not yours to fix, and I will restart it myself.

Milestone 9 (following any app's audio, not just Spotify's) was built and then
**reverted on purpose**: I do not want the notch reading from browsers or other
apps. The app is Spotify-only again. Do not bring that work back, and do not
start the browser extension that was planned after it.

## What we plan to do next

Whatever in `docs/WANTED.md` I ask for.

## How I want you to work

These are not suggestions; they are what the last sessions cost to learn, and
they are all in the docs with the incident that produced them.

- **This is my personal machine and the app is running on it.** Testing
  against real Spotify changes my playback: record `player position` first and
  restore it after. A leaked preview window cannot be closed by me — run
  `./tools/sweep.sh` after anything that launches one, and never put a launch
  inside `$(...)`, which waits for it.
- **Verify by measuring, not by reasoning.** Several times in this project the
  *instrument* was the broken thing rather than the code: a mutation harness
  grepping the wrong line, hygiene checks that could only print "fine", a
  probe measuring the wrong window. If a check and the app disagree, suspect the check first.
- **Break a new check before trusting it.** Every rule that matters here is a
  pure function with a test, and the test gets mutation-tested — change the
  logic on purpose and confirm the test goes red.
- **Say what you have and have not verified.** If you cannot see something,
  say so and ask me for a photo. Do not describe an inference as an
  observation.
- **`./tools/verify.sh` must be green before you claim anything is done.**
- Write the trap or the bug down in `docs/` in the same commit as the fix.

Ask me before doing anything that changes my machine's state beyond the
repo — permissions, launch agents, or my playback.

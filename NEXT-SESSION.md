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
   rules that break a new notch app" (six of them) and "What has never been
   checked".
2. `docs/TRAPS.md` — 42 entries, classes of mistake with the fix. Read before
   debugging anything.
3. `docs/BUGS.md` — 16 specific defects and what each cost.
4. `docs/DECISIONS.md` — 39 entries, why things are the way they are. Do not
   re-open a decision without reading its entry first.
5. `docs/WANTED.md` — what we deliberately have not built.
6. `README.md` — the commands.
7. `~/.claude/plans/i-want-to-build-parsed-cascade.md` — the current plan,
   covering milestones 9 and 10.

Then skim the code: `Sources/SpotifyNotchCore/Data/` (Spotify bridge, audio
source detection, the tap, the FFT) and `Sources/SpotifyNotchCore/Views/`.

When you are done, tell me in a few sentences what the app does, what the
open bug is, and what you think the next step is. **Do not start coding until
I answer.**

## Where we left off

Everything through **milestone 9** is committed and shipped. The last commit
is `7695896`. The working tree is clean and `./tools/verify.sh` is green
except for one line about `matchnotch` — that is my other notch app being
down, it is not yours to fix, and I will restart it myself.

Milestone 9 made the notch follow **any** app's audio, not just Spotify's: a
YouTube video gets the browser's icon, its name, a live waveform of its
audio, and media-key transport. Spotify still gets the full panel with
scrubbing.

**There is one open bug, reported by me and not yet investigated.** This is
the first thing to work on:

> If I play a YouTube video and then go back to Spotify, the waveform for
> Spotify is wrong — it is "making something up" rather than following the
> music — and it stays wrong for roughly a minute before correcting itself.

Context that matters: a wrong-but-moving waveform is the *synthetic*
generator, which the app falls back to when the tap delivers nothing. So the
likely shape of this is the tap still pointed at the browser (silent, stream
still open) while the peek has already switched to Spotify. A closely related
bug was fixed one commit earlier (`61f4c3a`, `docs/BUGS.md` #16), so read
that entry first — this may be the same root cause with a second path that
fix did not cover.

Do not guess at it. `--sources` and `--bands` will show you what the app
thinks is happening, and `docs/TRAPS.md` #42 explains why "is this app
producing output" is not the question it looks like.

## What we plan to do next

1. **Fix the bug above.**
2. **Milestone 10, a browser extension.** The notch can follow a video but can
   only name the app — "Aside", not the video's title — because macOS gated
   the API that would give a title and no browser exposes which tab is
   audible. An extension knows both. Through it the panel could have what
   Spotify has: the title, a real progress bar, play/pause, and skip ±10s
   landing on the exact tab instead of wherever a media key happens to go.
   The design, and why an extension rather than the global Apple-Events
   JavaScript switch, is in the plan file and in `docs/WANTED.md`.
3. Whatever else in `docs/WANTED.md` I ask for.

## How I want you to work

These are not suggestions; they are what the last sessions cost to learn, and
they are all in the docs with the incident that produced them.

- **This is my personal machine and the app is running on it.** Testing
  against real Spotify changes my playback: record `player position` first and
  restore it after. A leaked preview window cannot be closed by me — run
  `./tools/sweep.sh` after anything that launches one, and never put a launch
  inside `$(...)`, which waits for it.
- **Verify by measuring, not by reasoning.** Seven times in this project the
  *instrument* was the broken thing rather than the code: a check that
  reported 19/19 clean while three states went uncaptured, two diagnostics
  reporting on subscriptions they had dropped, a probe measuring the wrong
  window. If a check and the app disagree, suspect the check first.
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

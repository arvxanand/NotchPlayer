<div align="center">

<img src="assets/logo.png" alt="NotchPlayer" width="120">

# NotchPlayer

**Spotify now-playing, in the MacBook notch.**

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/github/license/arvxanand/NotchPlayer)](LICENSE)
[![Release](https://img.shields.io/github/v/release/arvxanand/NotchPlayer?include_prereleases&sort=semver)](https://github.com/arvxanand/NotchPlayer/releases)
[![Downloads](https://img.shields.io/github/downloads/arvxanand/NotchPlayer/total)](https://github.com/arvxanand/NotchPlayer/releases)

</div>

<div align="center">

<img src="assets/demo/hero.gif" alt="NotchPlayer expanding out of the MacBook notch" width="800">

</div>

---

Collapsed, while music plays: the album cover and a live waveform — a real FFT
of Spotify's own audio — either side of the camera housing. Hover the cutout
and it expands into a panel with the cover, the track, a progress bar you can
drag to seek, and the transport row. Idle, it draws nothing and the notch looks
like a notch.

No login and no Spotify developer account. The only network calls are the
album cover, Spotify's public page for a song when you click its title or
artist, and a daily check of this repo's releases for a new version, which you
can turn off. Swift 6 / SwiftUI + AppKit, zero third-party dependencies.

## Features

<table>
<tr>
<td width="50%">

<img src="assets/demo/media.gif" alt="Album cover and live waveform beside the notch" width="400">

</td>
<td width="50%">

### Now playing, at a glance

The cover on one side of the camera housing, a live waveform on the other.
The waveform is a real FFT of Spotify's output through a Core Audio process
tap — 14 bars, computed in memory, never stored and never sent anywhere.

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/transport.gif" alt="Transport row with seek, shuffle and repeat" width="400">

</td>
<td width="50%">

### Full transport

Play/pause, previous, next, and a progress bar you can click or drag to seek —
the target is the 30pt band around the line, not the line itself. Shuffle and
repeat sit in the same row; repeat cycles off → all → one, and NotchPlayer
loops the song itself for "one".

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/save.gif" alt="The plus button saving the current song" width="400">

</td>
<td width="50%">

### Save the song

The **+** at the end of the title row. By default it opens the song in Spotify
so you can add it there. Turn on **Save with Spotify's +** and it opens
Spotify's playlist list for you. Nothing is added until you pick a playlist.
A song you haven't saved gets Spotify's **Add to playlist** menu (Liked
Songs is one item above it); a saved one gets Spotify's picker.

</td>
</tr>
<tr>
<td width="50%">

<img src="assets/demo/settings.gif" alt="The settings panel" width="400">

</td>
<td width="50%">

### Stays out of the way

A waveform glyph in the menu bar is the only other control: what's playing,
**Hide from the Notch** (stands the app fully down — no panel, no hover
polling, no audio tap), and Quit. The gear opens settings: launch at login,
cover colour on the progress bar, and the + behaviour.

</td>
</tr>
</table>

## Install

You need:

- a MacBook with a notch (every one of them is Apple Silicon)
- macOS 15 Sequoia or later
- the Spotify desktop app, signed in

**Does my Mac have a notch?** If the camera sits in a black cutout that dips
into the top of the screen, yes. If it sits in the frame above the screen, no.

| Has a notch | No notch |
|---|---|
| MacBook Pro 14" and 16" (late 2021 and newer) | MacBook Pro 13" (every one, including M1 and M2) |
| MacBook Air 13" with M2 or newer | MacBook Air with M1, and older |
| MacBook Air 15" (all of them) | Intel MacBooks (NotchPlayer won't open) |
| | iMac, Mac mini, Mac Studio, Mac Pro |

Not sure which you have? Apple menu → **About This Mac** shows the model and
size. On a Mac without a notch, NotchPlayer draws nothing, and its menu bar
item says "This Mac has no notch".

### 1. Download it

**[Download NotchPlayer](https://github.com/arvxanand/NotchPlayer/releases/latest/download/NotchPlayer.dmg)**,
open the file, and drag **NotchPlayer** onto the **Applications** folder next to it.

<img src="assets/install/0-drag.png" alt="The NotchPlayer disk window: NotchPlayer next to an Applications folder" width="480">

### 2. Open it the first time

macOS warns you the first time you open NotchPlayer. That's expected. Apple
only vouches for apps whose developers pay for an Apple Developer account,
and this is a free, open-source project without one. You do this once per
download.

1. Open **NotchPlayer** from your Applications folder. macOS says it couldn't
   verify it. Click **Done** (not Move to Trash).

   <img src="assets/install/1-blocked.png" alt="&quot;NotchPlayer&quot; Not Opened, with Done and Move to Trash" width="260">

2. Open **System Settings** → **Privacy & Security**, scroll down to
   **Security**, and click **Open Anyway** next to "NotchPlayer was blocked".

   <img src="assets/install/2-open-anyway.png" alt="Privacy &amp; Security: &quot;NotchPlayer&quot; was blocked to protect your Mac, with an Open Anyway button" width="480">

3. Click **Open Anyway** again, then enter your password or use Touch ID.

   <img src="assets/install/3-confirm.png" alt="Open &quot;NotchPlayer&quot;?, with Move to Trash, Open Anyway and Done" width="244">

Right-clicking the app and choosing Open doesn't get past the warning on
macOS 15, so use the steps above.

#### If Open Anyway doesn't show up

1. **Try to open NotchPlayer again** from your Applications folder, and click
   **Done** when the warning appears. The Open Anyway button only shows up
   right after macOS blocks the app, and disappears again after about an hour.
2. **Go back to System Settings → Privacy & Security** and scroll all the way
   down to **Security**. If System Settings was already open, quit it first
   (**System Settings** menu → **Quit**) and open it again so it shows the
   latest.
3. **Still no button, or it asks for an administrator password you don't
   have?** Open the **Terminal** app (search for "Terminal" with Spotlight),
   paste this line, and press Return:

   ```bash
   xattr -dr com.apple.quarantine /Applications/NotchPlayer.app
   ```

   It prints nothing when it works. Now open NotchPlayer again. There's no
   warning this time.

### 3. Allow what it asks for

| Permission | Why | When |
|---|---|---|
| **Automation** | read the track and send play/pause/skip to Spotify | first launch |
| **Audio Recording** | the waveform — Spotify's output only, analysed in memory | first launch |
| **Accessibility** | optional, only for opening Spotify's playlist list from the **+** | when you enable it |

Click **Allow** for both on first launch. Then turn on **Launch at Login**
from the menu bar item (the waveform) → the gear.

#### What "Audio Recording" actually records

macOS asks for "System Audio Recording" because that's the name Apple uses
for the permission. Here's what NotchPlayer actually does with it:

- **It only hears Spotify.** It listens to Spotify's audio output, the music
  you're already hearing. It never uses the microphone, and it doesn't hear
  other apps, calls, videos or anything else on your Mac.
- **It only listens while Spotify is playing.** It stops when you pause,
  when Spotify quits, and when you choose **Hide from the Notch**.
- **Nothing is saved.** The audio passes through a buffer in memory that
  holds about a tenth of a second and is constantly written over. The app
  turns each slice into 14 bar heights for the waveform and throws the
  sound away. No audio ever goes to a file.
- **Nothing is sent anywhere.** The app has no account, no analytics and no
  server. Its only network requests are the album cover, Spotify's public
  page for a song when you click its title or artist, and a daily check of
  this repo's GitHub releases for a newer NotchPlayer. That check sends
  nothing about you or your music, and **Check for updates** behind the gear
  turns it off.
- **You can check.** The code that listens is
  [`AudioTap.swift`](Sources/NotchPlayerCore/Data/AudioTap.swift), and the
  permission can be turned off at any time in **System Settings → Privacy &
  Security → Screen & System Audio Recording**. Everything else keeps
  working; the bars just switch to a made-up animation.

#### If you clicked Don't Allow, or nothing shows up

You can turn each permission on later in **System Settings → Privacy &
Security**. Quit NotchPlayer (menu bar item → Quit) and open it again
afterwards.

- **The notch says "Can't reach Spotify"**, or the menu bar item says
  "Cannot read Spotify". That's **Automation**: go to **Privacy & Security →
  Automation**, click **NotchPlayer**, and turn on **Spotify**.
- **The cover shows, but the bars don't follow the music.** That's **Audio
  Recording**: go to **Privacy & Security → Screen & System Audio
  Recording**, scroll down to **System Audio Recording Only**, and turn on
  **NotchPlayer**.

  <img src="assets/install/4-audio.png" alt="System Audio Recording Only, with NotchPlayer switched on" width="480">

- **NotchPlayer isn't in the list at all**, so there's nothing to switch on.
  Open **Terminal**, paste this line, press Return, and open NotchPlayer
  again. It asks for everything again, and this time click **Allow**:

  ```bash
  tccutil reset All io.github.arvxanand.notchplayer
  ```

### Or install with Homebrew

If you already use [Homebrew](https://brew.sh), this puts NotchPlayer in
Applications with no warning to clear. You still allow the permissions:

```bash
brew install --cask arvxanand/notchplayer/notchplayer
```

### Updating

**From v0.3 on, NotchPlayer updates itself.** When a new version is out, the
menu bar icon gets a small dot and its menu says **Update to v0.x** in blue.
Click it: NotchPlayer swaps in the new version and restarts in a second or
two, and keeps its permissions. It checks once a day; **Check for updates**
behind the gear turns that off.

- **Coming from v0.2**, update the old way one last time: download the new
  version, drag it into Applications (choose **Replace**), clear the warning,
  and allow the permissions again. v0.2 can't update itself, and v0.3 is
  signed differently, so macOS asks once more.
- **If NotchPlayer can't replace itself** (you aren't an admin, or it's
  running from the dmg), the row opens the download page instead and you
  update the old way.
- **Installed with Homebrew?** The row stays hidden; run
  `brew upgrade --cask notchplayer`.

### Uninstalling

1. Turn off **Launch at Login** (menu bar item → the gear).
2. Quit NotchPlayer (menu bar item → Quit).
3. Drag NotchPlayer from Applications to the Trash, or run
   `brew uninstall --cask notchplayer`.

That leaves its settings, cached album covers and log behind. To remove those
too, use `brew uninstall --zap --cask notchplayer` instead, or delete these
yourself (in Finder, **Go → Go to Folder…** and paste each path):

- `~/Library/Preferences/io.github.arvxanand.notchplayer.plist`
- `~/Library/Caches/NotchPlayer`
- `~/Library/Caches/io.github.arvxanand.notchplayer`
- `~/Library/HTTPStorages/io.github.arvxanand.notchplayer`
- `~/Library/Logs/NotchPlayer.log`

## Using it

Hover the notch to open the panel; move the pointer away and it closes. Click
the title, artist or cover to open that thing in Spotify — the title opens the
album with the song highlighted rather than restarting the track.

The **+** needs a word of explanation. Spotify's AppleScript dictionary exposes
a `starred` property that does nothing, so there is no scriptable way to like a
song. NotchPlayer instead presses Spotify's real + through the Accessibility
API — the same channel VoiceOver uses. It's off by default, it's your own
click being relayed, and it brings Spotify to the front. If anything is missing
— permission not granted, or a Spotify update moved the button — the + quietly
falls back to opening the song. Local files and podcasts get no +.

## Found a bug, or have an idea?

[**Open an issue**](https://github.com/arvxanand/NotchPlayer/issues/new/choose)
and pick **Report a bug** or **Suggest an idea**. The bug form asks for your
Mac model and macOS version, and if you can, a phone photo of the notch and
NotchPlayer's log file. That's usually enough to find the problem. You need a
free GitHub account, and you'll be told when it's fixed.

## Building it yourself

Want to build NotchPlayer from source, or help out? See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GPL-3.0](LICENSE). You can use, modify and redistribute this, including
commercially — but if you distribute a modified version, its source has to stay
open under the same license.

NotchPlayer is not affiliated with, endorsed by, or connected to Spotify AB. It
controls the Spotify desktop app through macOS's own automation interfaces and
needs a running, signed-in Spotify client; it does not stream, download or
redistribute any audio.

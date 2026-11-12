<p align="center">
  <img src="docs/icon.png" width="128" alt="SleepGuard icon">
</p>

<h1 align="center">SleepGuard</h1>

<p align="center">
  Keep your Mac awake, <b>lid closed too</b>, for exactly as long as you choose.<br>
  Every block ends on its own. Never forever.
</p>

<p align="center">
  <img src="docs/window-light.png" width="330" alt="SleepGuard window, light mode">
  &nbsp;&nbsp;
  <img src="docs/window-dark.png" width="330" alt="SleepGuard window, dark mode">
</p>

---

## Why

Apps like `caffeinate` stop a Mac from *idle* sleeping, but closing the lid still puts it to sleep.
The only switch that keeps a MacBook awake with the lid closed is:

```bash
sudo pmset -a disablesleep 1
```

That setting stays on until you turn it off. Forget, and your Mac runs in your bag
until the battery is empty and it's hot.

SleepGuard wraps that switch in **timed blocks that always end**: when the timer runs out,
when the battery gets low, when you unplug (optional), when you press Stop, or when you quit the app.

## Features

- **Timed blocks:** 30 min, 1 h, 2 h, 4 h, or any custom time up to 24 h (`45`, `1:30`, `2h`).
  Extend a running block with +30m / +1h.
- **Works with the lid closed.** When a block ends with the lid closed, the Mac goes to sleep straight away
  (unless it's docked to an external display).
- **Battery cutoff:** ends the block at 10–50% battery (20% by default), and won't start one below it.
- **Stop when unplugged** (optional): ends the block when the charger is disconnected.
- **Menu bar + window:** a menu bar icon with a live countdown, and a window with a live countdown ring,
  system readouts and settings. Follows light and dark mode.
- **Catches forgotten blocks:** if sleep was disabled some other way (for example a manual `sudo pmset`),
  SleepGuard turns it back on as soon as you close the lid.
- **Fail-safe:** if SleepGuard crashes or is force-quit, a small background job turns sleep back on within a minute.
- **Password once, ever:** a one-time setup lets it switch sleep on and off without asking again.
- No network access, no analytics, no dependencies. About 1,000 lines of Swift you can read.

## Menu bar

| Icon | Meaning |
|---|---|
| Crossed 💤 + time left | SleepGuard is keeping the Mac awake |
| Faded 💤 | Sleep allowed, as normal |
| Crossed 💤 + orange `!` | Sleep is disabled by something else. It's turned back on when you close the lid |

You can switch the icon to 😴 in Settings.

## Requirements

macOS 14 Sonoma or later, on Apple silicon or Intel.

## Install

### Option 1: Download (easiest)

1. **[Download SleepGuard.zip](https://github.com/praveenkumarp98/SleepGuard/releases/latest/download/SleepGuard.zip)**
   (from the latest [release](https://github.com/praveenkumarp98/SleepGuard/releases/latest)).
2. Open the zip (double-click) and drag **SleepGuard** into your **Applications** folder.
3. Open SleepGuard. The first time, macOS blocks it, because it isn't notarized by Apple
   (that needs a paid developer account). To allow it, once:
   - **macOS 15 and later:** in the *"SleepGuard" Not Opened* message, click **Done**. Then open
     **System Settings → Privacy & Security**, scroll down to *"SleepGuard" was blocked…*,
     click **Open Anyway**, and confirm.
   - **macOS 14:** right-click SleepGuard in Applications, choose **Open**, then **Open** again.

   If you'd rather check the code first, build it yourself with Option 2.

### Option 2: Build from source

Needs Apple's Command Line Tools (a one-time download). If you've never installed them, run
`xcode-select --install` first (if you have Xcode, you're set). Then:

```bash
git clone https://github.com/praveenkumarp98/SleepGuard.git
cd SleepGuard
./install.sh
```

This builds the app on your Mac (about a minute), installs it to `~/Applications/SleepGuard.app` and opens it.
It needs no admin password, and macOS doesn't show the "not opened" warning for apps you build yourself.

### Then

1. **Look for 💤 in your menu bar.** The SleepGuard window also opens. macOS may show a
   *"Background Items Added"* notification: that's SleepGuard's *Open at login* setting and its fail-safe,
   which you can turn off in the app.
2. **One-time setup.** The first time you start a block (or click **Set Up…** in the window),
   SleepGuard explains what it needs and asks for your Mac password **once**. See
   [What the one-time setup does](#what-the-one-time-setup-does).

## Use

**Start a block.** Click 💤 in the menu bar and pick a duration, or open the window
(Spotlight → "SleepGuard", or **Open SleepGuard…** in the menu), choose a preset or type a time, and press **Start**.

**While it runs:**
- The menu bar shows the time left. The window shows a countdown ring and when sleep returns.
- You can add time (**+30m**, **+1h**) or **Stop** at any point.
- You can close the lid and the Mac stays awake.

**When the block ends:** sleep is turned back on. If the lid is closed, the Mac goes to sleep straight away.

**Settings** (in the window; the battery ones are also in the menu):

| Setting | Default | What it does |
|---|---|---|
| Stop at battery | 20% | Ends the block when the battery drops to this level (on battery power) |
| Stop when charger is unplugged | Off | Ends the block when you unplug |
| Open at login | On | Starts SleepGuard when you log in |
| Menu bar icon | 💤 | 💤 or 😴 |

Closing the window keeps SleepGuard running in the menu bar. **Quit SleepGuard** (in the menu)
turns sleep back on before quitting.

## Update

- **Downloaded:** quit SleepGuard, download the latest zip, and replace the app in Applications.
- **Built from source:** `cd SleepGuard`, `git pull`, then `./install.sh`.

## Uninstall

Dragging the app to the Bin leaves its fail-safe job, login item and sudoers rule behind, so remove it like this.

**Downloaded:** paste this into Terminal. It asks for your password at the end, to remove the sudoers rule.

```bash
for a in /Applications ~/Applications; do [ -x "$a/SleepGuard.app/Contents/MacOS/SleepGuard" ] && "$a/SleepGuard.app/Contents/MacOS/SleepGuard" --unregister-login; done
pkill -x SleepGuard
launchctl bootout gui/$(id -u)/local.sleepguard.failsafe
rm -f ~/Library/LaunchAgents/local.sleepguard.failsafe.plist
rm -rf /Applications/SleepGuard.app ~/Applications/SleepGuard.app "$HOME/Library/Application Support/SleepGuard"
defaults delete local.sleepguard
sudo pmset -a disablesleep 0
sudo rm -f /etc/sudoers.d/sleepguard
```

**Built from source:**

```bash
cd SleepGuard
./uninstall.sh
```

Both turn sleep back on and remove the app, its login item, the fail-safe job, your settings and the sudoers rule.

## How it works

### What the one-time setup does

Changing `disablesleep` needs admin rights. Instead of asking for your password every time
(and getting stuck on a password prompt when a block ends while the lid is closed), the setup adds one file,
`/etc/sudoers.d/sleepguard`:

```
<your-username> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It allows exactly those two commands and nothing else. It's checked with `visudo` before it's installed.
The trade-off: any program running as you could also switch sleep off or on without a password.
Remove the file (or run `./uninstall.sh`) to undo it.

### What gets installed

| Path | What it is |
|---|---|
| `/Applications/SleepGuard.app` (download) or `~/Applications/SleepGuard.app` (source) | The app |
| `~/Library/LaunchAgents/local.sleepguard.failsafe.plist` | Runs the fail-safe every 60 s. The app creates it when it starts |
| `~/Library/Application Support/SleepGuard/failsafe.sh` | If sleep is disabled and SleepGuard isn't running, turns sleep back on |
| `/etc/sudoers.d/sleepguard` | The one-time setup rule (only after you approve it) |
| `~/Library/Preferences/local.sleepguard.plist` | Your settings |

### Under the hood

- It reads the lid state, `SleepDisabled` and the battery straight from macOS (IOKit), every 5 seconds.
- A block ends with `pmset -a disablesleep 0`. If the lid is closed and no external display is driving the Mac,
  `pmset sleepnow` follows.
- The code is plain AppKit + SwiftUI in two files, `main.swift` (logic, menu bar, fail-safe) and
  `Window.swift` (window), built with `swiftc` into one universal app (Apple silicon + Intel). There's no Xcode project.

## Troubleshooting

**I don't see 💤 in the menu bar.** On MacBooks with a notch, menu bar icons can hide behind it when the bar is full.
Quit a few other menu bar apps, or open the window from Spotlight ("SleepGuard").

**"passwordless: not set up" in the window.** Click **Set Up…** and enter your password. If it still says
*not set up*, check that `/etc/sudoers.d/sleepguard` exists.

**The Mac didn't go to sleep when the block ended.** If it's connected to an external display and power,
macOS keeps it awake with the lid closed (clamshell mode). That's normal. Sleep *is* back on.

**"SleepGuard" Not Opened / can't be opened.** See step 3 of [Option 1](#option-1-download-easiest).
Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/SleepGuard.app`, then open it again.

**`install.sh` says the Swift compiler isn't found.** Run `xcode-select --install`, then run `./install.sh` again.

**Check what SleepGuard sees** (use `~/Applications` if you built from source):

```bash
/Applications/SleepGuard.app/Contents/MacOS/SleepGuard --status
```

## Development

| File | Purpose |
|---|---|
| `main.swift` | Sleep/lid/battery logic, menu bar, one-time setup, fail-safe job |
| `Window.swift` | The SwiftUI window |
| `makeicon.swift` | Draws the app icon (edit colours/shapes here) |
| `build.sh` | Builds the universal `build/SleepGuard.app` |
| `install.sh` / `uninstall.sh` | Build + install / remove everything |
| `make-release.sh` | Builds `build/SleepGuard.zip` for a GitHub Release (keep the asset name `SleepGuard.zip`) |
| `docs/make-social-preview.swift` | Draws `docs/social-preview.png`, the image shown when the repo link is shared |

`SleepGuard --snapshot <dir>` renders the window (idle and running, light and dark) to PNGs.
It's how the screenshots in `docs/` were made.

### Branches and releases

- **`stable`** is the default branch: the latest released version, what you get from `git clone`.
- **`main`** is where work happens. It may be ahead of the latest release and not ready yet.

To release a new version:

```bash
git checkout main            # bump CFBundleShortVersionString in Info.plist, then commit
git checkout stable && git merge --ff-only main && git push
git tag -a v1.1.0 -m "SleepGuard 1.1.0" && git push origin v1.1.0
./make-release.sh            # only runs on stable; builds build/SleepGuard.zip
git checkout main
```

Then create a GitHub Release for the tag and attach `build/SleepGuard.zip` (keep that exact name).

Inspired by [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) (battery cutoff, fail-safe),
[Lungo](https://sindresorhus.com/lungo) (stop when unplugged) and Theine (duration menu).

## License

[MIT](LICENSE): free to use, change and share. Provided as is, without warranty.

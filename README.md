# SleepGuard

Keeps the Mac awake (lid closed too) via `pmset disablesleep`, for a time you choose, with a battery cutoff.
Every block ends: timer, battery limit, charger unplugged (optional), Stop, or Quit.

- **Menu bar:** crossed 💤 (or 😴) + time left while blocking; plain faded emoji when sleep is allowed;
  crossed emoji + orange `!` when sleep is blocked by something else (undone when you close the lid).
- **Window:** open the app (Spotlight, Dock, or "Open SleepGuard…" in the menu). Dock icon shows only while it's open.

## Password: once, ever
The first time you start a block, SleepGuard asks for your password once to install
`/etc/sudoers.d/sleepguard`, which allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`
without a password. After that it never asks again, and blocks end on their own with the lid closed.

## Files
- `~/Applications/SleepGuard.app` – the app
- `~/Library/LaunchAgents/local.sleepguard.failsafe.plist` + `~/Library/Application Support/SleepGuard/failsafe.sh`
  – every 60 s: if sleep is blocked and SleepGuard isn't running, turn sleep back on

## Rebuild
`./build.sh` – renders the app icon (`makeicon.swift`), compiles `main.swift` + `Window.swift`, signs ad hoc,
installs, reloads the fail-safe job, opens the app.
`SleepGuard --snapshot <dir>` renders the window (idle and a simulated block, light and dark) to PNGs.

## Uninstall
```bash
launchctl bootout gui/$(id -u)/local.sleepguard.failsafe; rm ~/Library/LaunchAgents/local.sleepguard.failsafe.plist
pkill -x SleepGuard; rm -rf ~/Applications/SleepGuard.app "$HOME/Library/Application Support/SleepGuard"
sudo rm /etc/sudoers.d/sleepguard
```

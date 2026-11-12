#!/bin/zsh
# Removes SleepGuard completely: turns sleep back on, removes the app, its login item,
# the fail-safe job, its settings, and (asking for your password) the sudoers rule.
set -u
APPS=("$HOME/Applications/SleepGuard.app" "/Applications/SleepGuard.app")   # built from source / downloaded
SUPPORT="$HOME/Library/Application Support/SleepGuard"
PLIST="$HOME/Library/LaunchAgents/local.sleepguard.failsafe.plist"

echo "Removing SleepGuard…"

# Remove from Login Items, then quit the app.
for APP in $APPS; do
  [[ -x "$APP/Contents/MacOS/SleepGuard" ]] && "$APP/Contents/MacOS/SleepGuard" --unregister-login
done
pkill -x SleepGuard 2>/dev/null

# Stop and remove the fail-safe job.
launchctl bootout "gui/$(id -u)/local.sleepguard.failsafe" 2>/dev/null
rm -f "$PLIST"
rm -rf "$SUPPORT" $APPS
defaults delete local.sleepguard 2>/dev/null

# Make sure sleep is back on, then remove the sudoers rule (both may ask for your password).
if /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | grep -q '"SleepDisabled" = Yes'; then
  echo "Sleep is currently blocked; turning it back on."
  sudo /usr/bin/pmset -a disablesleep 0
fi
if [[ -e /etc/sudoers.d/sleepguard ]]; then
  echo "Removing the sudoers rule /etc/sudoers.d/sleepguard (needs your password)."
  sudo rm -f /etc/sudoers.d/sleepguard
fi

echo "SleepGuard is uninstalled. You can delete this folder too."

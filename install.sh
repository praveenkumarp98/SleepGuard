#!/bin/zsh
# Builds SleepGuard from source, installs it to ~/Applications and opens it.
# The app sets up its fail-safe job itself on launch. Safe to re-run to update. Needs no admin rights.
set -euo pipefail
cd "${0:A:h}"

./build.sh
pkill -x SleepGuard 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/SleepGuard.app
cp -R build/SleepGuard.app ~/Applications/
sleep 1; open ~/Applications/SleepGuard.app
echo "Installed ~/Applications/SleepGuard.app. Look for 💤 in your menu bar."

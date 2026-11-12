#!/bin/zsh
# Builds SleepGuard.app from source, installs it to ~/Applications, installs the fail-safe
# launchd job, and opens the app. Safe to re-run to update. Needs no admin rights.
set -euo pipefail
cd "${0:A:h}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

APP="build/SleepGuard.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
echo "Building…"
# Target macOS 14 so the app also runs on Macs older than the one that built it.
swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$APP/Contents/MacOS/SleepGuard" main.swift Window.swift \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp README.md "$APP/Contents/Resources/"
swift makeicon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" 2>/dev/null

pkill -x SleepGuard 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/SleepGuard.app
cp -R "$APP" ~/Applications/

SUPPORT="$HOME/Library/Application Support/SleepGuard"
PLIST="$HOME/Library/LaunchAgents/local.sleepguard.failsafe.plist"
mkdir -p "$SUPPORT" ~/Library/LaunchAgents
install -m 755 failsafe.sh "$SUPPORT/failsafe.sh"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.sleepguard.failsafe</string>
    <key>ProgramArguments</key><array><string>$SUPPORT/failsafe.sh</string></array>
    <key>StartInterval</key><integer>60</integer>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/local.sleepguard.failsafe" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 1; open ~/Applications/SleepGuard.app
echo "Installed ~/Applications/SleepGuard.app and the fail-safe job. Look for 💤 in your menu bar."

#!/bin/zsh
# Builds build/SleepGuard.app: one universal binary (Apple silicon + Intel), macOS 14+, ad-hoc signed.
# Used by install.sh and make-release.sh.
set -euo pipefail
cd "${0:A:h}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

APP="build/SleepGuard.app"
SOURCES=(main.swift Window.swift)
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement)

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
echo "Building (Apple silicon + Intel)…"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos14.0" -o "build/obj/SleepGuard-$arch" $SOURCES $FRAMEWORKS
done
lipo -create -output "$APP/Contents/MacOS/SleepGuard" build/obj/SleepGuard-arm64 build/obj/SleepGuard-x86_64

cp Info.plist "$APP/Contents/Info.plist"
swift makeicon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" 2>/dev/null
echo "Built $APP"

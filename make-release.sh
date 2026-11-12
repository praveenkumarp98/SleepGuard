#!/bin/zsh
# Builds the universal app and packs it as build/SleepGuard.zip, ready to attach to a GitHub Release.
# The asset name stays "SleepGuard.zip" so the README's "latest" download link always works.
set -euo pipefail
cd "${0:A:h}"

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
# --noextattr/--norsrc: leave out this Mac's extended attributes (e.g. com.apple.provenance) and ._ files.
ditto -c -k --norsrc --noextattr --keepParent build/SleepGuard.app build/SleepGuard.zip
echo
echo "Release asset: build/SleepGuard.zip  (version $VERSION, $(du -h build/SleepGuard.zip | cut -f1))"
echo "SHA-256:       $(shasum -a 256 build/SleepGuard.zip | cut -d' ' -f1)"
echo "Tag it v$VERSION and attach build/SleepGuard.zip to the GitHub Release."

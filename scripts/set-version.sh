#!/usr/bin/env bash
# Stamp a marketing version and advance the monotonic build number in
# Info.plist. CFBundleShortVersionString is the user-facing semver;
# CFBundleVersion is the always-increasing build number.
set -euo pipefail

version="$1"
plist="${2:-Resources/Info.plist}"

build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((build + 1))" "$plist"

#!/usr/bin/env bash
# semantic-release `prepare` hook (@semantic-release/exec): stamp the resolved
# version into Info.plist, build the app bundle, and package it as the release
# asset that @semantic-release/github uploads.
set -euo pipefail

version="$1"

scripts/set-version.sh "$version"
make build
codesign --force --sign - --deep dist/Speedlet.app
ditto -c -k --keepParent dist/Speedlet.app "Speedlet-${version}.zip"

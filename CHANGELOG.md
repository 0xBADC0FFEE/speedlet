# Changelog

All notable changes to Speedlet are documented here. Releases from v1.3.1
onward are generated automatically by semantic-release from Conventional
Commits.

## [1.3.0](https://github.com/0xBADC0FFEE/speedlet/releases/tag/v1.3.0) (2026-07-18)

Initial public release: a macOS menu-bar internet speed test.

### Features

* opt-in auto-run of speed + geo on network change, with immediate restart and geo refresh once the link settles ([#16](https://github.com/0xBADC0FFEE/speedlet/pull/16))
* country flag centered in the status bar while a test runs ([#7](https://github.com/0xBADC0FFEE/speedlet/pull/7))
* IP / country row in the menu with a spinner and 5s geo request timeout ([#2](https://github.com/0xBADC0FFEE/speedlet/pull/2), [#4](https://github.com/0xBADC0FFEE/speedlet/pull/4))
* click-to-run/stop speed test from the menu bar with a live speedometer status item
* launch at login via `SMAppService`
* monospaced-digit status title and a rotating starting-state indicator

# Speedlet

Menu bar app that runs `/usr/bin/networkQuality` on click and streams live download Mbps into the menu bar title. Fire-and-forget — no history, no prefs window.

## Requirements

- Apple Silicon mac
- macOS 13+
- Swift 5.9+ toolchain (Xcode 15 CLT or full Xcode)

## Install

```
make install
```

Builds release, assembles `dist/Speedlet.app`, ad-hoc codesigns, copies to `/Applications`. No Apple Developer account, no notarization.

To launch: `open /Applications/Speedlet.app` or `make run`.

## Use

- **Left-click** the speedometer icon — starts the test. Title flips to live Mbps, updating every ~1s. Test runs ~10s then auto-reverts to icon.
- **Left-click again mid-test** — aborts, reverts within 500 ms.
- **Right-click** — menu:
  - `Run test` — same as left-click
  - `Launch at login` — toggle via `SMAppService.mainApp`
  - `About Speedlet v1.0` — version readout, disabled
  - `Quit` — exits and reaps any running `networkQuality`

## Uninstall

```
killall Speedlet
rm -rf /Applications/Speedlet.app
```

If `Launch at login` was ever enabled, also remove from **System Settings → General → Login Items & Extensions**.

## How it works

`networkQuality` only streams per-second capacity lines when its stdout is a tty. `SpeedTestRunner` gives it a pty slave via `openpty(3)` so lines come through live. A relaxed regex matches both progressive (`Downlink: capacity X Mbps`) and summary (`Downlink capacity: X Mbps`) variants.

## Makefile

| Target | What it does |
|---|---|
| `make build` | `swift build -c release --arch arm64` + assemble `dist/Speedlet.app` |
| `make install` | `build` + ad-hoc codesign + copy to `/Applications` |
| `make run` | `install` + `open` |
| `make clean` | remove `.build` and `dist` |

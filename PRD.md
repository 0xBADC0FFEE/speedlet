# Speedlet — PRD

**Date:** 2026-04-21
**Status:** Shipped — v1.0
**Target platform:** macOS 13+ (Ventura), Apple Silicon only
**Bundle ID:** `dev.vawerv.speedlet`
**App name:** Speedlet

## Summary

macOS menu bar utility. One click — starts a speed test via the system `networkQuality`, with live display of the current download speed right in the menu bar. Click again — stop. Right click — mini menu.

Fire-and-forget: no history is stored; after completion the result is dropped and the icon is restored.

## User stories

- **US-1.** As a user, I click the menu bar icon — a test starts; I see the speed number updating in real time.
- **US-2.** As a user, I click again during a test — the process stops and the icon returns.
- **US-3.** As a user, I right-click — I see Run test / Launch at login / About / Quit items.
- **US-4.** As a developer, I run `make install` in a freshly cloned repo — I get a working `.app` in `/Applications` without having to buy an Apple Developer account.

## Behavior

### States

| State | Menu bar |
|-----------|----------|
| Idle | SF Symbol `speedometer` |
| Running | Integer Mbps (streamed from stdout), monospaced digits — e.g. `"285"` |
| Done / Stopped / Error | Icon (fire-and-forget) |

### Interaction

| Event | Action |
|---------|----------|
| Left click (idle) | Launch `networkQuality` subprocess, parse stdout |
| Left click (running) | SIGTERM subprocess, revert to icon |
| Right click | NSMenu with items (see below) |
| Subprocess exit (success) | Revert to icon |
| Subprocess exit (non-zero) | Revert to icon (silent) |
| Subprocess emitted line `Downlink: capacity X Mbps` | Update menu bar title to `Int(round(X))` |

### Right-click menu

- **Run test** — duplicates left click
- **Launch at login** ☐ — toggle via `SMAppService.mainApp`
- **About Speedlet vX.Y** — disabled item with version
- ─────
- **Quit**

## Technical decisions

### Stack

- Swift 5.9+
- AppKit: `NSStatusItem` + `NSMenu` (not `MenuBarExtra` — need separate handlers for left/right click)
- `Foundation.Process` + `openpty(3)` pty slave for live stdout streaming (networkQuality only emits progressive lines when stdout is a tty)
- `ServiceManagement.SMAppService.mainApp` for autostart
- Min target: macOS 13.0
- Arch: `arm64` only

### Parsing networkQuality

Command: `/usr/bin/networkQuality` (no flags, human-readable format — it already streams incremental values during the run, when stdout is a tty).

Relaxed regex matches both progressive (`Downlink: capacity X Mbps`) and summary (`Downlink capacity: X Mbps`) variants.

### Info.plist

- `LSUIElement` = `YES` (hide from Dock and Cmd+Tab)
- `LSMinimumSystemVersion` = `13.0`
- `CFBundleIdentifier` = `dev.vawerv.speedlet`
- `CFBundleIconFile` = `AppIcon`

### Project structure

```
speedlet/
  Package.swift              # SPM executable
  Sources/
    Speedlet/
      SpeedletApp.swift      # @main, NSApplicationDelegate
      StatusItemController.swift
      SpeedTestRunner.swift  # wraps Process + pty, emits Mbps updates
      LaunchAtLogin.swift    # SMAppService wrapper
  Resources/
    Info.plist
    AppIcon.icns
  Makefile
  README.md
  PRD.md
```

### Build & install pipeline

`make install`:

1. `swift build -c release --arch arm64`
2. Assemble the bundle manually:
   ```
   Speedlet.app/
     Contents/
       Info.plist
       MacOS/Speedlet   (copied from .build/release/Speedlet)
       Resources/AppIcon.icns
   ```
3. `codesign --force --deep --sign - Speedlet.app` (ad-hoc, `-s -`)
4. `cp -R Speedlet.app /Applications/`
5. `open /Applications/Speedlet.app`

Gatekeeper does not trigger because the bundle is not tagged `com.apple.quarantine` (it was not downloaded from the internet).

### Makefile targets

- `make build` — assemble the bundle into `./dist/Speedlet.app`
- `make install` — build + codesign + cp to /Applications
- `make run` — install + open
- `make clean` — rm -rf .build dist

## Non-goals (explicitly out of scope)

- Auto-trigger on VPN / public IP change
- Test history
- Display of upload / RPM / RTT / interface
- Separate settings window or preferences pane
- Notifications
- GitHub Releases / CI / Homebrew cask
- Notarization (requires $99/year Apple Developer)
- Intel / x86_64
- Sparkle autoupdate

## Acceptance criteria

1. `make install` on a clean system (Apple Silicon, macOS 13+) → `/Applications/Speedlet.app` launches, `speedometer` icon visible in menu bar.
2. Left click — icon replaced with a live integer, updating every ~1–2s during the networkQuality run.
3. Second left click during a run — subprocess terminates within ≤500ms, icon returns.
4. Right click — shows 4 menu items, all functional.
5. "Launch at login" toggle survives a system restart.
6. No Apple Developer certificate prompt at any build step.
7. No dock icon, not in Cmd+Tab switcher.

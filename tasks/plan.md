# Implementation Plan — NetMeter

**Source:** [SPEC.md](../SPEC.md) | [PRD.md](../PRD.md)

## Overview

Ship a macOS menu bar app in 7 vertical-sliced tasks across 5 phases. Each phase leaves `/Applications/NetMeter.app` in a usable state. Acceptance = PRD §1–§7 on Apple Silicon + macOS 13.

## Architecture Decisions

- **AppKit + `NSStatusItem`**, not SwiftUI `MenuBarExtra` — need per-button left/right click handlers.
- **Single `@MainActor` `StatusItemController`** owns icon, menu, and runner lifecycle. No Combine, no observers.
- **Callback-based `SpeedTestRunner`** — `Process.readabilityHandler` is push-style; async-streams add no value.
- **Ad-hoc codesign at install time** inside Makefile. No Xcode project.
- **Install smoke-tests from `/Applications`**, not `.build/` — `SMAppService.mainApp` resolves bundle path at runtime.

## Dependency Graph

```
Package.swift ─┬─ NetMeterApp.swift ─── StatusItemController.swift ─┬─ SpeedTestRunner.swift
               │                                                     └─ LaunchAtLogin.swift
               └─ Info.plist ─── Makefile
```

## Phases and Tasks

### Phase 1 — Installable shell

#### Task 1 — SPM skeleton

Scaffold Package.swift + empty `@main` AppDelegate that launches and idles (no UI). Enables downstream UI work against a real compile target.

- Acceptance:
  - `swift build -c release --arch arm64` succeeds.
  - Running the raw binary keeps a process alive (no immediate exit, no crash).
- Verify:
  - `swift build -c release --arch arm64 && .build/release/NetMeter &` — PID stays alive; `kill` it.
- Depends on: —
- Files: `Package.swift`, `Sources/NetMeter/NetMeterApp.swift`.
- Scope: S.

#### Task 2 — Build + install pipeline

Makefile assembles a `.app` bundle, ad-hoc codesigns, copies to `/Applications`. Info.plist with `LSUIElement=YES`, min 13.0, bundle id `dev.vawerv.netmeter`, version `1.0`.

- Acceptance:
  - `make install` produces `/Applications/NetMeter.app` with correct layout (Contents/{Info.plist, MacOS/NetMeter, Resources/}).
  - `codesign -dv /Applications/NetMeter.app` shows an ad-hoc signature.
  - `open /Applications/NetMeter.app` launches it; no Dock icon, not in Cmd-Tab.
  - `make clean` wipes `.build/` and `dist/`.
- Verify:
  - `make clean && make install && open /Applications/NetMeter.app && pgrep NetMeter`.
- Depends on: Task 1.
- Files: `Makefile`, `Resources/Info.plist`.
- Scope: S.

### Checkpoint A — Foundation

- [ ] `make install` yields a runnable bundle.
- [ ] Process stays alive, no UI yet, no Dock icon.
- [ ] Review before proceeding.

### Phase 2 — Menu bar presence

#### Task 3 — Idle `NSStatusItem`

`StatusItemController` owns an `NSStatusItem` showing an `NSImage(systemSymbolName: "speedometer")` with `isTemplate = true`. Left-click action wired to a stub (prints or toggles a placeholder).

- Acceptance:
  - After `make run`, a `speedometer` icon appears in the menu bar.
  - Icon adapts to light/dark menu bar (template behavior).
  - Left-click fires a no-op handler without crashing.
- Verify:
  - `make run`; visually confirm icon in menu bar; click → app still alive.
- Depends on: Task 2.
- Files: `Sources/NetMeter/StatusItemController.swift`, `Sources/NetMeter/NetMeterApp.swift`.
- Scope: S.

### Phase 3 — Speed test vertical slice

#### Task 4 — `SpeedTestRunner` + click-to-run/stop

Left-click on idle launches `/usr/bin/networkQuality`; stdout parsed via regex `/Downlink:?\s*capacity:?\s+([\d.]+)\s+Mbps/`; menu bar title replaces the icon with `Int(round(Mbps))`. Second left-click sends `SIGTERM`, waits, restores icon. Subprocess exit (any reason) also restores icon.

- Acceptance:
  - Click idle → within ~5 s the icon is replaced by a live integer updating every 1–2 s.
  - Click running → subprocess terminates ≤500 ms, icon returns.
  - `networkQuality` exits naturally → icon returns.
  - Non-zero exit → icon returns silently (no alert).
- Verify:
  - Visual observation of ≥2 full-run cycles and ≥1 interrupted cycle.
  - `pgrep networkQuality` returns empty ≤500 ms after a click-to-stop.
- Depends on: Task 3.
- Files: `Sources/NetMeter/SpeedTestRunner.swift`, `Sources/NetMeter/StatusItemController.swift`.
- Scope: M.

### Checkpoint B — Core flow (PRD §1–§3)

- [ ] PRD §1 satisfied.
- [ ] PRD §2 satisfied.
- [ ] PRD §3 satisfied.
- [ ] Review before proceeding.

### Phase 4 — Right-click menu + autostart

#### Task 5 — Right-click `NSMenu` (no autostart yet)

Right-click on the status-bar button shows a 4-item menu: `Run test`, disabled `About NetMeter v1.0` (pulled from `CFBundleShortVersionString`), separator, `Quit`. `Launch at login` added as a placeholder item in Task 6. Left-click behavior unchanged.

- Acceptance:
  - Right-click shows the menu; left-click still triggers the runner.
  - `Run test` equivalent to left-click.
  - `About` item is disabled, shows current version.
  - `Quit` terminates the app (and any running subprocess).
- Verify:
  - Visual: right-click shows menu items, each invocation matches spec.
  - `pgrep networkQuality` empty after `Quit` mid-run.
- Depends on: Task 4.
- Files: `Sources/NetMeter/StatusItemController.swift`.
- Scope: S.

#### Task 6 — `LaunchAtLogin` via `SMAppService.mainApp`

Add `Launch at login` checkbox item between `Run test` and `About`. `LaunchAtLogin` wrapper calls `SMAppService.mainApp.register()` / `.unregister()` and reads `.status`. Checkmark refreshed in `menuWillOpen`.

- Acceptance:
  - Toggling the item flips `SMAppService.mainApp.status` between `.enabled` and `.notRegistered`.
  - State survives a logout/login cycle (PRD §5).
  - Checkmark reflects live state each menu open.
  - No crash when SMAppService call fails (e.g., unsigned bundle edge cases) — log + noop.
- Verify:
  - Toggle on, reboot or logout/login, confirm NetMeter auto-starts.
  - Toggle off, reboot, confirm it does not.
- Depends on: Task 5.
- Files: `Sources/NetMeter/LaunchAtLogin.swift`, `Sources/NetMeter/StatusItemController.swift`.
- Scope: S.

### Checkpoint C — Menu complete (PRD §4–§5)

- [ ] PRD §4 satisfied.
- [ ] PRD §5 satisfied.
- [ ] Review before proceeding.

### Phase 5 — Polish + final acceptance

#### Task 7 — Title polish + subprocess reaping

Menu bar title uses monospaced digits (no width jitter during updates). On `applicationWillTerminate`, terminate and wait for the subprocess so no `networkQuality` orphans survive. Confirm no Dock icon, no Cmd-Tab entry (PRD §6–§7).

- Acceptance:
  - Title updates visually stable (digits don't shuffle).
  - `Quit` or `killall NetMeter` leaves zero `networkQuality` processes within 1 s.
  - App does not appear in Cmd-Tab or Dock.
  - No Apple Developer prompts at any build step.
- Verify:
  - Run full PRD §Acceptance criteria §1–§7 top to bottom on a clean install.
- Depends on: Task 6.
- Files: `Sources/NetMeter/StatusItemController.swift`, `Sources/NetMeter/NetMeterApp.swift`.
- Scope: S.

### Checkpoint D — Ship

- [ ] PRD §1–§7 all green on Apple Silicon / macOS 13+.
- [ ] README with `make install` instructions.
- [ ] Commit, tag `v1.0`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `networkQuality` output wording shifts across macOS 13/14/15 | High | Relaxed regex covers both variants; log unmatched lines during Task 4. |
| `SMAppService.mainApp` requires bundle at stable path | High | Always smoke-test from `/Applications/NetMeter.app`, never from `.build/`. |
| Ad-hoc signature stripped or mangled by `cp -R` | Med | Codesign after copy (inside Makefile), then verify with `codesign -dv`. |
| `Pipe.readabilityHandler` buffers partial lines | Med | Accumulate + split on `\n` inside runner; don't regex raw chunks. |
| Right-click detection on `NSStatusItem.button` | Low | Standard pattern: single action, branch on `NSApp.currentEvent?.type`. |
| Orphan `networkQuality` on crash | Low | `applicationWillTerminate` + `Process.terminate()` + `waitUntilExit()` with 1 s cap. |

## Parallelization

Serial only. Single agent, single session per phase. No coordination needed.

## Open Questions

None — all spec gaps already resolved.

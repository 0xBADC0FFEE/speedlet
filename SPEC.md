# SPEC — NetMeter

**Derived from:** [PRD.md](PRD.md) (2026-04-21)
**Status:** Approved — gaps filled with simplest defaults.

## Objective

macOS menu bar app that runs `/usr/bin/networkQuality` on click and streams live download Mbps into the menu bar title. Fire-and-forget: no history, no UI beyond the menu bar.

**Users:** Single developer (owner) + anyone running `make install` on Apple Silicon mac. No distribution outside source-clone use.

**Success:** PRD acceptance criteria §1–§7 all pass on a clean Apple Silicon mac running macOS 13+.

## Tech Stack

- Swift 5.9+ (Xcode 15+ toolchain)
- AppKit (`NSStatusItem`, `NSMenu`)
- `Foundation.Process` + `Pipe.readabilityHandler`
- `ServiceManagement.SMAppService.mainApp`
- SPM executable target, `arm64` only, min target macOS 13.0
- Ad-hoc codesign (`-s -`), no notarization

## Commands

```
make build      # swift build -c release --arch arm64 + assemble dist/NetMeter.app
make install    # build + ad-hoc codesign + cp -R to /Applications
make run        # install + open /Applications/NetMeter.app
make clean      # rm -rf .build dist
```

No `make test` — manual acceptance only.

## Project Structure

```
netmeter/
  Package.swift                  # SPM executable, target NetMeter
  Sources/NetMeter/
    NetMeterApp.swift            # @main AppDelegate, LSUIElement app
    StatusItemController.swift   # NSStatusItem + NSMenu, click handling
    SpeedTestRunner.swift        # Process wrapper, stdout stream → Mbps updates
    LaunchAtLogin.swift          # SMAppService.mainApp wrapper
  Resources/Info.plist           # LSUIElement=YES, min 13.0, bundle id
  Makefile                       # build/install/run/clean
  PRD.md
  SPEC.md
  README.md
```

## Code Style

Swift stdlib conventions. Small files, one type per file. No external deps.

```swift
// SpeedTestRunner.swift
final class SpeedTestRunner {
    private var process: Process?
    private let onMbps: (Int) -> Void
    private let onExit: () -> Void

    private static let downlinkRegex = /Downlink:?\s*capacity:?\s+([\d.]+)\s+Mbps/

    init(onMbps: @escaping (Int) -> Void, onExit: @escaping () -> Void) {
        self.onMbps = onMbps
        self.onExit = onExit
    }

    func start() { /* Process launch, readabilityHandler parses lines */ }
    func stop()  { process?.terminate() }
}
```

Conventions:
- `final class` by default; `struct` for value types.
- Callbacks over Combine/async-await (stdout is push-style).
- No force unwraps outside `@main` init.
- UI mutations hop to `@MainActor` / `DispatchQueue.main`.

## Testing Strategy

None. Acceptance via PRD §Acceptance criteria manually on Apple Silicon hardware. Rationale: utility is a thin wrapper over a system binary; no business logic justifies unit tests.

Smoke check post-`make install`:
1. Click icon → number appears within ~5s.
2. Click again → icon returns within 500ms.
3. Right-click → 4 items, all functional.

## Boundaries

**Always**
- Target arm64 + macOS 13 only.
- Ad-hoc codesign before copy to `/Applications`.
- Revert to icon on any subprocess exit (success, non-zero, termination).
- Hop to main thread before touching `NSStatusItem`.

**Ask first**
- Adding any SPM dependency.
- Changing bundle identifier.
- Changing minimum macOS version.
- Any scope not in PRD (notifications, history, upload, RPM, prefs window…).

**Never**
- Ship an Intel slice.
- Notarize or require an Apple Developer account.
- Store test results or telemetry.
- Add a dock icon / Cmd-Tab entry (keep `LSUIElement=YES`).
- Write to disk outside `~/Library/Application Support` (we won't need to).

## Resolutions (gaps not in PRD)

1. **Regex** — single relaxed pattern matches both wording variants: `/Downlink:?\s*capacity:?\s+([\d.]+)\s+Mbps/`.
2. **Version** — hardcode `CFBundleShortVersionString = 1.0` in Info.plist; bump manually on release.
3. **Offline / hang** — no watchdog. User clicks again to abort. Matches PRD's fire-and-forget model.
4. **Idle icon** — `NSImage(systemSymbolName: "speedometer")` with `isTemplate = true` so it adapts to light/dark menu bar.
5. **Running label** — bare integer (`"285"`), per PRD example. Monospaced digits.
6. **SMAppService state** — refresh checkmark only when menu opens (`NSMenuDelegate.menuWillOpen`). No observers.

## Success Criteria

Mirror PRD §Acceptance criteria §1–§7 verbatim. Also:
- Subprocess is fully reaped — no orphan `networkQuality` after quit.
- Menu bar title uses monospaced digits (no width jitter).
- "Launch at login" checkmark reflects live `SMAppService.status` when menu opens.

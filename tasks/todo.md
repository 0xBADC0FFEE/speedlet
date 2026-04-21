# Todo — NetMeter

Detail for each task: [tasks/plan.md](plan.md). Spec: [SPEC.md](../SPEC.md).

## Phase 1 — Installable shell
- [x] **Task 1** — SPM skeleton (`Package.swift`, empty `@main` AppDelegate). Verify: `swift build -c release --arch arm64` succeeds; binary stays alive.
- [x] **Task 2** — Makefile + Info.plist; `make install` copies signed `.app` to `/Applications`. Verify: `codesign -dv` shows ad-hoc sig; no Dock icon.

### Checkpoint A
- [ ] Foundation review (installable shell works).

## Phase 2 — Menu bar presence
- [x] **Task 3** — `StatusItemController` with idle `speedometer` template icon; left-click stub. Verify: icon visible after `make run`; click no-op doesn't crash.

## Phase 3 — Speed test vertical slice
- [ ] **Task 4** — `SpeedTestRunner` + click-to-start/stop; live Mbps in title; auto-revert on exit. Verify: PRD §1–§3; no orphan subprocess after stop.

### Checkpoint B
- [ ] PRD §1, §2, §3 pass.

## Phase 4 — Menu + autostart
- [ ] **Task 5** — Right-click `NSMenu`: `Run test`, disabled `About v1.0`, separator, `Quit`. Verify: all 3 items functional; `Quit` kills subprocess.
- [ ] **Task 6** — `LaunchAtLogin` via `SMAppService.mainApp`; checkmark refresh on `menuWillOpen`. Verify: PRD §4, §5 (survives reboot).

### Checkpoint C
- [ ] PRD §4, §5 pass.

## Phase 5 — Polish + ship
- [ ] **Task 7** — Monospaced digits; subprocess reaping in `applicationWillTerminate`; PRD §6, §7 verified. Verify: full PRD §Acceptance §1–§7.

### Checkpoint D — Ship
- [ ] All 7 acceptance criteria green.
- [ ] README written.
- [ ] Tag `v1.0`.

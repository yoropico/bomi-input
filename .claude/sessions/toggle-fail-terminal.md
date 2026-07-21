## Session state (devmode)
- Updated: 2026-07-22
- Goal: Han/Eng toggle wedges in Terminal — Right-Cmd goes dead until the app is
  refocused; "first letter eaten" on a fast han→eng switch. DONE.
- Branch: toggle-fail-terminal — merged --no-ff into main (d8cd3bc); branch and
  desk removed.
- Status: SHIPPED. Gate 32/32 on main. The fixed build has been the installed IME
  at ~/Library/Input Methods/Bomi.app since 2026-07-15 and is in daily use.

- Mental model:
  - The wedge was IMK event routing going stale, not a ToggleGate/debounce bug.
    In the wedged state `keyDown` keeps arriving and `flagsChanged` never does again.
  - Cause: `TISSelectInputSource` swaps the active source behind IMK's back. Fix:
    ask IMK itself via `selectMode` (`ModeSwitcher.selectViaIMK`), deferred off the
    flagsChanged callback.
  - `mode` is set optimistically to the target because `selectMode` is async; TIS
    is still the truth, re-read in `activateServer` / reported by `setValue`.

- Decisions (the WHY is in .claude/worklog.md):
  - Never return `false` from flagsChanged — tried, and every FIRE then lost its
    key-up (vs ~1 in 12 before). Both switch branches consume, deliberately.
  - `selectMode` is NOT the "~1 second slow path" the spec claimed: measured
    min 1ms / p50 34ms / p95 42ms / max 67ms over 2814 toggles. That unmeasured
    inherited sentence is what kept the correct fix off the table for weeks.
  - `DebugLog` is permanent in-tree, silent unless /tmp/bomi-debug.on exists (read
    once at startup). os_log shows nothing for this process.
  - The spec was corrected in place with a "do not reinstate" note, rather than
    left describing the design that caused the bug.

- Evidence (145h of daily use, installed build == merged tree):
  - 2814 FIREs, 0 wedges, 0 TIS fallbacks, 0 failed landings, 246 duplicates
    suppressed. 2744 first-keystrokes-after-toggle, 0 in the pre-toggle mode.

- Files: Sources/Bomi/{BomiInputController,ModeSwitcher,DebugLog}.swift,
  docs/superpowers/specs/2026-07-14-bomi-han-eng-mode-switching-design.md

- Next: nothing planned. Re-enable logging only if a problem reappears:
  `touch /tmp/bomi-debug.on && killall Bomi`.
- Open: none.

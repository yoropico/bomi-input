## Session state (devmode)
- Updated: 2026-07-22 (resumed on the desk)
- Goal: Han/Eng toggle wedges in Terminal — Right-Cmd goes dead until the app is
  refocused; "first letter eaten" on a fast han→eng switch. FIXED and verified.
- Branch: toggle-fail-terminal (desk: worktrees/bomi-input-toggle-fail-terminal)
- Status: work is COMPLETE and uncommitted. Gate 32/32. Awaiting commit + land.

- Mental model:
  - The wedge is IMK event-routing going stale, not a ToggleGate/debounce bug. In the
    wedged state `keyDown` keeps arriving and `flagsChanged` never does again.
  - Cause: `TISSelectInputSource` swaps the active source behind IMK's back. Fix: ask
    IMK itself via `selectMode` (`ModeSwitcher.selectViaIMK`), deferred off the callback.
  - `mode` is set optimistically to the target because `selectMode` is async; TIS is
    still the truth, re-read in `activateServer` / reported by `setValue`.

- Decisions (the WHY is in .claude/worklog.md):
  - Never return `false` from flagsChanged — tried, and every FIRE then lost its key-up.
  - `selectMode` is NOT the "~1 second slow path" it was believed to be: measured
    min 1ms / p50 34ms / p95 42ms / max 67ms over 2814 toggles.
  - `DebugLog` is permanent in-tree, silent unless /tmp/bomi-debug.on exists (read once
    at startup). os_log shows nothing for this process; a file is the only instrument.

- Evidence (145h of daily use, installed build == this tree):
  - 2814 FIREs, 0 wedges, 0 fallbacks, 0 failed landings, 246 duplicates suppressed.
  - 2744 first-keystrokes-after-toggle, 0 in the pre-toggle mode.

- Files: Sources/Bomi/{BomiInputController,ModeSwitcher,DebugLog}.swift (DebugLog is new)

- Next: commit the three source files + worklog, then land to main.
- Open: none.

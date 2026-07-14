## Session state (devmode)
- Updated: 2026-07-14 17:30
- Goal: Sebeolsik-final macOS IME — DONE, merged to main (5bc2c4e), gate 32/32
- Branch: sebeolsik-mvp (merged --no-ff, branch + worktree removed)
- Status: SHIPPED. Installed and in daily use at ~/Library/Input Methods/Bomi.app

- Mental model:
  - Three targets: BomiEngine (pure Hangul automaton, libhangul port) → BomiCore
    (pure app logic: KeyTranslator, ToggleGate, InputMode, Preferences) → Bomi
    (IMK controller, the only impure layer).
  - Han/Eng is NOT an internal boolean. Two input modes are declared
    (…bomi.korean / …bomi.roman); a Right-Cmd press switches the SYSTEM input
    source, which is what makes the menu-bar ㅂ/B icon update.
  - The active mode is read back from TIS, never inferred from IMK callbacks.

- Decisions (the WHY is in .claude/worklog.md — read it before touching the toggle):
  - Bundle id `com.bomi.inputmethod.bomi` — a bundle id ending in "inputmethod"
    is silently NOT registered by macOS. Never shorten it.
  - Toggle fires on PRESS + 80ms duplicate debounce + tracker reset on both fire
    and suppress paths. A release-based toggle wedges (the source switch eats the
    key-up).
  - IMK's setValue does not report roman→korean. TIS is the source of truth.
  - Royal TSX rewrites Right-Cmd → Right-Option before the IME sees it →
    per-app toggle-key substitution in Preferences.toggleKeyCode(forApp:).
  - Per-app language memory is macOS's job (LanguageMode was deleted).

- Gotchas:
  - NSLog/os_log shows NOTHING for this background IME process. To debug, write to
    a file (/tmp/bomi-debug.log). That instrumentation is what solved every real bug.
  - Changing bundle id / mode ids / InfoPlist.strings requires a full logout/login —
    TIS caches registration AND localized names.
  - Right Command is now a dedicated Han/Eng key; use LEFT Command for shortcuts.

- Files: Sources/{BomiEngine,BomiCore,Bomi}, Resources/Info.plist (+*.lproj),
  Scripts/{assemble-app,install}.sh, docs/superpowers/{specs,plans}/*

- Next (only if a problem shows up in daily use — nothing is planned):
  - Unverified: jamo loss when toggling mid-syllable; menu-bar icon actually
    flipping ㅂ↔B; inline composition in Electron apps; Royal TSX while an RDP
    session IS connected.
  - If inline composition breaks in some app, port Gureum's per-app marked-text
    policy (OSXCore/InlineComposition.swift: WebKit / Chromium / Terminal stacks).

- Open: none blocking.

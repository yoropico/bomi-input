# Bomi IME — Worklog

Append one line per decision (the WHY). Newest at bottom.

## 2026-07-14 — Brainstorming & design

- **IMK as base API**: only official macOS IME API, not deprecated on macOS 26; CGEventTap can't render preedit and breaks in secure fields → unusable for Hangul composition.
- **Pure-Swift automaton** (not libhangul embed): zero deps, license-free, Swift6/macOS26 native, full NFC control; libhangul kept only as reference + test oracle.
- **Sebeolsik-final (`3f`) first**: user's daily layout; separate cho/jung/jong keys → clean automaton, no 도깨비불 (jong never migrates to next cho).
- **In-IME han/eng toggle** (Gureum-style), default Right Command, per-app memory: consistent feel across apps.
- **Per-syllable immediate commit** (not eojeol-keep): matches Apple/Gureum feel, robust in hard apps (long preedit would break Terminal/Electron).
- **SwiftPM + assembly script** (not Xcode project): CLI/git-friendly, keeps Engine a clean pure module.
- **Automaton data** taken verbatim from libhangul `3f` keymap + `combination-default` (see spec Appendix A/B) — ingest, don't invent.
- **Research note**: parallel research workflow partially failed (sebeolsik finder hit StructuredOutput retry cap; two finders returned dummy). Recovered by fetching libhangul source directly for the authoritative mapping.
- **Spec approved**: `docs/superpowers/specs/2026-07-14-bomi-sebeolsik-ime-design.md`. Build order puts a minimal "does IMK load on macOS 26" spike first (highest risk), before the automaton.

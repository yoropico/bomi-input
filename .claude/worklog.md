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
- **Implementation plan written**: `docs/superpowers/plans/2026-07-14-bomi-sebeolsik-ime.md` — 11 tasks, TDD, full Swift code inline. Automaton is a verbatim port of libhangul `hangul_ic_process_jaso` (fetched from source, not invented). Concurrency approach fixed: `.defaultIsolation(MainActor.self)` on the app target; Engine target stays pure/non-isolated.

## 2026-07-14 — Task 1: IMK load spike

- **Builds clean** on Swift 6.3.3 / Xcode 26.6 / macOS 26.5.2 with `.defaultIsolation(MainActor.self)`, but `BomiInputController` needed extra concurrency bridging beyond the brief's snippet: `init()`, `init(server:delegate:client:)`, and `handle(_:client:)` all had to be marked `nonisolated` (they override `nonisolated` ObjC declarations), and `handle`'s body hops to `MainActor.assumeIsolated { }` to call `insertText`. Sending the non-`Sendable` `sender: Any!` into that closure additionally required a small `nonisolated`, `@unchecked Sendable` box type — plain `MainActor.assumeIsolated { }` alone wasn't enough to satisfy Swift 6's region-based "sending" check. Confirms spec §10.1 risk was real, and the escalation path the brief allowed (nonisolated override + assumeIsolated bridge) was sufficient without changing the tools-version or the overall isolation strategy.
- Also had to `mkdir -p Tests/BomiEngineTests` (empty) — `swift build` errors on the declared `BomiEngineTests` test target with "overlapping sources" if that directory doesn't exist yet; Task 2 will populate it.
- `swift build -c release`, `./Scripts/assemble-app.sh`, `./Scripts/install.sh` all succeed. `Bomi.app` is adhoc-codesigned, installs identically to `~/Library/Input Methods/Bomi.app`, and the standalone binary launches and stays alive (IMKServer registration doesn't crash) when run directly from the terminal.
- **Not yet verified** (needs interactive GUI/login session, handed to the human): adding Bomi in System Settings > Keyboard > Input Sources, switching to it, and typing in TextEdit to confirm `보미` commits on keypress.

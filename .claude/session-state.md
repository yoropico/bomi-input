## Session state (devmode)
- Updated: 2026-06-02 (auto-updater SHIPPED + right-Cmd/icon resolved)
- Goal: DONE & SHIPPED. History: notifications migration + han/eng fix (MERGED) -> fork
  README/CHANGELOG -> macOS cleanup & modernization (4 buckets, 1.15.0, tagged) -> GitHub-based
  auto-updater (PR #3 MERGED). All on-device verified. Nothing outstanding.
- Repo state:
  - Local `main` == origin/main == 0a718d5 ("Merge pull request #3 ... auto-updater"), PUSHED.
    Only `main` branch (feature branches cleanup/modernize-macos + github-auto-updater merged & deleted).
  - Auto-updater (PR #3): OSX/Updater.swift (download/verify codesign+team/admin-install/fallback),
    UpdateManager -> GitHub Releases API + semver isNewer + validate(statusCode:) fix, menu/notif wired,
    OSX/Gureum-personal.entitlements (non-sandbox personal build). e2e PASSED on device. Test release
    1.16.0 deleted after e2e.
  - Tags: 1.14.0 -> 30f944d, 1.15.0 -> 66c79d1 (1.16.0 was an e2e test tag, now deleted).
  - Tags pushed: 1.14.0 -> 30f944d (han/eng + notifications + fork docs), 1.15.0 -> 66c79d1 (cleanup).
    CHANGELOG compare links (1.13.2...1.14.0, 1.14.0...main) now resolve.
  - Key commits over upstream: 951d9f0 two fixes (PRs #1/#2), 30f944d fork README/CHANGELOG, bf53457
    spec, 376b5b6 remove iOS subsystem (-10k LOC), 844a77d plan, cd92e18 remove AnswersHelper, cb362ea
    remove Firebase Crashlytics (SPM now MASShortcut/Fuse/Alamofire/SwiftUp), b05f87d deploy target
    10.13->11.0 + flatten guards, 66c79d1 README/CHANGELOG 1.15.0 docs.
  - Build (signing-disabled Release) SUCCEEDED; 45 tests, only known testIPMDServerClientWrapper
    fails (unsigned, pre-existing). docs/superpowers/{specs,plans}/2026-06-01-macos-cleanup-*.
  - Working tree clean (only `.claude/` untracked).
- Installed build: /Library/Input Methods/Gureum.app = cleanup/modernize RELEASE build (code == b05f87d),
  now **Apple Development signed** (team G7J2LY4LP9, codesign VALID, chain to Apple Root CA), v1.15.0, 0
  Firebase symbols, no debug/key-logging notice. Launches clean (no amfi/profile/sandbox-deny). yoros
  re-grants Input Monitoring ONCE for the new signing identity; thereafter rebuilds (same cert) keep TCC.
- Mental model (for any follow-up):
  - App target OSX -> Gureum.app (org.youknowone.inputmethod.Gureum). Engine = OSXCore
    (GureumCore.framework). Each focused client gets its own IMKInputController -> InputReceiver
    -> GureumComposer; composer.inputMode (TIS id) and delegate (HangulComposer/RomanComposer)
    are kept in sync by the inputMode setter.
  - Han/Eng switching is macOS-driven here (enableCapslockToToggleInputMode=false, no Gureum
    shortcuts): CapsLock uses #918 TICapsLockLanguageSwitchCapable -> setValue drives the mode.
- The bug & fix (PR #2, now in main):
  - Root cause (confirmed via temporary GRMDIAG os_log diagnostics, since removed):
    (1) GureumComposer.init always started at lastRomanInputMode (qwerty); under rapid
    activate/deactivate churn a missed setValue left the composer stuck English while the
    input source still showed Korean. (2) init set delegate=romanComposer AFTER inputMode,
    overwriting the Hangul delegate -> "Korean mode types English".
  - Fix: Configuration.lastInputMode tracks last actual mode; init seeds from it; init sets the
    default delegate BEFORE inputMode so the setter's delegate wins.
- Gotchas (still true; do NOT re-debug):
  1. sudo has no TTY via Bash/`!`; install via `osascript ... with administrator privileges`.
  2. Build: `git fetch --tags` + override CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2
     (apple-generic casts CURRENT_PROJECT_VERSION to double; dotted git-describe breaks C).
     Generated OSX/Version.xcconfig -> keep out of diffs.
  3. Empty ${VERSION} makes Xcode DROP CFBundleVersion -> IME won't register; PlistBuddy-add 1.13.2 + re-sign.
  4. Re-sign ad-hoc with OSX/Gureum.entitlements (+ get-task-allow) for sandbox/IOHID.
     ENABLE_DEBUG_DYLIB=YES -> real code in Gureum.debug.dylib + GureumCore.framework.
  5. Reinstalling the ad-hoc IME DROPS it from Input Sources (re-add in System Settings each time),
     breaks Input Monitoring TCC (cdhash changes), and leaves Chromium/Edge with a stale IME
     connection (logout/login or restart the app to reconnect). A stable Apple Development/Developer
     ID signature would remove all of this churn.
  6. `log` is a zsh builtin here -> use `/usr/bin/log show ...`.
  7. NSLog("...\(x)") logs the value as <private>; use os_log("%{public}@", str) for public values.
  8. 1 pre-existing unrelated test fails unsigned: GureumObjCTests.testIPMDServerClientWrapper.
  9. Deployment target is now 11.0 (was 10.13); OSX/OSXCore have NO @available guards left,
     Preferences keeps its `OSX 13` guards. Firebase/AnswersHelper/iOS subsystem all removed.
 10. Subagent git hazard: a stray `git commit --amend` while HEAD sat on a docs commit destroyed
     it once (recovered by recommit). Tell impl subagents: ONE plain commit, no reset/amend/rebase,
     `git add` explicit paths only, restore OSX/Version.xcconfig if a build dirties it.
 11. STABLE SIGNING now available (personal use, free). Identity "Apple Development: yoropico@gmail.com
     (K83K59TGLX)", team G7J2LY4LP9, in login keychain; needed Apple WWDR G3 intermediate
     (AppleWWDRCAG3.cer from apple.com) imported to fix CSSMERR_TP_NOT_TRUSTED (only expired G1 was
     present). Build SIGNED with: `xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration
     Release -derivedDataPath build/DerivedData-signed CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2
     DEVELOPMENT_TEAM=G7J2LY4LP9 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"
     -allowProvisioningUpdates build` (first codesign needs login-keychain pw + Always Allow). Use THIS
     instead of ad-hoc going forward so Input Monitoring TCC persists across rebuilds. Cert expires
     2027-05-31. Project pbxproj still has upstream team 9384JEL3M9 / "Developer ID Application" (do not
     commit team changes; override on cmdline only).
- Auth: 1Password classic PAT "github-PAT(classic)" (user "claude") via `op item get ... --reveal`
  -> GH_TOKEN env. gh push/pr/merge only need repo scope (gh auth login wants read:org). op desktop
  integration on (biometric authorizes reads, no `op signin`).
- Next / open:
  - cleanup/modernize ALL DONE & SHIPPED: merged + pushed (origin/main == 66c79d1), on-device smoke
    PASSED, RELEASE installed + confirmed working on device, README/CHANGELOG (1.15.0) documented,
    tags 1.14.0/1.15.0 pushed. Nothing outstanding for this work.
  - DONE this session: removed dead Fabric/Answers (AnswersHelper), removed heavy Firebase, bumped
    deployment target to 11.0 + dropped @available guards, documented 1.15.0, cut release tags.
  - Still optional: propose SwiftIOKit + han/eng fixes upstream (gureum/gureum); get a stable
    Apple Development/Developer ID signature (kills the Input Sources / Input Monitoring rebuild
    churn); consider Sparkle.
  - MCP sync configured (.claude/devmode.json sessionProject=gureum). EXAM_API_KEY IS set in
    ~/.claude/settings.json env (+ ~/.zshrc), so PreCompact/SessionEnd hook AUTO-SAVE is ACTIVE
    (REST save verified 200). Manual MCP session_save no longer required (still fine as a checkpoint).

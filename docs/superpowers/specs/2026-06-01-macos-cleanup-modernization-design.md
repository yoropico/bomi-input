# macOS Cleanup & Modernization — Design

- Date: 2026-06-01
- Repo: yoropico/gureum (fork of gureum/gureum)
- Scope target: macOS targets only (OSXCore, OSX, OSXTests, Preferences, ScriptSupport, OSXTestApp)
- Status: approved (design), pending spec review

## Goal

Remove dead/abandoned code and modernize the macOS build of the Gureum input
method. Four independent cleanup buckets, all approved:

- **A.** Remove the dead analytics shim (`AnswersHelper`).
- **B.** Remove Firebase Crashlytics entirely.
- **C.** Delete the orphaned iOS source directories.
- **D.** Raise the deployment target to macOS 11.0 and drop all `@available`
  guards it makes unreachable.

## Context (verified, 2026-06-01)

- Active Xcode targets are all macOS: `OSXCore, OSX, OSXTests, Preferences,
  ScriptSupport, OSXTestApp`. There are **no iOS targets** in the project.
- `iOS/`, `iOSApp/`, `iOSShared/` (~1.1 MB) are referenced **0 times** in
  `Gureum.xcodeproj/project.pbxproj`. They still `import Fabric` / `Crashlytics`
  (an SDK Google sunset in 2020) and do not compile.
- `OSX/AnswersHelper.swift` is a complete no-op: every method body is commented
  out. A global `answers` instance, an hourly `logUptime` `Timer`, and ~12
  `answers.log*()` call sites (in `GureumAppDelegate.swift`, `GureumMenu.swift`)
  all do nothing.
- Firebase Crashlytics IS wired into the OSX target: SPM package
  `firebase-ios-sdk` (8.15.0), a `FirebaseCrashlytics` framework link, a "Run
  Crashlytics" build phase, `OSX/GoogleService-Info.plist` bundled into
  `Resources`, and `FirebaseApp.configure()` in `applicationDidFinishLaunching`.
  It pulls ~16 transitive SPM packages (gRPC, BoringSSL, abseil, leveldb,
  nanopb, protobuf, GoogleAppMeasurement/DataTransport/Utilities, Promises,
  GTMSessionFetcher). The bundled `GoogleService-Info.plist` belongs to the
  upstream author's Firebase project, so crash reports never reach this fork.
- `MACOSX_DEPLOYMENT_TARGET` is `10.13` for the macOS targets (a separate `10.8`
  exists for a non-Swift sub-project such as libhangul-objc — leave it).
- There are 8 `@available` / `if #available` / `#unavailable` occurrences across
  `OSX OSXCore Preferences`, guarding 10.14 / 10.15 / 11.0.
- Remaining (kept) SPM dependencies: MASShortcut, Fuse, Alamofire, SwiftUp.

## Order of work

Lowest-risk first, build-verify after each step. Each bucket is its own commit
so the history bisects cleanly.

**C → A → B → D**

1. **C** and **A** are pure source deletions with no build-graph change — do
   them first to establish a stable baseline build.
2. **B** is the Xcode project surgery (highest risk); isolate it in its own
   commit.
3. **D** changes both project settings and code; the compiler validates the code
   flattening immediately.

## Bucket details

### C. Delete orphaned iOS directories
- `git rm -r iOS/ iOSApp/ iOSShared/`.
- No pbxproj edit needed (0 references). Removes the last Fabric/Crashlytics
  source references in the repo.

### A. Remove dead analytics shim
- Delete `OSX/AnswersHelper.swift` (includes the global `let answers`).
- `OSX/GureumAppDelegate.swift`: remove `answers.logLaunch()`, the hourly
  `Timer.scheduledTimer(... AnswersHelper.logUptime ...)`, and
  `answers.logUpdateNotification(updating:)`. Remove the dead comment blocks
  (`// Fabric.with(...)`, `// for 10.12+ ... Timer`).
- `OSX/GureumMenu.swift`: remove the 8 `answers.logMenu(name:)` calls.
- Remove `AnswersHelper.swift` from the project's file reference and the OSX
  target's Compile Sources build phase in `project.pbxproj`.
- Grep-verify no remaining `answers.` references in active macOS sources.

### B. Remove Firebase Crashlytics
- Code (`OSX/GureumAppDelegate.swift`): remove `import Firebase` and
  `FirebaseApp.configure()`. Also remove the
  `UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])`
  registration — it exists only so Crashlytics can capture ObjC exceptions;
  without Crashlytics it would make the input agent hard-crash on exceptions
  instead of using the default handler. Removing it restores default behavior.
- Project (`project.pbxproj`): remove the `FirebaseCrashlytics in Frameworks`
  build file + the framework link, the `XCRemoteSwiftPackageReference
  "firebase-ios-sdk"` package reference and its product dependency, the "Run
  Crashlytics" `PBXShellScriptBuildPhase`, and the `GoogleService-Info.plist`
  file reference + its `Resources` build-phase membership.
- Delete `OSX/GoogleService-Info.plist`.
- Re-resolve packages (`xcodebuild -resolvePackageDependencies` or open in
  Xcode) so `Package.resolved` drops the Firebase graph (~16 packages). Kept:
  MASShortcut, Fuse, Alamofire, SwiftUp.

### D. Deployment target 11.0 + drop @available guards
- Set `MACOSX_DEPLOYMENT_TARGET = 11.0` for the macOS targets (OSX, OSXCore,
  Preferences, and any other Swift macOS target at 10.13). Do not touch the
  10.8 non-Swift sub-project.
- Flatten the 8 availability guards to their always-true branch:
  - `@available(macOS 10.14, *) class NotificationCenterDelegate` → drop the
    attribute.
  - `if #available(macOS 11.0, *) { [.banner, .list] } else { [.alert] }` →
    `[.banner, .list]`.
  - `if #available(macOS 10.14, *) { ...notification setup... }` → run
    unconditionally.
  - `if #available(macOS 10.15, *) { IOHIDRequestAccess(...) }` → call
    unconditionally.
  - Any remaining guards in OSXCore/Preferences → same flattening.
- The compiler flags any guard left dangling, so build success is the check.

## Verification

- After each bucket: build the macOS app and Preferences in Release:
  `xcodebuild -scheme OSX -configuration Release build` and
  `xcodebuild -scheme Preferences -configuration Release build`.
- Run `OSXTests`. The pre-existing `GureumObjCTests.testIPMDServerClientWrapper`
  failure under an unsigned build is a known, unrelated failure and is excluded.
- Final smoke test: ad-hoc sign + install to `/Library/Input Methods`, then
  verify Korean/English switching, the update notification path, and Input
  Monitoring, per the established build gate (fetch tags + version overrides +
  PlistBuddy CFBundleVersion + re-sign with entitlements).

## Risks & rollback

- Highest risk is the pbxproj surgery in **B**. Mitigation: separate commit,
  re-resolve packages, confirm a clean build before moving on.
- **D** is mechanical code flattening; sub-11.0 branches are removed entirely so
  the compiler catches omissions.
- All work on a `cleanup/modernize-macos` branch, one commit per bucket, then a
  PR into `main`.

## Out of scope

- Sparkle adoption (separate future work).
- Reworking the kept dependencies (MASShortcut/Fuse/Alamofire/SwiftUp).
- Any change to upstream-tracked behavior beyond the four buckets above.

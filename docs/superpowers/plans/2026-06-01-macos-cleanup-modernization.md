# macOS Cleanup & Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove dead/abandoned code (AnswersHelper shim, Firebase Crashlytics, orphaned iOS source dirs) and raise the macOS deployment target to 11.0, flattening the availability guards it makes unreachable.

**Architecture:** Four independent cleanup buckets executed lowest-risk first (C → A → B → D), each its own commit, with a build (and, for the final task, test + install) gate after every bucket. No runtime behavior changes — this is deletion/refactoring, so the "test" at each step is a clean Release build plus the existing `OSXTests` suite, not new test-first code.

**Tech Stack:** Swift 5, Xcode project (`Gureum.xcodeproj`), Swift Package Manager dependencies, macOS input method (`Gureum.app`).

---

## Spec

`docs/superpowers/specs/2026-06-01-macos-cleanup-modernization-design.md`

## Verified anchors (as of 2026-06-01)

- Orphaned dirs: `iOS/`, `iOSApp/`, `iOSShared/` — **0** references in `Gureum.xcodeproj/project.pbxproj`.
- `OSX/AnswersHelper.swift` — no-op shim. pbxproj refs: lines **103** (PBXBuildFile), **360** (PBXFileReference), **466** (group child), **1074** (Sources phase). IDs `38B9547B229ED9BC00A9D6E1` (build file) / `38B9547A229ED9BC00A9D6E1` (file ref).
- `answers.` call sites: `OSX/GureumMenu.swift` lines 20, 75, 80, 87, 93, 99, 105, 111; `OSX/GureumAppDelegate.swift` lines 51, 110, 112 (Timer), 115 (comment).
- Firebase in code: `OSX/GureumAppDelegate.swift` line 10 (`import Firebase`), line 61 (`FirebaseApp.configure()`), line 62 (`NSApplicationCrashOnExceptions`), line 97 (dead `// Fabric.with` comment).
- Firebase in pbxproj: `FirebaseCrashlytics in Frameworks` build file (line ~128) + Frameworks phase entry (~409); `XCRemoteSwiftPackageReference "firebase-ios-sdk"` (~911, 1728-1736) + product dependency `FirebaseCrashlytics` (~730, 1783-1786); "Run Crashlytics" `PBXShellScriptBuildPhase` (~716, 1046-1064); `GoogleService-Info.plist` file ref (~391), group child (~454), Resources membership (~129, 972).
- Availability guards (floor will be 11.0 → flatten everything ≤ 11.0, **keep** `OSX 13`):
  - `OSX/UpdateManager.swift:74` `@available(macOS 10.14, *)` on `updateNotificationContent` → remove attribute.
  - `OSX/UpdateManager.swift` `notifyUpdate`: `guard #available(macOS 10.14, *) else { return }` → remove the guard.
  - `OSX/GureumAppDelegate.swift:16` `@available(macOS 10.14, *)` on `NotificationCenterDelegate` → remove.
  - `OSX/GureumAppDelegate.swift:25` `if #available(macOS 11.0, *) { [.banner,.list] } else { [.alert] }` → `[.banner, .list]`.
  - `OSX/GureumAppDelegate.swift:64` `if #available(macOS 10.14, *) { ... }` → run unconditionally.
  - `OSX/GureumAppDelegate.swift:103` `if #available(macOS 10.15, *) { IOHIDRequestAccess(...) }` → call unconditionally.
  - `Preferences/PreferenceViewController.swift:149,164,179` `if #available(OSX 13, *)` → **KEEP** (above the 11.0 floor).
- Deployment target: `Gureum.xcodeproj/project.pbxproj` lines **1492** (Debug) and **1554** (Release), both `MACOSX_DEPLOYMENT_TARGET = 10.13` → `11.0`. No per-target overrides exist. Leave `libhangul-objc/Hangul.xcodeproj` (10.13, ObjC dep) and `hangeul/cdebug/.../debug.xcodeproj` (10.8) untouched.

## Build commands (used throughout)

This machine has no "Developer ID Application" certificate, so the build's
codesign step fails unless signing is disabled. For these cleanup tasks the
**compile** is the gate (the final signed install happens in Task 5), so build
with signing disabled:

```bash
git fetch --tags
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Gureum.xcodeproj -scheme Preferences -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Expected after each task: `** BUILD SUCCEEDED **`.

---

## Task 1 (Bucket C): Delete the orphaned iOS subsystem

**Files:**
- Delete: `iOS/`, `iOSApp/`, `iOSShared/`, `iOSTests/`, `iOSTheme/`, `iOS.xcodeproj/`

The entire iOS subsystem is dead: `iOS.xcodeproj` is a separate Xcode project
referenced by nothing (not `Gureum.xcodeproj`, not the Makefile, not CI — CI only
has a commented-out iOS destination), and all the iOS source/test/theme dirs feed
only it. Deleting the dirs without `iOS.xcodeproj` would leave that project full of
dangling file references, so remove the whole subsystem.

- [ ] **Step 1: Confirm zero references from the macOS project**

```bash
grep -cE 'iOSApp|iOSShared|(^|/)iOS/' Gureum.xcodeproj/project.pbxproj   # -> 0
grep -rnE 'iOS\.xcodeproj' --include='Makefile' --include='*.yml' --include='*.yaml' --include='*.sh' . | grep -vE '^\./(build|docs)/'   # -> empty
```

- [ ] **Step 2: Remove the iOS subsystem**

```bash
git rm -r iOS iOSApp iOSShared iOSTests iOSTheme iOS.xcodeproj
```

- [ ] **Step 3: Build to confirm no impact**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Remove orphaned iOS source directories

iOS/, iOSApp/, iOSShared/ are referenced by no Xcode target (all active
targets are macOS) and still import the sunset Fabric/Crashlytics SDK.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2 (Bucket A): Remove the dead AnswersHelper analytics shim

**Files:**
- Delete: `OSX/AnswersHelper.swift`
- Modify: `OSX/GureumAppDelegate.swift`, `OSX/GureumMenu.swift`
- Modify: `Gureum.xcodeproj/project.pbxproj`

- [ ] **Step 1: Delete the shim file**

```bash
git rm OSX/AnswersHelper.swift
```

- [ ] **Step 2: Remove the 4 pbxproj references**

Remove these exact lines from `Gureum.xcodeproj/project.pbxproj` (match by ID, not line number — line numbers shift):
- `38B9547B229ED9BC00A9D6E1 /* AnswersHelper.swift in Sources */ = {isa = PBXBuildFile; ... };`
- `38B9547A229ED9BC00A9D6E1 /* AnswersHelper.swift */ = {isa = PBXFileReference; ... };`
- the group-children line `38B9547A229ED9BC00A9D6E1 /* AnswersHelper.swift */,`
- the Sources-phase line `38B9547B229ED9BC00A9D6E1 /* AnswersHelper.swift in Sources */,`

- [ ] **Step 3: Remove `answers.*` call sites in `OSX/GureumAppDelegate.swift`**

In `userNotificationCenter(_:didReceive:...)` remove the trailing line:
```swift
        answers.logUpdateNotification(updating: updating)
```
In `applicationDidFinishLaunching` remove:
```swift
        answers.logLaunch()

        Timer.scheduledTimer(timeInterval: 3600, target: answers, selector: #selector(AnswersHelper.logUptime), userInfo: nil, repeats: true)
        // for 10.12+
        // Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
        //   answers.logUptime()
        // }
```
And the dead analytics comments in the `#if DEBUG`/`#else` block:
```swift
            // Fabric.with([Answers.self])
```
```swift
            // Fabric.with([Crashlytics.self, Answers.self])
```
(emit the full file per the full-code edit invariant)

- [ ] **Step 4: Remove the 8 `answers.logMenu(...)` calls in `OSX/GureumMenu.swift`**

Delete each standalone statement (lines 20, 75, 80, 87, 93, 99, 105, 111):
```swift
        answers.logMenu(name: "about")
        answers.logMenu(name: "check-version")
        answers.logMenu(name: "check-experimental")
        answers.logMenu(name: "website")
        answers.logMenu(name: "website-help")
        answers.logMenu(name: "website-source")
        answers.logMenu(name: "website-issues")
        answers.logMenu(name: "website-donation")
```
(emit the full file)

- [ ] **Step 5: Verify no remaining references**

```bash
grep -rnE 'answers\.|AnswersHelper' --include='*.swift' OSX OSXCore Preferences
grep -nE 'AnswersHelper' Gureum.xcodeproj/project.pbxproj
```
Expected: no output from either command.

- [ ] **Step 6: Build**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Remove dead AnswersHelper analytics shim

AnswersHelper was a no-op (all bodies commented out since the Fabric/Answers
SDK was dropped). Remove the file, the global answers instance, the hourly
logUptime Timer, and all answers.log* call sites.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3 (Bucket B): Remove Firebase Crashlytics

**Files:**
- Modify: `OSX/GureumAppDelegate.swift`
- Modify: `Gureum.xcodeproj/project.pbxproj`
- Delete: `OSX/GoogleService-Info.plist`

- [ ] **Step 1: Remove Firebase from `OSX/GureumAppDelegate.swift`**

Remove the import:
```swift
import Firebase
```
At the top of `applicationDidFinishLaunching`, remove both lines:
```swift
        FirebaseApp.configure()
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
```
(The `NSApplicationCrashOnExceptions` flag existed only so Crashlytics could capture ObjC exceptions; without Crashlytics it would make the agent hard-crash instead of using the default handler. Removing it restores default behavior.)
(emit the full file)

- [ ] **Step 2: Remove the Firebase build wiring in `Gureum.xcodeproj/project.pbxproj`**

Remove, by ID/name:
- the `FirebaseCrashlytics in Frameworks` `PBXBuildFile` (`CE31CC0A28109975004659B0`) and its entry in the Frameworks build phase.
- the `XCRemoteSwiftPackageReference "firebase-ios-sdk"` block (`CE21ADEA280A0F6300B54371`) and its entry in the project's `packageReferences` list.
- the `XCSwiftPackageProductDependency` `FirebaseCrashlytics` (`CE31CC0928109975004659B0`) and its entry in the target's `packageProductDependencies`.
- the `Run Crashlytics` `PBXShellScriptBuildPhase` (`CE31CC0B281099D9004659B0`) and its entry in the OSX target's `buildPhases`.
- the `GoogleService-Info.plist` `PBXFileReference` (`CE31CC0C28109B95004659B0`), its group-children entry, the `GoogleService-Info.plist in Resources` `PBXBuildFile` (`CE31CC0D28109B95004659B0`), and its entry in the Resources build phase.

- [ ] **Step 3: Delete the bundled config**

```bash
git rm OSX/GoogleService-Info.plist
```

- [ ] **Step 4: Re-resolve Swift packages**

```bash
xcodebuild -project Gureum.xcodeproj -resolvePackageDependencies
```
Expected: resolution succeeds; the resolved graph no longer lists `firebase-ios-sdk`, `gRPC`, `BoringSSL-GRPC`, `abseil`, `leveldb`, `nanopb`, `GoogleAppMeasurement`, `GoogleDataTransport`, `GoogleUtilities`, `Promises`, `GTMSessionFetcher`, `SwiftProtobuf`. Kept: `MASShortcut`, `Fuse`, `Alamofire`, `SwiftUp`.

- [ ] **Step 5: Verify no remaining Firebase references**

```bash
grep -rnE 'Firebase|Crashlytics|firebase-ios-sdk|GoogleService' --include='*.swift' OSX OSXCore Preferences Gureum.xcodeproj/project.pbxproj
```
Expected: no output.

- [ ] **Step 6: Build**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Remove Firebase Crashlytics

Drop the firebase-ios-sdk SPM dependency, the FirebaseCrashlytics link, the
Run Crashlytics build phase, the bundled GoogleService-Info.plist, and the
FirebaseApp.configure() call. Crash reports went to the upstream author's
Firebase project, never this fork, at the cost of ~16 transitive packages.
Also drop the NSApplicationCrashOnExceptions registration (Crashlytics-only).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4 (Bucket D): Deployment target 11.0 + flatten availability guards

**Files:**
- Modify: `Gureum.xcodeproj/project.pbxproj` (lines 1492, 1554)
- Modify: `OSX/UpdateManager.swift`, `OSX/GureumAppDelegate.swift`

- [ ] **Step 1: Raise the deployment target**

In `Gureum.xcodeproj/project.pbxproj`, change both project-level occurrences:
```
MACOSX_DEPLOYMENT_TARGET = 10.13;
```
to
```
MACOSX_DEPLOYMENT_TARGET = 11.0;
```
Verify exactly two changed and none left at 10.13 in this project:
```bash
grep -nE 'MACOSX_DEPLOYMENT_TARGET' Gureum.xcodeproj/project.pbxproj
```
Expected: two lines, both `= 11.0;`.

- [ ] **Step 2: Flatten guards in `OSX/UpdateManager.swift`**

Remove the attribute on `updateNotificationContent`:
```swift
    /// 업데이트 알림에 표시할 `UNNotificationContent`를 만든다.
    /// 전달(delivery)과 분리해 단위 테스트에서 컨텐츠만 검증할 수 있도록 한다.
    class func updateNotificationContent(info: VersionInfo) -> UNMutableNotificationContent {
```
Remove the guard in `notifyUpdate` so it becomes:
```swift
    class func notifyUpdate(info: VersionInfo) {
        let content = updateNotificationContent(info: info)
        let request = UNNotificationRequest(
            identifier: gureumUpdateNotificationCategoryIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
```
(emit the full file)

- [ ] **Step 3: Flatten guards in `OSX/GureumAppDelegate.swift`**

Remove the class attribute:
```swift
class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
```
Collapse the willPresent body:
```swift
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .list])
    }
```
Run the notification setup unconditionally (drop the `if #available(macOS 10.14, *)` wrapper, keeping its body at one less indent level) and call `IOHIDRequestAccess` unconditionally:
```swift
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
```
(emit the full file)

- [ ] **Step 4: Confirm only the OSX 13 guards remain**

```bash
grep -rnE '@available|#available|#unavailable' --include='*.swift' OSX OSXCore Preferences
```
Expected: only the three `if #available(OSX 13, *)` lines in `Preferences/PreferenceViewController.swift`.

- [ ] **Step 5: Build both schemes**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 build
xcodebuild -project Gureum.xcodeproj -scheme Preferences -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 build
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Raise macOS deployment target to 11.0 and drop dead availability guards

min macOS 10.13 -> 11.0. Flatten the now-unreachable 10.14/10.15/11.0
@available and #available guards in GureumAppDelegate and UpdateManager.
The OSX 13 guards in Preferences stay (above the floor).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full verification, install smoke test, and PR

**Files:** none (verification + integration)

- [ ] **Step 1: Run the unit tests**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 test 2>&1 | tail -40
```
Expected: tests pass. The pre-existing `GureumObjCTests.testIPMDServerClientWrapper` failure under an unsigned build is a known, unrelated failure — note it if it appears, do not treat it as a regression.

- [ ] **Step 2: Install smoke test (per the established build gate)**

Build, ensure `CFBundleVersion` is set (PlistBuddy add `1.13.2` if `${VERSION}` resolved empty), ad-hoc re-sign with `OSX/Gureum.entitlements` (+ `get-task-allow`), install to `/Library/Input Methods` via `osascript ... with administrator privileges`, then re-add the input source and verify:
  - Korean/English switching (CapsLock) works.
  - The update-notification path still presents a notification.
  - Input Monitoring is grantable (cdhash changed → re-add in System Settings).
Expected: all three behave as before this branch.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin cleanup/modernize-macos
gh pr create --base main --head cleanup/modernize-macos \
  --title "macOS cleanup & modernization" \
  --body "$(cat <<'EOF'
Remove dead/abandoned code and modernize the macOS build.

- Delete orphaned iOS source dirs (no target references them).
- Remove the no-op AnswersHelper analytics shim.
- Remove Firebase Crashlytics (SPM dep + build phase + bundled plist + configure call), dropping ~16 transitive packages.
- Raise deployment target 10.13 -> 11.0 and flatten the unreachable availability guards.

Spec: docs/superpowers/specs/2026-06-01-macos-cleanup-modernization-design.md
Plan: docs/superpowers/plans/2026-06-01-macos-cleanup-modernization.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for the implementer

- **Full-code edit invariant:** when a step says "emit the full file", output the entire modified file, not a diff.
- **pbxproj edits:** match by the hex IDs given, not by line number — line numbers shift as earlier lines are removed. After each pbxproj edit, the build is the validation that the project still parses.
- **Order matters:** do C → A → B → D. A clean build after each task is the gate; do not proceed past a red build.
- **Korean strings** in the source (notification titles, comments) are inherently-Korean content — keep them as-is.

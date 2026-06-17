# bomi-input (macOS IME)

Korean input method for macOS, rebranded from **Gureum**. App target `OSX` → `bomi-input.app`.
Engine lives in `OSXCore` → `GureumCore.framework`. Per-client input flows:
`InputController` (`@objc(GureumInputController)`) → `InputReceiver` → `GureumComposer`
(delegate = `HangulComposer`/`RomanComposer`, kept in sync by the `inputMode` setter).

## Identifiers (rebrand)
- Bundle ID: `com.yoropico.inputmethod.bomi-input`
- Input-source IDs: `com.yoropico.inputmethod.bomi-input.<mode>` (han2/han3/han3final/qwerty/…)
- Settings suite (`Configuration.sharedSuiteName`): `com.yoropico.bomi-input`
  - **SANDBOXED**: the app has a container, so this suite is redirected to
    `~/Library/Containers/com.yoropico.inputmethod.bomi-input/Data/Library/Preferences/com.yoropico.bomi-input.plist`.
    Plain `defaults read com.yoropico.bomi-input` reads the WRONG (non-sandbox) `~/Library/Preferences/…`
    and shows stale/missing keys. To inspect real settings use `defaults find <key>` or
    `plutil -p "<container plist>"`. (Bit me once: read "inline off" when it was on.)
- IMK connection name (internal, invisible): `GureumInputMethod_1_Connection`
  (`Info.plist:InputMethodConnectionName` must equal the name passed to `IMKServer`)
- App-target Swift module name: **`bomi_input`** (derived from `PRODUCT_NAME=bomi-input`, hyphen→underscore).

## CRITICAL gotcha — nib/xib custom-class module (broke ALL input)
A renamed `PRODUCT_NAME` changes the Swift module, so any `.xib`/`.storyboard` that hardcodes a
custom Swift class's module breaks at load: AppKit can't find `_TtC6Gureum…` and silently
substitutes `NSObject`. If that class is the app delegate, `applicationDidFinishLaunching` never
runs → `IMKServer` is never created → the IME process launches but accepts no input (input source
reverts to ABC, no logs).
- **Rule:** every `customObject`/`windowController`/`viewController` referencing an in-target Swift
  class MUST carry `customModuleProvider="target"` (which re-bakes the current module at build time).
  Do NOT rely on a literal `customModule="…"` alone.
- Diagnose with: `log show --predicate 'process == "bomi-input"' --last 5m | grep "Unknown class"`.
- Known still-stale: `GureumTests/GureumObjCTests.m` imports `Gureum-Swift.h` (now `bomi_input-Swift.h`).
  Breaks the *test* target only, not the app build/install.

## Build / sign / install (stable signature avoids TCC + input-source churn)
Identity: `Apple Development: yoropico@gmail.com (K83K59TGLX)`, team `G7J2LY4LP9` (login keychain).
```
xcodebuild -project bomi-input.xcodeproj -scheme OSX -configuration Release \
  -derivedDataPath build/DerivedData-signed \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  DEVELOPMENT_TEAM=G7J2LY4LP9 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build
```
Install (sudo has no TTY here → use admin AppleScript):
```
killall bomi-input 2>/dev/null
osascript -e "do shell script \"rm -rf '/Library/Input Methods/bomi-input.app' && \
  cp -R '<built>/bomi-input.app' '/Library/Input Methods/bomi-input.app'\" with administrator privileges"
open "/Library/Input Methods/bomi-input.app"
```
- `CURRENT_PROJECT_VERSION`/`MARKETING_VERSION` overrides are required: apple-generic casts
  `CURRENT_PROJECT_VERSION` to double, so a dotted git-describe value breaks the build. An empty
  `${VERSION}` makes Xcode drop `CFBundleVersion` → the IME won't register.
- Every build dirties `OSX/Version.xcconfig` → `git checkout OSX/Version.xcconfig`; keep it OUT of commits.
- `log` is a zsh builtin → use `/usr/bin/log show …`.
- `pbxproj` still carries upstream team `9384JEL3M9` / "Developer ID Application"; override on the
  command line only — do NOT commit team changes.
- **Tests** (`xcodebuild test -scheme OSX … -only-testing:OSXTests`): the test host IS the IME app, so it
  hangs forever on the `IMKServer` connection-name collision if the installed IME is running. `killall
  bomi-input` BEFORE running tests, then reinstall after. Baseline: 94 run / 1 expected fail
  (`GureumObjCTests testIPMDServerClientWrapper` — stale `Gureum-Swift.h` import, test target only).

## git
One plain commit, explicit `git add` paths, no reset/amend/rebase. Push to `main` needs fresh
per-instance authorization each time. Commit messages in English.
